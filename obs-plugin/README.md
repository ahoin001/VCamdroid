# obs-vcamdroid

A dedicated OBS Studio source plugin for VCamdroid. While Phase 1 of the
project already makes VCamdroid available to OBS via the system-wide
DirectShow virtual camera (`Softcam`), this plugin offers a tighter
integration for power users:

- **Lower latency**: frames are pushed directly into OBS via
  `obs_source_output_video` instead of going through the DirectShow ring
  buffer.
- **In-OBS device picker**: lists every connected VCamdroid phone (Android
  or iOS) without needing the main VCamdroid window.
- **In-OBS camera controls**: lens zoom, exposure, white balance, focus,
  stabilization, studio mode for iOS — all exposed in the source properties
  panel.
- **Auto-reconnect** with a clear status indicator inside OBS.

## Status

Phase 4 deliverable. The scaffold below shows the integration points; the
build system + actual OBS API wiring will be filled in alongside the first
public release.

## Build outline

```
obs-plugin/
  CMakeLists.txt              # to be added (links libobs, libavformat)
  src/
    vcamdroid_source.h        # OBS source descriptor (placeholder below)
    vcamdroid_source.cpp      # source lifecycle: create/update/render/destroy
    discovery_bridge.h        # consumes Discovery::MdnsBrowser
    control_bridge.h          # mirrors RTSP::Manager API for in-OBS controls
    frame_pipe.h              # bridge from Streaming::IFrameReceiver to OBS frames
```

## Integration with existing code

The plugin reuses the same primitives the desktop client uses, keeping a
single source of truth for protocol + device behavior:

| Plugin module      | Existing component                              |
|--------------------|-------------------------------------------------|
| `discovery_bridge` | `windows/src/discovery/mdnsdiscovery.h`         |
| `control_bridge`   | `windows/src/rtsp/manager.h` (`RTSP::Manager`)  |
| `frame_pipe`       | `windows/src/streaming/framereceiver.h`         |
| protocol           | `docs/PROTOCOL.md`                              |

When/if the plugin is enabled, it instantiates its own `RTSP::Manager` (one
per OBS source instance) rather than sharing with the main VCamdroid
application. This keeps OBS sessions independent and allows multiple OBS
sources to point at different phones simultaneously.

## Why a separate plugin instead of fully replacing Softcam?

- Softcam-based delivery is the only way to make VCamdroid usable in apps
  that don't load OBS plugins (Zoom, Discord, browser-based apps).
- The OBS plugin is an *additional* path, not a replacement. Users choose
  whichever fits their workflow.

## Next steps

1. Bring up CMakeLists with `find_package(libobs CONFIG REQUIRED)` and
   reuse `windows/src/rtsp`/`windows/src/streaming` as a static library.
2. Implement `vcamdroid_source.cpp` with the OBS callbacks:
   `obs_source_info { create, destroy, get_name, video_render,
   get_properties, update, get_defaults }`.
3. Surface camera controls via `obs_properties_add_*` and route them
   through `RTSP::Manager`.
4. Build a status panel (connection, FPS, bitrate, resolution) using OBS's
   `obs_source_get_proc_handler`.
