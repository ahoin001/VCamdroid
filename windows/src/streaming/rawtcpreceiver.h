#pragma once

#include "streaming/framereceiver.h"
#include "rtsp/ffmpeg.h"

#include <asio.hpp>
#include <atomic>
#include <thread>
#include <string>

namespace Streaming
{
    /*
        Raw-TCP video receiver for iOS clients. Connects out to vcmd://<host>:<port>
        and consumes:

            [4-byte magic "VCMD"][1-byte version][1-byte codec]
            [2-byte width BE][2-byte height BE][1-byte fps]
            then repeatedly:
            [4-byte NAL length BE][N bytes raw NAL unit]

        Each NAL is converted to Annex-B (00 00 00 01 prefix) before being
        handed to ffmpeg's avcodec_send_packet. This mirrors how the existing
        RTSP::Receiver feeds frames downstream so the rest of the application
        (preview canvas, DirectShow sink, snapshot manager) needs no changes.
    */
    class RawTCPReceiver : public IFrameReceiver
    {
    public:
        RawTCPReceiver(OnFrameReceivedCallback frameReceivedCallback,
                       OnStatsReceivedCallback statsReceivedCallback);
        ~RawTCPReceiver() override;

        // url is "vcmd://<host>:<port>/...". transportHint is unused (always TCP).
        void Start(const std::string& url,
                   const std::string& transportHint,
                   int width,
                   int height) override;

        void Stop() override;

    private:
        void WorkerFunc(std::string host, unsigned short port);

        bool ReadExact(asio::ip::tcp::socket& socket, uint8_t* dst, size_t size);
        bool ReadHeader(asio::ip::tcp::socket& socket, int& codecOut, int& widthOut, int& heightOut, int& fpsOut);
        bool ReadNalUnit(asio::ip::tcp::socket& socket, std::vector<uint8_t>& outAnnexB);

        OnFrameReceivedCallback onFrame;
        OnStatsReceivedCallback onStats;

        std::atomic<bool> isRunning;
        std::thread worker;

        int expectedWidth;
        int expectedHeight;
    };
}
