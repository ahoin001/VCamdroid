#include "vcamdroid_source.h"

/*
	Placeholder implementation. The build system that pulls in libobs will
	supply the real obs_source_info layout; here we only declare the entry
	points so the rest of the repository can lint/compile this file when
	libobs is unavailable.

	Once libobs is installed locally (`vcpkg install obs-studio`), this
	file becomes:

	    static const char* GetName(void*) { return "VCamdroid Phone"; }
	    static void* Create(obs_data_t* settings, obs_source_t* source) { ... }
	    static void Destroy(void* data) { ... }
	    static obs_properties_t* GetProperties(void* data) { ... }
	    static void Update(void* data, obs_data_t* settings) { ... }
	    static void VideoRender(void* data, gs_effect_t* effect) { ... }

	The actual wiring of those callbacks to RTSP::Manager / IFrameReceiver
	lives in the desktop client and is reused here directly to avoid
	duplicating protocol code.
*/

namespace VCamdroidOBS {

	const obs_source_info* describe_source()
	{
		// Real implementation is provided once libobs is available in the
		// plugin build environment. See README.md for the integration plan.
		return nullptr;
	}

	bool register_module()
	{
		return false;
	}

}
