#pragma once

#include "receiver.h"
#include "net/devicedescriptor.h"
#include "net/server.h"
#include "streaming/framereceiver.h"
#include "streamoptions.h"
#include "constants.h"

#include <memory>
#include <vector>

namespace RTSP
{
	/*
		Owns the active video receiver (RTSP for Android, raw TCP for iOS) and
		fans incoming commands out over the existing TCP control channel. The
		receiver is created lazily per Connect2Stream so transport selection
		is fully descriptor-driven.
	*/
	class Manager
	{
	public:
		struct Command
		{
			// v1 — shared with Android
			static const int FRAME              = 0x00;
			static const int RESOLUTION         = 0x01;
			static const int ACTIVATION         = 0x02;
			static const int CAMERA             = 0x03;
			static const int QUALITY            = 0x04;
			static const int CORRECTION_FILTER  = 0x05;
			static const int EFFECT_FILTER      = 0x06;
			static const int ROTATION           = 0x07;
			static const int BITRATE            = 0x08;
			static const int ADAPTIVE_BITRATE   = 0x09;
			static const int STABILIZATION      = 0xA;
			static const int FLASH              = 0xB;
			static const int FOCUS              = 0xC;
			static const int CODEC              = 0xD;
			static const int FPS                = 0xE;
			static const int ZOOM               = 0xF;
			static const int FLIP               = 0x10;

			// v2 — iOS premium controls
			static const int LENS_ZOOM             = 0x20;
			static const int EXPOSURE              = 0x21;
			static const int WHITE_BALANCE         = 0x22;
			static const int STUDIO_MODE           = 0x23;
			static const int EXPOSURE_COMPENSATION = 0x24;
			static const int STABILIZATION_MODE    = 0x25;
			static const int FOCUS_LOCK            = 0x26;
			static const int TAP_TO_FOCUS          = 0x27;
			static const int MIC_ENABLED           = 0x28;
			static const int SNAPSHOT_REQUEST      = 0x29;
			static const int RESET_CAMERA_TO_AUTO  = 0x2A;
			static const int PORTRAIT_MODE         = 0x2B;
		};

		using OnFrameReceivedCallback = Streaming::IFrameReceiver::OnFrameReceivedCallback;
		using OnStatsReceivedCallback = Streaming::IFrameReceiver::OnStatsReceivedCallback;
		using Stats                   = Streaming::IFrameReceiver::Stats;

		Manager(const Server& server,
		        OnFrameReceivedCallback onFrameReceivedCallback,
		        OnStatsReceivedCallback onStatsReceivedCallback);

		void AddDescriptor(DeviceDescriptor& descriptor);
		void RemoveDescriptor(DeviceDescriptor& descriptor);

		void Connect2Stream(int descriptorId, const StreamOptions& options);
		void StopAll();
		void ClearStreamingDevice();

		const std::vector<DeviceDescriptor>& GetDescriptors() const;
		const int& GetStreamingDevice() const;
		bool HasValidStreamingDevice() const;

		// v1 controls (Android + iOS where applicable)
		void SetResolution(unsigned short width, unsigned short height);
		void SetFPS(int fps);
		void SetBitrate(int bitrate);
		void SetAdaptiveBitrate(int min, int max);
		void SetStabilization(bool enabled);
		void SetFlash(bool enabled);
		void SetFocusMode(int mode);
		void SetH265Codec(bool enabled);
		void SwapCamera();
		void Rotate(uint8_t degrees);
		void Zoom(float factor);
		void FlipHorizontally();
		void FlipVertically();

		void ApplyCorrectionFilter(std::string filterName, int value = 0);
		void ApplyEffectFilter(std::string filterName);

		// v2 controls (iOS only)
		void SetLensZoom(float factor);
		void SetExposure(float durationSeconds, float iso);
		void SetWhiteBalance(float temperatureK, float tint);
		void SetStudioMode(bool enabled);
		void SetExposureCompensation(float bias);
		void SetStabilizationMode(int mode);
		/// Pass `lensPosition < 0` to release the lock and return to auto.
		void SetFocusLock(float lensPosition);
		void TapToFocus(float x, float y);
		void SetMicrophoneEnabled(bool enabled);
		void RequestSnapshot();
		void ResetCameraToAuto();
		void SetPortraitMode(bool enabled, uint8_t strength);

	private:
		bool SendToActiveDevice(const unsigned char* bytes, size_t size) const;
		const Server& server;

		OnFrameReceivedCallback onFrameReceivedCallback;
		OnStatsReceivedCallback onStatsReceivedCallback;

		std::vector<DeviceDescriptor> descriptors;
		int streamingDevice;

		std::unique_ptr<Streaming::IFrameReceiver> receiver;

		std::unique_ptr<Streaming::IFrameReceiver> CreateReceiverFor(const DeviceDescriptor& descriptor) const;
	};
};
