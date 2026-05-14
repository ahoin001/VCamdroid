#pragma once

#include "ffmpeginterrupt.h"
#include "ffmpeg.h"
#include "streaming/framereceiver.h"

#include <memory>
#include <thread>
#include <atomic>
#include <functional>

namespace RTSP
{
    class Receiver : public Streaming::IFrameReceiver
    {
    public:

        using Stats = Streaming::IFrameReceiver::Stats;
        using OnFrameReceivedCallback = Streaming::IFrameReceiver::OnFrameReceivedCallback;
        using OnStatsReceivedCallback = Streaming::IFrameReceiver::OnStatsReceivedCallback;

        Receiver(OnFrameReceivedCallback frameReceivedListener, OnStatsReceivedCallback statsReceivedCallback);
        virtual ~Receiver();

        void Start(const std::string& url, const std::string& protocol, int width, int height) override;
        void Stop() override;

    private:

        /// <summary>
        /// RTSP receving function that runs in its own thread 
        /// </summary>
        void Loop(int width, int height);
        void WorkerFunc();

        bool OpenConnection(AVFormatContext** ctx);
        bool FindVideoStream(AVFormatContext* ctx, int& streamIdx, AVCodecContext** codecCtx, int width, int height);

        FFmpegInterrupt::State state;

        std::string rtspUrl;
        std::string rtspProtocol;

        OnFrameReceivedCallback onFrameReceivedCallback;
		OnStatsReceivedCallback onStatsReceivedCallback;

        std::thread workerThread;
        std::atomic<bool> isRunning;
    };
};
