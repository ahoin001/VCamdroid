#pragma once

#include <string>

/*
    Abstract USB-tunnel bridge. Implementations wrap a host-side daemon that
    forwards TCP ports between this PC and a connected mobile device. Two
    concrete implementations exist:

      - AdbBridge   (windows/src/net/adbbridge.h)    Android via adb.exe.
      - UsbmuxBridge (windows/src/net/usbmuxbridge.h) iOS via libusbmuxd.

    The DirectShow / RTSP / TCP receiver layers remain transport-agnostic.
*/
class IDeviceBridge
{
public:
    virtual ~IDeviceBridge() = default;

    /// Forwards the device's TCP `port` to the host's `localhost:port`.
    /// Returns true on success.
    virtual bool Forward(int port) = 0;

    /// Reverses host's TCP `port` so the device can reach it via
    /// `localhost:port`. Returns true on success.
    virtual bool Reverse(int port) = 0;

    /// Tears down both forward and reverse mappings.
    virtual bool Kill(int port) = 0;

    /// Human-readable name for logs / UI.
    virtual const char* Name() const = 0;
};
