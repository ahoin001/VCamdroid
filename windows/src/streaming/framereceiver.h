#pragma once

#include "rtsp/ffmpeg.h"

#include <functional>
#include <string>

namespace Streaming
{
    /*
        Abstract base for anything that can produce decoded AVFrame*s for the
        VCamdroid pipeline. Both the existing RTSP receiver and the new iOS
        raw-TCP receiver fulfill this contract, which lets RTSP::Manager pick
        the right transport per device without caring about the details.
    */
    class IFrameReceiver
    {
    public:
        struct Stats
        {
            int width = 0;
            int height = 0;
            int fps = 0;
            double bitrate = 0.0;
        };

        using OnFrameReceivedCallback = std::function<void(AVFrame* frame)>;
        using OnStatsReceivedCallback = std::function<void(const Stats& stats)>;

        virtual ~IFrameReceiver() = default;

        /*
            url            - transport-specific endpoint (rtsp://... or vcmd://...)
            transportHint  - "tcp" / "udp" for RTSP; ignored by raw-TCP receivers
            width / height - expected frame dimensions for early decoder setup
        */
        virtual void Start(const std::string& url,
                           const std::string& transportHint,
                           int width,
                           int height) = 0;

        virtual void Stop() = 0;
    };
}
