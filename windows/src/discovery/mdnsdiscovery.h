#pragma once

#include <atomic>
#include <functional>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace Discovery
{
    struct RawDiscoveryRecord
    {
        std::string instanceName;   // e.g. "Alex's iPhone 16 Pro"
        std::string host;           // resolved A record, e.g. "192.168.1.42"
        unsigned short controlPort = 6969;
        unsigned short videoPort   = 8554;
        std::map<std::string, std::string> txtRecords;
    };

    class MdnsBrowser
    {
    public:
        using OnDeviceFound   = std::function<void(const RawDiscoveryRecord&)>;
        using OnDeviceRemoved = std::function<void(const std::string& instanceName)>;

        MdnsBrowser(OnDeviceFound onFound, OnDeviceRemoved onRemoved);
        ~MdnsBrowser();

        /// Begins the background browse loop. Idempotent.
        void Start(const std::string& serviceType = "_vcamdroid._tcp.local.");

        /// Stops the loop and blocks until the worker thread exits.
        void Stop();

        bool IsRunning() const { return running.load(); }

    private:
        void WorkerLoop(std::string serviceType);

        OnDeviceFound onFoundCallback;
        OnDeviceRemoved onRemovedCallback;

        std::atomic<bool> running{ false };
        std::thread worker;
        std::mutex deviceMutex;
        std::map<std::string, RawDiscoveryRecord> knownDevices;

        // Tracks how many consecutive poll cycles a device has been absent.
        // After kMissedCyclesBeforeRemoval cycles, the device is pruned.
        std::map<std::string, int> missedCycles;
        static constexpr int kMissedCyclesBeforeRemoval = 3;
    };
}
