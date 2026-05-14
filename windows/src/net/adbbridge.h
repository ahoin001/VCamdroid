#pragma once

#include "net/devicebridge.h"
#include "adb.h"

/*
    Concrete `IDeviceBridge` for Android. Thin wrapper over the existing
    `adb` namespace so the legacy free-function call sites in Server keep
    working unchanged while new code can hold the bridge polymorphically.
*/
class AdbBridge : public IDeviceBridge
{
public:
    bool Forward(int port) override { return adb::forward(port); }
    bool Reverse(int port) override { return adb::reverse(port); }
    bool Kill(int port) override    { return adb::kill(port); }
    const char* Name() const override { return "adb"; }
};
