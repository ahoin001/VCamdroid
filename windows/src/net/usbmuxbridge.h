#pragma once

#include "net/devicebridge.h"

#include <map>
#include <thread>
#include <atomic>
#include <mutex>

#ifdef VCAMDROID_HAS_USBMUXD
#include <usbmuxd.h>
#endif

/// Concrete `IDeviceBridge` for iOS over libusbmuxd. Tunnels TCP ports
/// between the host and a USB-connected iOS device so the rest of the
/// VCamdroid stack (which binds to `localhost:<port>`) works identically
/// to the ADB path.
///
/// Requires:
///   - Apple Mobile Device Service (comes with iTunes / Apple Devices)
///   - libusbmuxd + libimobiledevice vcpkg packages
///   - `VCAMDROID_HAS_USBMUXD` preprocessor define
class UsbmuxBridge : public IDeviceBridge
{
public:
    UsbmuxBridge();
    ~UsbmuxBridge();

    bool Forward(int port) override;
    bool Reverse(int port) override;
    bool Kill(int port) override;
    const char* Name() const override { return "usbmuxd"; }

    /// Returns true if at least one iOS device is USB-attached.
    bool HasConnectedDevice() const;

private:
#ifdef VCAMDROID_HAS_USBMUXD
    struct Relay
    {
        std::atomic<bool> running{ true };
        std::thread thread;
        int listenSocket = -1;
        int deviceHandle = -1;
    };

    std::mutex relayMutex;
    std::map<int, std::unique_ptr<Relay>> relays;

    uint32_t cachedDeviceHandle = 0;
    bool deviceEnumerated = false;

    bool EnsureDevice();
    void RelayWorker(int port, Relay* relay);
#endif
};
