#include "discovery/mdnsdiscovery.h"

#include "logger.h"

#ifdef _WIN32
#include <Winsock2.h>
#include <Ws2tcpip.h>
#endif

#include <mdns.h>

#include <chrono>
#include <cstring>
#include <algorithm>
#include <set>

namespace Discovery
{
    // Per-query accumulator passed through mdns user_data pointer.
    // A single browse cycle may produce PTR, SRV, A, TXT responses
    // across multiple callback invocations. We accumulate them here
    // keyed by instance name, then reconcile with knownDevices.
    struct BrowseAccumulator
    {
        struct PendingRecord
        {
            std::string instanceName;
            std::string host;
            unsigned short port = 0;
            std::map<std::string, std::string> txt;
        };
        std::map<std::string, PendingRecord> pending;
    };

    static int QueryCallback(int sock, const struct sockaddr* from, size_t addrlen,
                             mdns_entry_type_t entry, uint16_t query_id, uint16_t rtype,
                             uint16_t rclass, uint32_t ttl, const void* data, size_t size,
                             size_t name_offset, size_t name_length, size_t record_offset,
                             size_t record_length, void* user_data)
    {
        auto* acc = static_cast<BrowseAccumulator*>(user_data);
        char nameBuf[256]{};
        char entryBuf[256]{};

        // Extract the entry name (the name label from the DNS record).
        mdns_string_t entryStr = mdns_string_extract(data, size, &name_offset, entryBuf, sizeof(entryBuf));

        if (rtype == MDNS_RECORDTYPE_PTR)
        {
            mdns_string_t ptr = mdns_record_parse_ptr(data, size, record_offset, record_length,
                                                      nameBuf, sizeof(nameBuf));
            if (ptr.length > 0)
            {
                std::string instanceName(ptr.str, ptr.length);
                // Strip the service suffix to get a human-readable name.
                auto suffixPos = instanceName.find("._vcamdroid._tcp.local.");
                std::string displayName = (suffixPos != std::string::npos)
                    ? instanceName.substr(0, suffixPos)
                    : instanceName;
                acc->pending[instanceName].instanceName = displayName;
            }
        }
        else if (rtype == MDNS_RECORDTYPE_SRV)
        {
            mdns_record_srv_t srv = mdns_record_parse_srv(data, size, record_offset, record_length,
                                                          nameBuf, sizeof(nameBuf));
            std::string entryName(entryStr.str, entryStr.length);
            auto& rec = acc->pending[entryName];
            rec.port = srv.port;
            if (rec.instanceName.empty())
            {
                auto suffixPos = entryName.find("._vcamdroid._tcp.local.");
                rec.instanceName = (suffixPos != std::string::npos)
                    ? entryName.substr(0, suffixPos) : entryName;
            }
        }
        else if (rtype == MDNS_RECORDTYPE_A)
        {
            struct sockaddr_in addr;
            mdns_record_parse_a(data, size, record_offset, record_length, &addr);
            char addrStr[64]{};
            inet_ntop(AF_INET, &addr.sin_addr, addrStr, sizeof(addrStr));
            std::string entryName(entryStr.str, entryStr.length);
            // A records often arrive keyed by hostname, not instance name.
            // Associate with any pending record that lacks a host.
            for (auto& [key, rec] : acc->pending)
            {
                if (rec.host.empty())
                    rec.host = addrStr;
            }
        }
        else if (rtype == MDNS_RECORDTYPE_TXT)
        {
            mdns_record_txt_t txtRecords[16]{};
            size_t parsed = mdns_record_parse_txt(data, size, record_offset, record_length,
                                                  txtRecords, 16);
            std::string entryName(entryStr.str, entryStr.length);
            auto& rec = acc->pending[entryName];
            for (size_t i = 0; i < parsed; ++i)
            {
                std::string key(txtRecords[i].key.str, txtRecords[i].key.length);
                std::string val;
                if (txtRecords[i].value.str && txtRecords[i].value.length > 0)
                    val.assign(txtRecords[i].value.str, txtRecords[i].value.length);
                rec.txt[key] = val;
            }
        }

        return 0; // continue parsing
    }

    // -----------------------------------------------------------------------

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
        missedCycles.clear();
    }

    void MdnsBrowser::WorkerLoop(std::string serviceType)
    {
#ifdef _WIN32
        WSADATA wsaData;
        WSAStartup(MAKEWORD(2, 2), &wsaData);
#endif

        int sock = mdns_socket_open_ipv4(nullptr);
        if (sock < 0)
        {
            logger << "[mdns] Failed to open mDNS socket. Auto-discovery disabled.\n";
#ifdef _WIN32
            WSACleanup();
#endif
            running.store(false);
            return;
        }

        logger << "[mdns] Browser started for " << serviceType << "\n";

        // Query buffer — 2KB is generous for browse queries.
        constexpr size_t kBufferCapacity = 2048;
        void* buffer = malloc(kBufferCapacity);

        while (running.load())
        {
            int queryId = mdns_query_send(sock, MDNS_RECORDTYPE_PTR,
                                          serviceType.c_str(), serviceType.size(),
                                          buffer, kBufferCapacity, 0);
            if (queryId < 0)
            {
                logger << "[mdns] Query send failed, retrying...\n";
                std::this_thread::sleep_for(std::chrono::seconds(3));
                continue;
            }

            BrowseAccumulator acc;

            // Collect responses over a 2-second window.
            auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(1500);
            while (std::chrono::steady_clock::now() < deadline && running.load())
            {
                // Non-blocking recv with short timeout via select.
                fd_set readfds;
                FD_ZERO(&readfds);
                FD_SET(sock, &readfds);
                struct timeval tv;
                tv.tv_sec = 0;
                tv.tv_usec = 250000; // 250ms

                if (select(sock + 1, &readfds, nullptr, nullptr, &tv) > 0)
                {
                    mdns_query_recv(sock, buffer, kBufferCapacity, QueryCallback, &acc, queryId);
                }
            }

            // Reconcile accumulated records with known devices.
            {
                std::lock_guard<std::mutex> lock(deviceMutex);

                std::set<std::string> seenThisCycle;

                for (auto& [key, pending] : acc.pending)
                {
                    if (pending.instanceName.empty() || pending.host.empty())
                        continue;

                    seenThisCycle.insert(pending.instanceName);

                    RawDiscoveryRecord record;
                    record.instanceName = pending.instanceName;
                    record.host = pending.host;
                    record.txtRecords = std::move(pending.txt);

                    // Extract ports from TXT records if available, otherwise use defaults.
                    if (auto it = record.txtRecords.find("ctl"); it != record.txtRecords.end())
                    {
                        try { record.controlPort = static_cast<unsigned short>(std::stoi(it->second)); }
                        catch (...) {}
                    }
                    if (auto it = record.txtRecords.find("vid"); it != record.txtRecords.end())
                    {
                        try { record.videoPort = static_cast<unsigned short>(std::stoi(it->second)); }
                        catch (...) {}
                    }
                    // SRV port overrides TXT if present (SRV is authoritative).
                    if (pending.port > 0)
                        record.controlPort = pending.port;

                    auto existing = knownDevices.find(record.instanceName);
                    if (existing == knownDevices.end())
                    {
                        logger << "[mdns] Discovered: " << record.instanceName
                               << " @ " << record.host << ":" << record.controlPort << "\n";
                        knownDevices[record.instanceName] = record;
                        missedCycles.erase(record.instanceName);
                        if (onFoundCallback) onFoundCallback(record);
                    }
                    else
                    {
                        // Update host/port if changed (e.g. DHCP re-assignment).
                        bool changed = (existing->second.host != record.host)
                                    || (existing->second.controlPort != record.controlPort)
                                    || (existing->second.videoPort != record.videoPort);
                        if (changed)
                        {
                            existing->second = record;
                            if (onFoundCallback) onFoundCallback(record);
                        }
                        missedCycles.erase(record.instanceName);
                    }
                }

                // Increment miss counter for devices not seen this cycle.
                std::vector<std::string> toRemove;
                for (auto& [name, _] : knownDevices)
                {
                    if (seenThisCycle.find(name) == seenThisCycle.end())
                    {
                        missedCycles[name]++;
                        if (missedCycles[name] >= kMissedCyclesBeforeRemoval)
                            toRemove.push_back(name);
                    }
                }

                for (const auto& name : toRemove)
                {
                    logger << "[mdns] Lost: " << name << "\n";
                    knownDevices.erase(name);
                    missedCycles.erase(name);
                    if (onRemovedCallback) onRemovedCallback(name);
                }
            }

            // Wait before next browse cycle.
            for (int i = 0; i < 10 && running.load(); ++i)
                std::this_thread::sleep_for(std::chrono::milliseconds(300));
        }

        free(buffer);
        mdns_socket_close(sock);

#ifdef _WIN32
        WSACleanup();
#endif

        logger << "[mdns] Browser exiting.\n";
    }
}
