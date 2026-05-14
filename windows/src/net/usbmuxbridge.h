#pragma once

#include "net/devicebridge.h"

/*
    Concrete `IDeviceBridge` for iOS over libusbmuxd. The full implementation
    relies on Apple Mobile Device Service (installed with iTunes / Apple
    Devices on Windows) and the `libusbmuxd` + `libimobiledevice` vcpkg
    packages.

    Until those dependencies are wired up, this class is a no-op that logs
    a guidance message. Wi-Fi streaming is unaffected and works today; USB
    becomes available once libusbmuxd is integrated (planned for Phase 4).

    Plugging libusbmuxd in is a localized change:

      1. vcpkg install libimobiledevice:x64-windows libusbmuxd:x64-windows
      2. Replace the placeholders below with calls to:
         - `usbmuxd_get_device_list_ex` to enumerate attached iOS devices
         - `usbmuxd_connect` to obtain a tunneled socket for each port
         - thread per-port plumbing to relay bytes to/from a host loopback
           listener that the rest of VCamdroid binds to.
*/
class UsbmuxBridge : public IDeviceBridge
{
public:
    bool Forward(int port) override;
    bool Reverse(int port) override;
    bool Kill(int port) override;
    const char* Name() const override { return "usbmuxd"; }
};
