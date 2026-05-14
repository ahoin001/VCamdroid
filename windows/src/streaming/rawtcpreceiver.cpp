#include "streaming/rawtcpreceiver.h"

#include "logger.h"

#include <chrono>
#include <cstring>
#include <regex>

namespace
{
    using tcp = asio::ip::tcp;

    // Parses "vcmd://<host>:<port>/..." into (host, port). Returns false if
    // the URL doesn't conform. Anything after the optional path is ignored.
    bool ParseVcmdUrl(const std::string& url, std::string& host, unsigned short& port)
    {
        static const std::regex pattern(R"(^vcmd://([^:/]+):(\d+)(?:/.*)?$)", std::regex::icase);
        std::smatch m;
        if (!std::regex_match(url, m, pattern))
            return false;

        host = m[1].str();
        const long parsed = std::stol(m[2].str());
        if (parsed <= 0 || parsed > 0xFFFF) return false;
        port = static_cast<unsigned short>(parsed);
        return true;
    }

    uint16_t ReadU16BE(const uint8_t* p) { return (uint16_t(p[0]) << 8) | uint16_t(p[1]); }
    uint32_t ReadU32BE(const uint8_t* p)
    {
        return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16)
             | (uint32_t(p[2]) << 8)  |  uint32_t(p[3]);
    }
}

namespace Streaming
{
    RawTCPReceiver::RawTCPReceiver(OnFrameReceivedCallback frameReceivedCallback,
                                   OnStatsReceivedCallback statsReceivedCallback)
        : onFrame(std::move(frameReceivedCallback)),
          onStats(std::move(statsReceivedCallback)),
          isRunning(false),
          expectedWidth(0),
          expectedHeight(0)
    {
    }

    RawTCPReceiver::~RawTCPReceiver()
    {
        Stop();
    }

    void RawTCPReceiver::Start(const std::string& url, const std::string& /*transportHint*/, int width, int height)
    {
        if (isRunning) return;

        std::string host;
        unsigned short port = 0;
        if (!ParseVcmdUrl(url, host, port))
        {
            logger << "[RawTCP] Invalid VCMD URL: " << url << std::endl;
            return;
        }

        expectedWidth = width;
        expectedHeight = height;
        isRunning = true;
        worker = std::thread(&RawTCPReceiver::WorkerFunc, this, host, port);
    }

    void RawTCPReceiver::Stop()
    {
        if (!isRunning) return;
        isRunning = false;
        if (worker.joinable())
            worker.join();
    }

    void RawTCPReceiver::WorkerFunc(std::string host, unsigned short port)
    {
        logger << "[RawTCP] Connecting to " << host << ":" << port << std::endl;

        asio::io_context io;
        tcp::socket socket(io);

        try
        {
            tcp::resolver resolver(io);
            auto endpoints = resolver.resolve(host, std::to_string(port));
            asio::connect(socket, endpoints);
            socket.set_option(tcp::no_delay(true));
        }
        catch (std::exception& e)
        {
            logger << "[RawTCP] Connect error: " << e.what() << std::endl;
            isRunning = false;
            return;
        }

        int codecId = 0, w = 0, h = 0, fps = 0;
        if (!ReadHeader(socket, codecId, w, h, fps))
        {
            logger << "[RawTCP] Header read failed; closing.\n";
            isRunning = false;
            return;
        }

        if (expectedWidth == 0)  expectedWidth = w;
        if (expectedHeight == 0) expectedHeight = h;

        // Select the right ffmpeg codec.
        AVCodecID avCodecId = (codecId == 0x02) ? AV_CODEC_ID_HEVC : AV_CODEC_ID_H264;
        const AVCodec* codec = avcodec_find_decoder(avCodecId);
        if (!codec)
        {
            logger << "[RawTCP] Decoder not found for codecId=" << codecId << std::endl;
            isRunning = false;
            return;
        }

        AVCodecContext* codecCtx = avcodec_alloc_context3(codec);
        codecCtx->width = (expectedWidth > 0) ? expectedWidth : w;
        codecCtx->height = (expectedHeight > 0) ? expectedHeight : h;
        codecCtx->pix_fmt = AV_PIX_FMT_YUV420P;
        codecCtx->thread_count = 4;
        codecCtx->thread_type = FF_THREAD_SLICE;
        codecCtx->flags |= AV_CODEC_FLAG_LOW_DELAY;

        if (avcodec_open2(codecCtx, codec, nullptr) < 0)
        {
            logger << "[RawTCP] avcodec_open2 failed.\n";
            avcodec_free_context(&codecCtx);
            isRunning = false;
            return;
        }

        AVFrame* frame = av_frame_alloc();
        AVPacket* packet = av_packet_alloc();

        std::vector<uint8_t> annexB;
        annexB.reserve(256 * 1024);

        auto lastStats = std::chrono::steady_clock::now();
        int64_t byteAccum = 0;
        int frameAccum = 0;

        logger << "[RawTCP] Decoding " << codec->name << " " << w << "x" << h << "@" << fps << "fps\n";

        while (isRunning)
        {
            if (!ReadNalUnit(socket, annexB))
                break;

            byteAccum += annexB.size();

            packet->data = annexB.data();
            packet->size = static_cast<int>(annexB.size());

            if (avcodec_send_packet(codecCtx, packet) == 0)
            {
                while (avcodec_receive_frame(codecCtx, frame) == 0)
                {
                    frameAccum++;
                    if (onFrame)
                        onFrame(frame);
                }
            }

            auto now = std::chrono::steady_clock::now();
            auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(now - lastStats).count();
            if (elapsedMs >= 1000)
            {
                Stats stats{};
                stats.width = codecCtx->width;
                stats.height = codecCtx->height;
                stats.fps = static_cast<int>(frameAccum / (elapsedMs / 1000.0));
                stats.bitrate = (byteAccum * 8.0) / 1'000'000.0 / (elapsedMs / 1000.0);
                if (onStats) onStats(stats);
                byteAccum = 0;
                frameAccum = 0;
                lastStats = now;
            }
        }

        logger << "[RawTCP] Receiver thread exiting.\n";
        av_frame_free(&frame);
        av_packet_free(&packet);
        avcodec_free_context(&codecCtx);

        asio::error_code ec;
        socket.close(ec);
        isRunning = false;
    }

    bool RawTCPReceiver::ReadExact(asio::ip::tcp::socket& socket, uint8_t* dst, size_t size)
    {
        size_t total = 0;
        while (total < size && isRunning)
        {
            asio::error_code ec;
            size_t got = socket.read_some(asio::buffer(dst + total, size - total), ec);
            if (ec || got == 0) return false;
            total += got;
        }
        return total == size;
    }

    bool RawTCPReceiver::ReadHeader(asio::ip::tcp::socket& socket, int& codecOut, int& widthOut, int& heightOut, int& fpsOut)
    {
        uint8_t hdr[11] = { 0 };
        if (!ReadExact(socket, hdr, sizeof(hdr))) return false;

        // Magic "VCMD" (0x56 43 4D 44)
        if (hdr[0] != 0x56 || hdr[1] != 0x43 || hdr[2] != 0x4D || hdr[3] != 0x44)
        {
            logger << "[RawTCP] Bad magic on stream header.\n";
            return false;
        }
        const uint8_t version = hdr[4];
        if (version != 0x01)
        {
            logger << "[RawTCP] Unsupported stream version " << int(version) << std::endl;
            return false;
        }
        codecOut  = hdr[5];
        widthOut  = ReadU16BE(hdr + 6);
        heightOut = ReadU16BE(hdr + 8);
        fpsOut    = hdr[10];
        return true;
    }

    bool RawTCPReceiver::ReadNalUnit(asio::ip::tcp::socket& socket, std::vector<uint8_t>& outAnnexB)
    {
        uint8_t lengthBytes[4];
        if (!ReadExact(socket, lengthBytes, sizeof(lengthBytes))) return false;
        const uint32_t nalSize = ReadU32BE(lengthBytes);
        if (nalSize == 0 || nalSize > 16 * 1024 * 1024)
        {
            logger << "[RawTCP] Refusing absurd NAL size " << nalSize << std::endl;
            return false;
        }

        // Annex-B start code + payload.
        outAnnexB.resize(4 + nalSize);
        outAnnexB[0] = 0x00;
        outAnnexB[1] = 0x00;
        outAnnexB[2] = 0x00;
        outAnnexB[3] = 0x01;
        return ReadExact(socket, outAnnexB.data() + 4, nalSize);
    }
}
