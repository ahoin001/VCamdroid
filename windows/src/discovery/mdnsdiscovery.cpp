#include "discovery/mdnsdiscovery.h"

#include "logger.h"

#include <chrono>

namespace Discovery
{
    MdnsBrowser::MdnsBrowser(OnDeviceFound onFound, OnDeviceRemoved onRemoved)
        : onFoundCallback(std::move(onFound)),
          onRemovedCallback(std::move(onRemoved))
    {
    }

    MdnsBrowser::~MdnsBrowser()
    {
        Stop();
    }

    void MdnsBrowser::Start(const std::string& serviceType)
    {
        if (running.exchange(true)) return;
        worker = std::thread(&MdnsBrowser::WorkerLoop, this, serviceType);
    }

    void MdnsBrowser::Stop()
    {
        if (!running.exchange(false)) return;
        if (worker.joinable()) worker.join();

        std::lock_guard<std::mutex> lock(deviceMutex);
        for (const auto& [name, _] : knownDevices)
        {
            if (onRemovedCallback) onRemovedCallback(name);
        }
        knownDevices.clear();
    }

    void MdnsBrowser::WorkerLoop(std::string serviceType)
    {
        logger << "[mdns] Browser placeholder running for " << serviceType
               << ". Integrate mjansson/mdns (or Windows DNS-SD) to enable auto-discovery.\n";

        // Polling cadence chosen to match a typical mDNS browse period.
        // Even with the integration in place we want a soft refresh window
        // so devices that lapse without a TTL-aware update get pruned.
        while (running.load())
        {
            std::this_thread::sleep_for(std::chrono::seconds(2));
        }

        logger << "[mdns] Browser exiting.\n";
    }
}
