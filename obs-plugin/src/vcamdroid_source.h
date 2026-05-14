#pragma once

// Forward declarations for the OBS API. The real headers are pulled in by
// the plugin's own build system (libobs); this header is intentionally OBS
// API agnostic so the rest of the repo can build without OBS installed.
struct obs_source_info;
struct obs_data;
struct obs_source;
struct obs_properties;

namespace VCamdroidOBS {

	/*
		Plugin entry point. Returns the obs_source_info descriptor that the
		OBS module loader registers for the "VCamdroid Phone" source type.

		Lifecycle:
		  * create   - allocates a VCamdroidSource instance (one per OBS source)
		  * update   - re-applies user-selected device/resolution/fps
		  * tick     - drives RTSP::Manager + frame_pipe pumps
		  * destroy  - tears everything down cleanly

		Camera controls (zoom, exposure, WB, focus, stabilization, studio mode)
		are surfaced as `obs_properties_t` items so they appear directly in
		the OBS source properties dialog.
	*/
	const obs_source_info* describe_source();

	/*
		Module load hook. Wires `describe_source()` into the OBS module
		registration call (`obs_register_source`).
	*/
	bool register_module();

}
