#pragma once

#include "constants.h"

/*
	State store for a connected device
*/
struct StreamOptions
{
	// State registry mapping device name to its cached state store
	using Registry = std::map<std::string, StreamOptions>;

	// Maps filter names to values
	using FilterValueCache = std::map<std::string, int>;

	int fps = 30;
	std::pair<int, int> resolution = { 640, 480 };
	bool backCameraActive = true;

	// Cached values of adjustment filters
	FilterValueCache filterSliderValues;
	// Only 1 effect filter is permitted
	std::string activeEffectFilter;

	bool adaptiveBitrate = false;
	int bitrate = RTSP::DEFAULT_STATIC_BITRATE; 
	int minBitrate = RTSP::DEFAULT_MIN_BITRATE;
	int maxBitrate = RTSP::DEFAULT_MAX_BITRATE;

	float zoom = 1.0f;
	bool stabilizationEnabled = false;
	bool flashEnabled = false;
	bool h265Enabled = false;
	int focusMode = 0;

	// --- iOS premium controls (v2). Not wire-serialized in ACTIVATION; applied
	//     via follow-up iOS-only commands after activation. ---

	/// Continuous zoom across the full triple-camera range (0.5x ultra-wide
	/// through 5x telephoto on iPhone 16 Pro). 1.0 == native wide.
	float iosLensZoom = 1.0f;

	enum class ExposureMode { Auto = 0, Manual = 1 };
	ExposureMode iosExposureMode = ExposureMode::Auto;
	/// Shutter time in seconds, e.g. 1/60 -> 0.01667. Only honored when
	/// iosExposureMode == Manual.
	float iosExposureDurationSeconds = 1.0f / 60.0f;
	float iosExposureISO = 100.0f;
	/// EV bias in stops. 0 == no bias.
	float iosExposureCompensation = 0.0f;

	enum class WhiteBalanceMode { Auto = 0, Manual = 1 };
	WhiteBalanceMode iosWhiteBalanceMode = WhiteBalanceMode::Auto;
	float iosWhiteBalanceTemperatureK = 5500.0f;
	float iosWhiteBalanceTint = 0.0f;

	/// 0=off, 1=standard, 2=cinematic, 3=cinematicExtended.
	int iosStabilizationMode = 1;

	/// 0..1 lens position when locked. Negative means "release to auto".
	float iosFocusLockPosition = -1.0f;
};