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
    /*
        Background mDNS / Bonjour browser for `_vcamdroid._tcp.` services.
        Notifies a listener whenever an iOS device joins or leaves the LAN.

        The intent is for the GUI to consume these notifications and
        auto-populate the source dropdown, removing the manual host-entry
        step. iOS devices already advertise themselves via
        `BonjourPublisher.swift`.

        ──────────────────────────────────────────────────────────────────
        Wiring up a real mDNS implementation
        ──────────────────────────────────────────────────────────────────
        For zero new dependencies the simplest production-grade option is
        the public-domain single-header library `mjansson/mdns`:

            https://github.com/mjansson/mdns

        Drop `mdns.h` into `windows/3rdparty/mdns/` and replace the polling
        body in `mdnsdiscovery.cpp` with calls to:

            - mdns_socket_open_ipv4(...)
            - mdns_query_send(..., MDNS_RECORDTYPE_PTR, "_vcamdroid._tcp.local.")
            - mdns_query_recv(..., callback)

        Alternative paths if you'd prefer:

            * Windows DNS-SD (`dnsapi.dll`, Win10+) via `DnsServiceBrowse`.
            * Apple Bonjour SDK for Windows (`dns_sd.h`) via `DNSServiceBrowse`.

        Either replacement maps cleanly onto the `RawDiscoveryRecord`
        push-callback contract below, so callers do not change.
    */
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
    };
}
