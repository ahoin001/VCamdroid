#pragma once

#include <string>
#include <vector>

#include "video/filter.h"

/*
	Describes information about a streaming device.

	The byte format of the device descriptor is as follows:
	each string is preceded by a 2 byte value representing its length,
	and the resolutions are preceded by a 2 byte value representing their count

	[uint16_t size][uint8_t[] name]
	[uint16_t size][uint8_t[] url]
	[uint16_t count]
	[uint16_t width][uint_16_t height] [0]
	...
	[uint16_t width][uint_16_t height] [count-1]

	The "url" field also implicitly carries the device type:
	- rtsp://...  => Android (RTSP transport)
	- vcmd://...  => iOS (raw TCP transport)
*/
struct DeviceDescriptor
{
	enum class DeviceType
	{
		Android,
		iOS,
	};

	enum class Transport
	{
		Rtsp,
		RawTcp,
	};

	/*
		first = width
		second = height
	*/
	using Resolution = std::pair<int, int>;

	DeviceDescriptor(std::string name,
	                 std::string url,
	                 std::string protocol,
	                 DeviceType deviceType,
	                 Transport transport,
	                 std::vector<Resolution> frontResolutions,
	                 std::vector<Resolution> backResolutions,
	                 Video::Filter::Registry filters)
		: deviceName(std::move(name)),
		  rtspUrl(std::move(url)),
		  rtspProtocol(std::move(protocol)),
		  deviceTypeValue(deviceType),
		  transportValue(transport),
		  availableFrontResolutions(std::move(frontResolutions)),
		  availableBackResolutions(std::move(backResolutions)),
		  availableFilters(std::move(filters)) {}

	DeviceDescriptor(const DeviceDescriptor&) = default;
	DeviceDescriptor& operator=(const DeviceDescriptor&) = default;
	DeviceDescriptor(DeviceDescriptor&&) = default;
	DeviceDescriptor& operator=(DeviceDescriptor&&) = default;

	const std::string& name() const { return deviceName; }
	const std::string& url() const { return rtspUrl; }
	const std::string& protocol() const { return rtspProtocol; }

	DeviceType deviceType() const { return deviceTypeValue; }
	Transport transport() const { return transportValue; }

	bool isiOS() const { return deviceTypeValue == DeviceType::iOS; }
	bool isAndroid() const { return deviceTypeValue == DeviceType::Android; }

	const std::vector<Resolution>& frontResolutions() const { return availableFrontResolutions; }
	const std::vector<Resolution>& backResolutions() const { return availableBackResolutions; }
	const Video::Filter::Registry& filters() const { return availableFilters; }

	bool operator==(const DeviceDescriptor& other) const
	{
		return this->rtspUrl == other.rtspUrl && this->deviceName == other.deviceName;
	}

private:
	std::string deviceName;
	std::string rtspUrl;
	std::string rtspProtocol;
	DeviceType deviceTypeValue = DeviceType::Android;
	Transport transportValue = Transport::Rtsp;
	std::vector<Resolution> availableFrontResolutions;
	std::vector<Resolution> availableBackResolutions;
	Video::Filter::Registry availableFilters;
};
