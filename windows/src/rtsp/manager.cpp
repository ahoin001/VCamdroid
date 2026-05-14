#include "rtsp/manager.h"

#include "logger.h"
#include "net/serializer.h"
#include "streaming/rawtcpreceiver.h"

#include <cstring>

namespace
{
	// Helper for the iOS-specific commands. Encodes a single float in
	// little-endian (matching the existing Zoom/Bitrate encoders).
	void AppendFloat32LE(std::vector<uint8_t>& out, float value)
	{
		uint32_t bits;
		std::memcpy(&bits, &value, sizeof(float));
		out.push_back(static_cast<uint8_t>(bits & 0xFF));
		out.push_back(static_cast<uint8_t>((bits >> 8) & 0xFF));
		out.push_back(static_cast<uint8_t>((bits >> 16) & 0xFF));
		out.push_back(static_cast<uint8_t>((bits >> 24) & 0xFF));
	}
}

namespace RTSP
{
	Manager::Manager(const Server& server,
	                 OnFrameReceivedCallback onFrameReceivedCallback,
	                 OnStatsReceivedCallback onStatsReceivedCallback)
		: server(server),
		  onFrameReceivedCallback(std::move(onFrameReceivedCallback)),
		  onStatsReceivedCallback(std::move(onStatsReceivedCallback)),
		  streamingDevice(-1)
	{
	}

	void Manager::AddDescriptor(DeviceDescriptor& descriptor)
	{
		descriptors.push_back(std::move(descriptor));
	}

	void Manager::RemoveDescriptor(DeviceDescriptor& descriptor)
	{
		descriptors.erase(std::remove(descriptors.begin(), descriptors.end(), descriptor));
	}

	std::unique_ptr<Streaming::IFrameReceiver> Manager::CreateReceiverFor(const DeviceDescriptor& descriptor) const
	{
		switch (descriptor.transport())
		{
		case DeviceDescriptor::Transport::RawTcp:
			logger << "[Manager] Creating raw-TCP receiver for iOS device " << descriptor.name() << std::endl;
			return std::make_unique<Streaming::RawTCPReceiver>(onFrameReceivedCallback, onStatsReceivedCallback);
		case DeviceDescriptor::Transport::Rtsp:
		default:
			logger << "[Manager] Creating RTSP receiver for Android device " << descriptor.name() << std::endl;
			return std::make_unique<Receiver>(onFrameReceivedCallback, onStatsReceivedCallback);
		}
	}

	void Manager::Connect2Stream(int descriptorId, const StreamOptions& options)
	{
		this->streamingDevice = descriptorId;

		auto& descriptor = descriptors[descriptorId];
		auto& url = descriptor.url();

		logger << "[RTSP Manager] Connecting to stream " << url << "\n";

		if (receiver)
		{
			receiver->Stop();
			receiver.reset();
		}

		auto serializedOptions = Serializer::SerializeStreamOptions(options);
		serializedOptions[0] = Command::ACTIVATION;
		server.Send(streamingDevice, serializedOptions.data(), serializedOptions.size());

		receiver = CreateReceiverFor(descriptor);
		receiver->Start(url, descriptor.protocol(), options.resolution.first, options.resolution.second);
	}

	void Manager::SetResolution(unsigned short width, unsigned short height)
	{
		const unsigned char bytes[5] = {
			Command::RESOLUTION,
			static_cast<unsigned char>(width & 0xFF),
			static_cast<unsigned char>(width >> 8),
			static_cast<unsigned char>(height & 0xFF),
			static_cast<unsigned char>(height >> 8),
		};
		server.Send(streamingDevice, bytes, 5);
	}

	void Manager::SetFPS(int fps)
	{
		const unsigned char bytes[2] = { Command::FPS, (uint8_t)fps };
		server.Send(streamingDevice, bytes, 2);
	}

	void Manager::SetBitrate(int bitrate)
	{
		const unsigned char bytes[3] = {
			Command::BITRATE,
			static_cast<unsigned char>(bitrate & 0xFF),
			static_cast<unsigned char>(bitrate >> 8),
		};
		server.Send(streamingDevice, bytes, 3);
	}

	void Manager::SetAdaptiveBitrate(int min, int max)
	{
		const unsigned char bytes[5] = {
			Command::ADAPTIVE_BITRATE,
			static_cast<unsigned char>(min & 0xFF),
			static_cast<unsigned char>(min >> 8),
			static_cast<unsigned char>(max & 0xFF),
			static_cast<unsigned char>(max >> 8),
		};
		server.Send(streamingDevice, bytes, 5);
	}

	void Manager::SetStabilization(bool enabled)
	{
		const unsigned char bytes[2] = { Command::STABILIZATION, enabled ? (uint8_t)1 : (uint8_t)0 };
		server.Send(streamingDevice, bytes, 2);
	}

	void Manager::SetFlash(bool enabled)
	{
		const unsigned char bytes[2] = { Command::FLASH, enabled ? (uint8_t)1 : (uint8_t)0 };
		server.Send(streamingDevice, bytes, 2);
	}

	void Manager::SetFocusMode(int mode)
	{
		const unsigned char bytes[2] = { Command::FOCUS, (uint8_t)mode };
		server.Send(streamingDevice, bytes, 2);
	}

	void Manager::SetH265Codec(bool enabled)
	{
		const unsigned char bytes[2] = { Command::CODEC, enabled ? (uint8_t)1 : (uint8_t)0 };
		server.Send(streamingDevice, bytes, 2);
	}

	void Manager::SwapCamera()
	{
		const unsigned char bytes[1] = { Command::CAMERA };
		server.Send(streamingDevice, bytes, 1);
	}

	void Manager::Rotate(uint8_t degrees)
	{
		const unsigned char bytes[2] = { Command::ROTATION, degrees };
		server.Send(streamingDevice, bytes, 2);
	}

	void Manager::Zoom(float factor)
	{
		std::vector<uint8_t> bytes;
		bytes.reserve(5);
		bytes.push_back(Command::ZOOM);
		AppendFloat32LE(bytes, factor);
		server.Send(streamingDevice, bytes.data(), bytes.size());
	}

	void Manager::FlipHorizontally()
	{
		const unsigned char bytes[2] = { Command::FLIP, 1 };
		server.Send(streamingDevice, bytes, 2);
	}

	void Manager::FlipVertically()
	{
		const unsigned char bytes[2] = { Command::FLIP, 0 };
		server.Send(streamingDevice, bytes, 2);
	}

	void Manager::ApplyCorrectionFilter(std::string filterName, int value)
	{
		uint8_t nameLen = static_cast<uint8_t>(filterName.size());

		std::vector<uint8_t> packet;
		packet.reserve(3 + nameLen);

		packet.push_back(Command::CORRECTION_FILTER);
		packet.push_back(nameLen);
		packet.insert(packet.end(), filterName.begin(), filterName.end());
		packet.push_back(static_cast<uint8_t>(value));

		server.Send(streamingDevice, packet.data(), packet.size());
	}

	void Manager::ApplyEffectFilter(std::string filterName)
	{
		uint8_t nameLen = static_cast<uint8_t>(filterName.size());

		std::vector<uint8_t> packet;
		packet.reserve(3 + nameLen);

		packet.push_back(Command::EFFECT_FILTER);
		packet.push_back(nameLen);
		packet.insert(packet.end(), filterName.begin(), filterName.end());

		server.Send(streamingDevice, packet.data(), packet.size());
	}

	// MARK: - iOS premium controls

	void Manager::SetLensZoom(float factor)
	{
		std::vector<uint8_t> bytes;
		bytes.reserve(5);
		bytes.push_back(Command::LENS_ZOOM);
		AppendFloat32LE(bytes, factor);
		server.Send(streamingDevice, bytes.data(), bytes.size());
	}

	void Manager::SetExposure(float durationSeconds, float iso)
	{
		std::vector<uint8_t> bytes;
		bytes.reserve(9);
		bytes.push_back(Command::EXPOSURE);
		AppendFloat32LE(bytes, durationSeconds);
		AppendFloat32LE(bytes, iso);
		server.Send(streamingDevice, bytes.data(), bytes.size());
	}

	void Manager::SetWhiteBalance(float temperatureK, float tint)
	{
		std::vector<uint8_t> bytes;
		bytes.reserve(9);
		bytes.push_back(Command::WHITE_BALANCE);
		AppendFloat32LE(bytes, temperatureK);
		AppendFloat32LE(bytes, tint);
		server.Send(streamingDevice, bytes.data(), bytes.size());
	}

	void Manager::SetStudioMode(bool enabled)
	{
		const unsigned char bytes[2] = { Command::STUDIO_MODE, enabled ? (uint8_t)1 : (uint8_t)0 };
		server.Send(streamingDevice, bytes, 2);
	}

	void Manager::SetExposureCompensation(float bias)
	{
		std::vector<uint8_t> bytes;
		bytes.reserve(5);
		bytes.push_back(Command::EXPOSURE_COMPENSATION);
		AppendFloat32LE(bytes, bias);
		server.Send(streamingDevice, bytes.data(), bytes.size());
	}

	void Manager::SetStabilizationMode(int mode)
	{
		const unsigned char bytes[2] = { Command::STABILIZATION_MODE, static_cast<uint8_t>(mode) };
		server.Send(streamingDevice, bytes, 2);
	}

	void Manager::SetFocusLock(float lensPosition)
	{
		std::vector<uint8_t> bytes;
		bytes.reserve(5);
		bytes.push_back(Command::FOCUS_LOCK);
		if (lensPosition < 0.0f)
		{
			// Sentinel 0xFFFFFFFF means "release lock and return to auto".
			bytes.push_back(0xFF);
			bytes.push_back(0xFF);
			bytes.push_back(0xFF);
			bytes.push_back(0xFF);
		}
		else
		{
			AppendFloat32LE(bytes, lensPosition);
		}
		server.Send(streamingDevice, bytes.data(), bytes.size());
	}

	void Manager::TapToFocus(float x, float y)
	{
		std::vector<uint8_t> bytes;
		bytes.reserve(9);
		bytes.push_back(Command::TAP_TO_FOCUS);
		AppendFloat32LE(bytes, x);
		AppendFloat32LE(bytes, y);
		server.Send(streamingDevice, bytes.data(), bytes.size());
	}

	void Manager::SetMicrophoneEnabled(bool enabled)
	{
		const unsigned char bytes[2] = { Command::MIC_ENABLED, enabled ? (uint8_t)1 : (uint8_t)0 };
		server.Send(streamingDevice, bytes, 2);
	}

	void Manager::RequestSnapshot()
	{
		const unsigned char bytes[1] = { Command::SNAPSHOT_REQUEST };
		server.Send(streamingDevice, bytes, 1);
	}

	void Manager::ResetCameraToAuto()
	{
		const unsigned char bytes[1] = { Command::RESET_CAMERA_TO_AUTO };
		server.Send(streamingDevice, bytes, 1);
	}

	const std::vector<DeviceDescriptor>& Manager::GetDescriptors() const
	{
		return descriptors;
	}

	const int& Manager::GetStreamingDevice() const
	{
		return streamingDevice;
	}
};
