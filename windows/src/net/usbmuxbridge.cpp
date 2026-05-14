#include "net/usbmuxbridge.h"

#include "logger.h"

#ifdef VCAMDROID_HAS_USBMUXD

#include <Winsock2.h>
#include <Ws2tcpip.h>

#include <cstring>
#include <vector>

// ---------------------------------------------------------------------------
// Real libusbmuxd implementation
// ---------------------------------------------------------------------------

UsbmuxBridge::UsbmuxBridge() = default;

UsbmuxBridge::~UsbmuxBridge()
{
    // Tear down all relay threads.
    std::lock_guard<std::mutex> lock(relayMutex);
    for (auto& [port, relay] : relays)
    {
        relay->running = false;
        if (relay->listenSocket >= 0)
            closesocket(relay->listenSocket);
        if (relay->thread.joinable())
            relay->thread.join();
    }
    relays.clear();
}

bool UsbmuxBridge::HasConnectedDevice() const
{
    usbmuxd_device_info_t* devices = nullptr;
    int count = usbmuxd_get_device_list(&devices);
    if (count > 0 && devices)
    {
        usbmuxd_device_list_free(&devices);
        return true;
    }
    if (devices) usbmuxd_device_list_free(&devices);
    return false;
}

bool UsbmuxBridge::EnsureDevice()
{
    usbmuxd_device_info_t* devices = nullptr;
    int count = usbmuxd_get_device_list(&devices);
    if (count <= 0 || !devices)
    {
        logger << "[usbmuxd] No iOS devices found via USB.\n";
        if (devices) usbmuxd_device_list_free(&devices);
        return false;
    }
    cachedDeviceHandle = devices[0].handle;
    deviceEnumerated = true;
    logger << "[usbmuxd] Found device: " << devices[0].product_id
           << " (UDID: " << devices[0].udid << ")\n";
    usbmuxd_device_list_free(&devices);
    return true;
}

bool UsbmuxBridge::Forward(int port)
{
    std::lock_guard<std::mutex> lock(relayMutex);

    if (relays.count(port))
    {
        logger << "[usbmuxd:" << port << "] Forward already active.\n";
        return true;
    }

    if (!EnsureDevice()) return false;

    // Create a local TCP listening socket on localhost:port. When a client
    // connects to it, we bridge traffic to the iOS device's port via
    // usbmuxd_connect.
    SOCKET listenSock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listenSock == INVALID_SOCKET)
    {
        logger << "[usbmuxd:" << port << "] Failed to create listen socket.\n";
        return false;
    }

    // Allow port reuse so we can rebind quickly after a restart.
    int reuseVal = 1;
    setsockopt(listenSock, SOL_SOCKET, SO_REUSEADDR, (const char*)&reuseVal, sizeof(reuseVal));

    struct sockaddr_in bindAddr{};
    bindAddr.sin_family = AF_INET;
    bindAddr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bindAddr.sin_port = htons(static_cast<u_short>(port));

    if (bind(listenSock, (struct sockaddr*)&bindAddr, sizeof(bindAddr)) != 0)
    {
        logger << "[usbmuxd:" << port << "] Failed to bind listen socket.\n";
        closesocket(listenSock);
        return false;
    }

    if (listen(listenSock, 1) != 0)
    {
        logger << "[usbmuxd:" << port << "] Failed to listen.\n";
        closesocket(listenSock);
        return false;
    }

    auto relay = std::make_unique<Relay>();
    relay->listenSocket = static_cast<int>(listenSock);
    auto* relayPtr = relay.get();

    relay->thread = std::thread(&UsbmuxBridge::RelayWorker, this, port, relayPtr);
    relays[port] = std::move(relay);

    logger << "[usbmuxd:" << port << "] Forward active (listening on localhost:" << port << ").\n";
    return true;
}

bool UsbmuxBridge::Reverse(int port)
{
    // usbmuxd only supports forward tunneling (host-to-device). Reverse is
    // the same as Forward for our use case: the iOS device's port becomes
    // available on localhost.
    return Forward(port);
}

bool UsbmuxBridge::Kill(int port)
{
    std::lock_guard<std::mutex> lock(relayMutex);

    auto it = relays.find(port);
    if (it == relays.end()) return true;

    it->second->running = false;
    if (it->second->listenSocket >= 0)
        closesocket(it->second->listenSocket);

    if (it->second->thread.joinable())
        it->second->thread.join();

    relays.erase(it);

    logger << "[usbmuxd:" << port << "] Forward killed.\n";
    return true;
}

void UsbmuxBridge::RelayWorker(int port, Relay* relay)
{
    constexpr size_t kBufSize = 64 * 1024;
    std::vector<char> buf(kBufSize);

    while (relay->running)
    {
        // Wait for a local client to connect.
        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(relay->listenSocket, &readfds);
        struct timeval tv{ 0, 500000 }; // 500ms

        int sel = select(relay->listenSocket + 1, &readfds, nullptr, nullptr, &tv);
        if (sel <= 0) continue;

        struct sockaddr_in clientAddr{};
        int addrLen = sizeof(clientAddr);
        SOCKET clientSock = accept(relay->listenSocket, (struct sockaddr*)&clientAddr, &addrLen);
        if (clientSock == INVALID_SOCKET) continue;

        logger << "[usbmuxd:" << port << "] Client connected, opening tunnel to device.\n";

        // Connect to the device port via usbmuxd.
        int deviceFd = usbmuxd_connect(cachedDeviceHandle, static_cast<unsigned short>(port));
        if (deviceFd < 0)
        {
            logger << "[usbmuxd:" << port << "] usbmuxd_connect failed.\n";
            closesocket(clientSock);
            continue;
        }

        relay->deviceHandle = deviceFd;

        // Bidirectional relay loop.
        while (relay->running)
        {
            fd_set fds;
            FD_ZERO(&fds);
            FD_SET(clientSock, &fds);
            FD_SET(deviceFd, &fds);
            int maxFd = (int)((clientSock > (SOCKET)deviceFd) ? clientSock : deviceFd);

            struct timeval relayTv{ 0, 100000 }; // 100ms
            int ready = select(maxFd + 1, &fds, nullptr, nullptr, &relayTv);
            if (ready < 0) break;
            if (ready == 0) continue;

            // Client -> Device
            if (FD_ISSET(clientSock, &fds))
            {
                int n = recv(clientSock, buf.data(), (int)kBufSize, 0);
                if (n <= 0) break;
                int sent = usbmuxd_send(deviceFd, buf.data(), (uint32_t)n, nullptr);
                if (sent < 0) break;
            }

            // Device -> Client
            if (FD_ISSET(deviceFd, &fds))
            {
                uint32_t received = 0;
                int rc = usbmuxd_recv(deviceFd, buf.data(), (uint32_t)kBufSize, &received);
                if (rc < 0 || received == 0) break;
                int totalSent = 0;
                while (totalSent < (int)received)
                {
                    int s = send(clientSock, buf.data() + totalSent, (int)received - totalSent, 0);
                    if (s <= 0) goto end_relay;
                    totalSent += s;
                }
            }
        }
        end_relay:

        logger << "[usbmuxd:" << port << "] Relay session ended.\n";
        usbmuxd_disconnect(deviceFd);
        closesocket(clientSock);
        relay->deviceHandle = -1;
    }
}

#else

// ---------------------------------------------------------------------------
// Stub implementation when libusbmuxd is not available
// ---------------------------------------------------------------------------

namespace
{
    void LogUnavailable(const char* op, int port)
    {
        logger << "[usbmuxd:" << port << "] " << op
               << " not available (build without VCAMDROID_HAS_USBMUXD). "
                  "Install libusbmuxd + libimobiledevice via vcpkg and rebuild "
                  "with VCAMDROID_HAS_USBMUXD to enable USB iOS streaming.\n";
    }
}

UsbmuxBridge::UsbmuxBridge() = default;
UsbmuxBridge::~UsbmuxBridge() = default;

bool UsbmuxBridge::Forward(int port)  { LogUnavailable("Forward", port); return false; }
bool UsbmuxBridge::Reverse(int port)  { LogUnavailable("Reverse", port); return false; }
bool UsbmuxBridge::Kill(int /*port*/) { return true; }
bool UsbmuxBridge::HasConnectedDevice() const { return false; }

#endif
