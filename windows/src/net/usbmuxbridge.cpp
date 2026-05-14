#include "net/usbmuxbridge.h"

#include "logger.h"

namespace
{
    void LogUnavailable(const char* op, int port)
    {
        logger << "[usbmuxd:" << port << "] " << op
               << " not yet wired up. Install libusbmuxd + libimobiledevice via vcpkg "
                  "and plug them into windows/src/net/usbmuxbridge.cpp to enable USB iOS streaming. "
                  "Wi-Fi connections to iPhones already work today.\n";
    }
}

bool UsbmuxBridge::Forward(int port)
{
    LogUnavailable("Forward", port);
    return false;
}

bool UsbmuxBridge::Reverse(int port)
{
    LogUnavailable("Reverse", port);
    return false;
}

bool UsbmuxBridge::Kill(int /*port*/)
{
    return true;
}
