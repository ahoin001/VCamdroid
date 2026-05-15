<h1 align="center">
  <sub>
    <img src="imgs/icon2.png" width="150">
  </sub>
  <br>
  VCamdroid
</h1>

<p align="center">Turn your Android phone or iPhone into a high-performance Windows webcam.</p>

<p align="center">
  <a href="https://github.com/darusc/VCamdroid/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/darusc/VCamdroid?style=for-the-badge" alt="License">
  </a>
  <a href="https://github.com/darusc/VCamdroid/releases">
    <img src="https://img.shields.io/github/v/release/darusc/VCamdroid?style=for-the-badge" alt="Release">
  </a>
  <a href="https://github.com/darusc/VCamdroid/releases">
    <img src="https://img.shields.io/github/downloads/darusc/VCamdroid/total?style=for-the-badge" alt="Downloads">
  </a>
</p>

## Table of Contents

1. [**Description**](#description)
2. [**Key Features**](#key-features)
3. [**Installation Guide**](#installation-guide)
4. [**Usage Instructions**](#usage-instructions)
5. [**Using VCamdroid in OBS**](#using-vcamdroid-in-obs)
6. [**iPhone Premium Camera Controls**](#iphone-premium-camera-controls)
7. [**Troubleshooting**](#troubleshooting)
8. [**Reporting Issues**](#reporting-issues)
9. [**Technical Architecture**](#technical-architecture)
10. [**Contributing**](#contributing)
11. [**Releases and CI**](#releases-and-ci)

## Description

VCamdroid allows you to seamlessly use your **Android phone or iPhone** as a virtual webcam on your Windows PC. Built using a custom DirectShow filter provided by [Softcam library](https://github.com/tshino/softcam), it ensures compatibility with popular applications like Zoom, OBS, Discord, and Teams. Whether wired (via USB) or wireless (via Wi-Fi), VCamdroid delivers a low-latency, hardware-accelerated video feed directly to your desktop.

iPhone users get access to **premium camera controls** — continuous optical zoom across all built-in lenses, manual exposure, white balance, focus lock, stabilization modes, and a battery-saving Studio Mode — all driven remotely from the Windows UI.

<p align="center">
  <img src="imgs/demo.gif" width="600" alt="VCamdroid Demo">
</p>

## Key Features

* **Universal Compatibility:** Works with any Windows application that supports standard webcams (Zoom, OBS, Discord, Teams, etc.).
* **Android + iPhone Support:** Works with Android 7.0+ and iPhone XS or newer (iOS 16+).
* **Flexible Connectivity:** Supports high-speed wired connections (USB via ADB for Android) and convenient wireless connections (Wi-Fi for both platforms).
* **Multi-Device Support:** Connect multiple phones simultaneously and switch between them instantly.
* **Full Camera Control:** Remotely toggle between front and back cameras, adjust resolutions, and enable flash.
* **Image Adjustments:** Real-time controls for rotation, mirroring (flip), brightness, contrast, and saturation.
* **Zero-Config Pairing:** Automatically connects Android over USB via ADB; straightforward QR code pairing for Wi-Fi. iPhones are auto-discovered on the local network via Bonjour.
* **iPhone Premium Controls:** Continuous optical zoom (ultra-wide to telephoto), manual exposure (duration/ISO/compensation), white balance (temperature/tint), focus lock, stabilization modes, and Studio Mode.


## Installation Guide

### Prerequisites

* **PC:** Windows 10 or 11.
* **Android Phone:** Android 7.0 (Nougat) or higher.
* **iPhone:** iPhone XS or newer running iOS 16.0+. Triple-camera models (iPhone 11 Pro, 12 Pro, 13 Pro, 14 Pro, 15 Pro, 16 Pro and their Max variants) are recommended for the best zoom range.

### Step 1: Install on Windows

1.  Download the latest binaries from the [**Releases Page**](https://github.com/darusc/VCamdroid/releases).
2.  Extract the ZIP archive.
3.  Right-click `install.bat` and select **Run as Administrator**.
    * *Note: This script registers `softcam.dll` with the system, making the virtual webcam device visible to other applications.*
4.  Check both **Private** and **Public** profiles in the Windows Firewall popup and allow the app.

### Step 2: Install on Android

You can transfer the APK file to your phone and install it manually, or follow the steps below for an automatic install:
1.  Connect your phone to your PC via USB.
2.  Ensure **USB Debugging** is enabled (see instructions below).
3.  Run `install_apk.bat` on your PC to automatically install the app on your phone.


### Step 3: Install on iPhone

The iOS app must be built from source using Xcode:

1.  **Prerequisites:**
    * A Mac with **Xcode 15** or newer installed.
    * [**XcodeGen**](https://github.com/yonaskolb/XcodeGen) installed (`brew install xcodegen`).
    * An Apple Developer account (free or paid) for code signing.

2.  **Generate the Xcode project:**
    ```bash
    cd ios/VCamdroidiOS
    xcodegen generate
    ```

3.  **Open the project:**
    ```bash
    open VCamdroidiOS.xcodeproj
    ```

4.  **Configure signing:**
    * In Xcode, select the **VCamdroidiOS** target.
    * Go to **Signing & Capabilities**.
    * Select your Apple Developer **Team**.

5.  **Build and run:**
    * Connect your iPhone via USB.
    * Select your iPhone as the run destination in Xcode's toolbar.
    * Press **Cmd + R** to build and install.
    * *Note: The iOS Simulator does not support real camera capture. You must use a physical iPhone.*

6.  **Grant permissions on first launch:**
    * Tap **Allow** when prompted for **Camera** access.
    * Tap **Allow** when prompted for **Local Network** access (required for Wi-Fi discovery and streaming).
    * If you plan to use microphone streaming, also allow **Microphone** access when prompted.


### How to Enable USB Debugging (Android only)

1.  Go to **Settings > About Phone**.
2.  Find **Build Number** and tap it **7 times** until you see "You are now a developer!"
3.  Go back to **Settings > System > Developer Options**.
4.  Toggle **USB Debugging** to **ON**.
    * *For device-specific steps, refer to the [official Android documentation](https://developer.android.com/studio/debug/dev-options).*


## Usage Instructions

### Android: Wired Connection (USB / ADB)

*Recommended for lowest latency and highest stability.*

1.  Connect your Android phone to the PC via USB.
2.  Launch the **VCamdroid Desktop Client**.
3.  Launch the **VCamdroid App** on your phone.
4.  The connection is automatic. The app should change to streaming mode.

### Android: Wireless Connection (Wi-Fi)

1.  Ensure both your PC and Android phone are on the **same Wi-Fi network**.
2.  Launch the **VCamdroid Desktop Client** and select the **Connect** tab to reveal a QR Code.
3.  Launch the **VCamdroid App** on your phone.
4.  Point your camera at the PC screen to scan the QR code. Click **Connect** in the popup dialog.

### iPhone: Wi-Fi Connection

*The primary connection method for iPhone. Both devices must be on the same Wi-Fi network.*

1.  Launch the **VCamdroid Desktop Client** on your Windows PC.
2.  Launch the **VCamdroid App** on your iPhone.
3.  On your iPhone, you will see the connection screen with two fields:
    * **Windows host** — Enter the local IP address of your Windows PC.
      To find your PC's IP: open a Command Prompt and run `ipconfig`. Look for the **IPv4 Address** under your Wi-Fi or Ethernet adapter (e.g., `192.168.1.10`).
    * **Control port** — Leave this as `6969` (the default).
4.  Tap **Connect**.
5.  The iPhone will connect to the Windows client, start the camera, and begin streaming. You should see:
    * A live camera preview on your iPhone with streaming status indicators (FPS, bitrate, resolution).
    * The video feed appear in the VCamdroid Desktop Client's preview window.
6.  Your iPhone camera is now available as a webcam in any Windows application (Zoom, OBS, Discord, Teams, etc.).

**Auto-Discovery (Bonjour):** If your network supports mDNS/Bonjour, the VCamdroid Desktop Client will automatically detect your iPhone on the local network — no need to type the IP manually. Look for your iPhone's name in the device dropdown.

### iPhone: Disconnecting

* **From iPhone:** Tap the **X** button at the bottom of the streaming screen.
* **From Windows:** Close the VCamdroid Desktop Client or switch to a different device in the dropdown.

### iPhone: Studio Mode

When you mount your iPhone on a tripod or stand for a long streaming session, enable **Studio Mode** from the Windows UI:

* The iPhone screen goes to near-black with a single green pulse indicator, saving battery and preventing light bleed.
* The idle timer is disabled so the screen never locks during streaming.
* All UI overlays are hidden to minimize distractions.
* To exit Studio Mode, disable it from the Windows controls or disconnect.

If you encounter any problems, check the [**Troubleshooting**](#troubleshooting) section. If the issue persists, please [report the issue](#reporting-issues).


## Using VCamdroid in OBS

VCamdroid works as a standard webcam in OBS Studio with no extra plugins required:

1.  Make sure VCamdroid is streaming (follow the connection steps above for your device).
2.  In OBS, click **+** under **Sources** and select **Video Capture Device**.
3.  Name it (e.g., "VCamdroid") and click **OK**.
4.  In the **Device** dropdown, select **Softcam** (this is the VCamdroid virtual camera).
5.  Click **OK**. Your phone's camera feed now appears as a source in OBS.

**Tips:**
* Set the resolution in OBS to match the resolution configured in the VCamdroid Desktop Client for the best quality.
* For the lowest latency, use a USB connection (Android) or ensure your Wi-Fi network is uncongested.
* VCamdroid also works in Zoom, Discord, Teams, Google Meet, and any other app that accepts standard webcam input — just select **Softcam** as the camera.
* Use **File → OBS / Zoom setup…** in the desktop app for a quick checklist.

**If the feed stops or the app feels stuck:** fully quit VCamdroid on Windows and on your iPhone, then reopen the PC app first, then the phone app. The desktop client clears USB tunnels and port `6969` on startup.

## iPhone Premium Camera Controls

When an iPhone is connected, the desktop app shows a **Camera controls** dock (and the stream settings dialog) with Portrait Mode (bokeh), exposure, and white balance. The iOS streaming screen exposes the same primary controls. All are applied in real time on your iPhone:

### Portrait Mode (bokeh)
* Blurs the background while keeping you sharp (Camo-style), with an adjustable strength slider on phone and PC.

### Lens Zoom
* Smoothly zoom across the **entire optical range** of your iPhone's camera system.
* On triple-camera models (e.g., iPhone 16 Pro), this transitions seamlessly from ultra-wide (0.5x) through wide (1x) to telephoto (up to 5x optical on iPhone 16 Pro).
* The zoom slider controls the hardware `videoZoomFactor`, so quality stays sharp at every level.

### Manual Exposure
* **Mode:** Switch between **Auto** (camera manages everything) and **Manual** (you set duration and ISO).
* **Duration:** Control the shutter speed (exposure duration in seconds). Longer durations let in more light but increase motion blur.
* **ISO:** Control sensor sensitivity. Higher ISO brightens the image but adds noise.
* **Compensation:** Adjust the EV bias (+/- stops) to make the overall image brighter or darker while keeping auto-exposure active.

### White Balance
* **Mode:** Switch between **Auto** and **Manual**.
* **Temperature (K):** Shift the color from warm (lower values, more orange) to cool (higher values, more blue).
* **Tint:** Fine-tune the green/magenta axis.

### Focus
* **Auto Focus:** The camera continuously focuses on the scene (default).
* **Tap to Focus:** Click a point in the preview to focus and meter at that location.
* **Manual Focus Lock:** Lock the lens at a specific focus distance (0.0 = near, 1.0 = infinity).

### Stabilization
* Choose from **Off**, **Standard**, **Cinematic**, or **Cinematic Extended** stabilization modes.
* Cinematic modes smooth out hand-held movement, ideal for walk-and-talk or handheld streaming.

### Studio Mode
* Blanks the iPhone screen to near-black for battery savings during long tripod-mounted sessions.
* A small green pulse indicator confirms the stream is still active.

### Microphone
* Toggle iPhone microphone capture on/off from the Windows UI.

### Snapshot
* Capture a full-resolution JPEG snapshot of the current camera frame directly from the Windows UI.


---

## Technical Architecture

### Networking Protocol

VCamdroid uses **two different video transports** depending on the device platform, with a **shared control protocol** for both:

| | Android | iPhone |
|---|---|---|
| **Video Transport** | RTSP (RTP over TCP/UDP) | Raw TCP (length-prefixed H.264/H.265 NAL units) |
| **Control Channel** | TCP port 6969 (binary protocol) | TCP port 6969 (same binary protocol) |
| **Wired Connection** | ADB port forwarding | USB tunneling via libusbmuxd (planned) |
| **Wireless Discovery** | QR code | Bonjour / mDNS auto-discovery |

For full protocol details, see [`docs/PROTOCOL.md`](docs/PROTOCOL.md).

#### Android Transport

1.  **Wi-Fi:** The Windows client connects directly to the RTSP server running on the Android device over the local network.
2.  **USB:** The application uses **ADB Port Forwarding** to tunnel the RTSP stream over **TCP** (interleaved RTSP). This creates a stable, high-bandwidth tunnel via `localhost` that bypasses network interference.
3.  **Libraries:** Server-side uses [RootEncoder](https://github.com/pedroSG94/RootEncoder) for RTSP/RTP. Client-side uses [FFmpeg](https://ffmpeg.org/) for decoding.

#### iPhone Transport

1.  **Wi-Fi:** The iPhone runs a TCP server on port 8554. The Windows client connects, receives a stream header (magic + codec + resolution + fps), then continuously reads length-prefixed H.264 or H.265 NAL units.
2.  **Encoding:** Frames are captured via `AVCaptureSession` and encoded with Apple's hardware **VideoToolbox** (`VTCompressionSession`) for low-latency H.264/H.265. Pixel buffers stay on IOSurface-backed GPU memory (zero CPU copy).
3.  **Adaptive Bitrate:** The iOS app monitors streaming metrics and automatically adjusts encoder bitrate to match network conditions, preventing frame drops on congested Wi-Fi.

<p align="center"><img src="imgs/network.png" width="60%"></p>

### Video Pipeline

The pipeline is engineered for performance, offloading image processing to the phone's GPU before compression to minimize latency and bandwidth.

1.  **Capture, Process & Encode (Android):**
    * **Capture:** Video frames are captured using the modern **Camera2 API**.
    * **Pre-Processing:** Raw frames are processed on the GPU using OpenGL. Operations like **Rotation**, **Mirroring (Flip)**, and **Color Correction** are applied here *before* encoding, ensuring the stream is "ready-to-display."
    * **Hardware Encoding:** The processed frames are passed to the device's hardware **MediaCodec** (supporting **H.264** or **H.265/HEVC**). This offloads compression from the CPU.
    * **Transmission:** **RootEncoder** encapsulates the encoded stream into RTP packets and transmits them over the active network connection.

2.  **Capture, Encode & Stream (iPhone):**
    * **Capture:** Frames are captured using `AVCaptureSession` with `AVCaptureVideoDataOutput`, targeting the `builtInTripleCamera` (or best available) for full zoom range.
    * **Hardware Encoding:** `CVPixelBuffer` frames are passed to **VideoToolbox** (`VTCompressionSession`) configured for real-time, low-latency encoding. No B-frames, CABAC entropy, and burst-rate limiting keep the stream smooth.
    * **NAL Extraction & Streaming:** Encoded NAL units are extracted from the `CMSampleBuffer` and streamed over TCP with length-prefix framing. SPS/PPS/VPS parameter sets are sent in-band on every keyframe for mid-stream tune-in.

3.  **Decode & Render (Windows):**
    * **Decoding:** The Windows client uses **FFmpeg** to decode H.264/H.265 frames from either the RTSP stream (Android) or raw TCP stream (iPhone) into raw image data.
    * **Output:**
        * **UI Preview:** The decoded frame is rendered immediately to the application window.
        * **Virtual Device:** The frame is written to a ring buffer managed by the [Softcam](https://github.com/tshino/softcam) library, making it available to all Windows apps as a standard webcam.

<p align="center"><img src="imgs/pipeline.png" width="50%"></p>


## Releases and CI

Automated **GitHub Releases** (Android APK, unsigned iOS IPA, Windows zip), **pull request CI**, and hosted-runner assumptions are documented in [**docs/CI-AND-RELEASE.md**](docs/CI-AND-RELEASE.md). From the repo root: `make ship-patch` (or `ship-minor` / `ship-major`) bumps the version, commits, tags, and pushes.


## Contributing

We actively welcome contributions! Whether you're fixing a bug, optimizing performance, or adding a cool new feature, please feel free to fork the repository and submit a Pull Request.

### Repository Structure

* `android/`: The Android Studio project (Kotlin). Handles Camera2 API capture, OpenGL processing, and RTSP streaming.
* `ios/`: The iOS app (Swift/SwiftUI). Handles AVFoundation capture, VideoToolbox encoding, and TCP streaming with premium camera controls.
* `windows/`: The Visual Studio solution (C++). Contains the Desktop Client GUI, RTSP/TCP receivers, and the DirectShow filter logic.
* `obs-plugin/`: Scaffold for a dedicated OBS Studio source plugin (future enhancement).
* `docs/`: Protocol specification, performance notes, and [**CI / release**](docs/CI-AND-RELEASE.md) for maintainers.

---

### Development Setup

#### Android App

1.  **Prerequisites:** Install the latest **Android Studio**.
2.  **Import:** Open the `android/` directory as a project.
3.  **Build:** Let Gradle sync and download dependencies.
    * *Core Dependency:* [RootEncoder](https://github.com/pedroSG94/RootEncoder) (handles RTSP/RTP packets).
4.  **Run:** Connect a physical Android device (emulators often lack necessary encoder hardware) and run the `app` module.

#### iOS App

1.  **Prerequisites:**
    * **Xcode 15** or newer.
    * [**XcodeGen**](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
2.  **Generate the Xcode project:**
    ```bash
    cd ios/VCamdroidiOS
    xcodegen generate
    ```
3.  **Open and configure:** Open `VCamdroidiOS.xcodeproj`, select your signing team under **Signing & Capabilities**.
4.  **Build and run:** Connect a physical iPhone and press **Cmd + R**. The iOS Simulator does not support real camera capture.
5.  **Run tests:**
    ```bash
    xcodebuild -project VCamdroidiOS.xcodeproj -scheme VCamdroidiOSTests test
    ```

#### Windows Client

1.  **Prerequisites:**
    * **Visual Studio 2026** (with "Desktop development with C++" workload).
    * **vcpkg** for `asio 1.32.0`, `wxWidgets 3.3.1` and `ffmpeg 7.1.2`.

2.  **Install Dependencies:**
    Use `vcpkg` to install the required libraries for **x64**:
    ```powershell
    vcpkg install wxwidgets:x64-windows ffmpeg:x64-windows
    vcpkg integrate install
    ```

3.  **Build Instructions:**
    * Build `softcam`. [See](https://github.com/tshino/softcam?tab=readme-ov-file#how-to-build-the-library) for instructions.
    * Open `windows/VCamdroid.sln`.
    * Set the configuration to **Release / x64** (x86 is not supported).
    * Build the solution.

4.  **Testing the Driver:**
    * The DirectShow filter (`softcam.dll`) must be registered to be visible to apps like OBS or Zoom.
    * Run `install.bat` as Administrator in your output directory, or manually register it via:
        ```cmd
        regsvr32 softcam.dll
        ```

### Submitting a Pull Request

1.  Fork the project.
2.  Create your feature branch (`git checkout -b feature/AmazingFeature`).
3.  Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4.  Push to the branch (`git push origin feature/AmazingFeature`).
5.  Open a Pull Request.


## Troubleshooting

### App Crashes / "VCRUNTIME140.dll was not found"

If the application closes immediately or you see a system popup error regarding missing DLLs (like `VCRUNTIME140.dll` or `MSVCP140.dll`), your PC is missing the C++ runtime libraries.
* **Fix:** Download and install the [latest VC++ Redistributable (x64)](https://aka.ms/vs/17/release/vc_redist.x64.exe) from Microsoft.

### Android: Connection Failed / Host Unreachable

If the Android app cannot connect to the Windows client:
1.  **Check Windows Firewall:** The firewall often blocks incoming video streams.
    * Search for **"Allow an app through Windows Firewall"** in the Start Menu.
    * Find `VCamdroid.exe` in the list and ensure both **Private** and **Public** boxes are checked.
2.  **Verify Network Visibility (Reverse Ping Test):**
    Sometimes the phone cannot see the PC. To verify:
    * Connect via USB (for the test command).
    * Open a terminal in the VCamdroid folder and run: `adb shell ping -c 4 <PC_IP_ADDRESS>`
    * If you see "100% packet loss" or "unreachable," your PC's firewall or router settings (AP Isolation) are blocking the connection.

### Android: USB Connection Not Working

If the app does not detect your phone:
1.  **Check ADB Devices:**
    * Open a terminal in the VCamdroid folder.
    * Run: `adb devices`
    * **If list is empty:** Your cable is bad or [Universal ADB Drivers](https://adb.clockworkmod.com/) are missing.
    * **If "unauthorized":** Check your phone screen and tap "Allow" on the **"Allow USB Debugging?"** popup.
2.  **Kill Conflicting ADB Processes:**
    * Open **Task Manager** (`Ctrl + Shift + Esc`).
    * Search for `adb.exe` in the **Details** tab.
    * Right-click and select **End Task**, then restart VCamdroid.

### iPhone: Can't Connect

If the iPhone app fails to connect to the Windows client:
1.  **Verify same Wi-Fi network:** Both your iPhone and PC must be on the exact same local network. Hotspots, guest networks, or VPNs will prevent the connection.
2.  **Double-check the IP address:** On your Windows PC, open Command Prompt and run `ipconfig`. Use the **IPv4 Address** from your Wi-Fi or Ethernet adapter, not any VPN or virtual adapter address.
3.  **Check Windows Firewall:** Just like Android, ensure VCamdroid.exe is allowed through the firewall for both Private and Public profiles.
4.  **Grant Local Network permission:** On first launch, iOS asks for **Local Network** access. If you denied it:
    * Go to iPhone **Settings > Privacy & Security > Local Network**.
    * Find **VCamdroid** and toggle it **ON**.

### iPhone: Camera Permission Denied

If you see a "Camera permission denied" error on the iPhone:
* Go to iPhone **Settings > VCamdroid** (or **Settings > Privacy & Security > Camera**).
* Ensure VCamdroid is toggled **ON**.
* Relaunch the VCamdroid app.

### iPhone: No Video After Connecting

If the connection succeeds but no video appears in the Windows preview:
1.  **Ensure the device is activated:** In the VCamdroid Desktop Client, check the device dropdown. Your iPhone's name should appear. Select it if it's not already active.
2.  **Check the streaming status:** On the iPhone, the status indicator should show **"Streaming"** with a green pill. If it shows **"Waiting for PC"**, the video port may be blocked by a firewall.
3.  **Restart the connection:** Disconnect from both sides and reconnect.

### iPhone: High Latency or Choppy Video

* Move closer to your Wi-Fi router, or switch to a 5 GHz band if available.
* Lower the resolution or FPS in the Windows stream configuration dialog.
* The app has adaptive bitrate enabled by default — it will automatically reduce quality to maintain a smooth stream on congested networks.
* Close other bandwidth-heavy apps on both the iPhone and PC.

---

## Reporting Issues

VCamdroid supports a wide range of Android and iOS devices. Your feedback is crucial!

If you encounter a bug or crash, please open a [New Issue](https://github.com/darusc/VCamdroid/issues) and **attach the logs** to help us fix it faster.

### How to get the logs:
1.  **Android Logs:**
    * Open the VCamdroid app on your phone.
    * Tap the **Bug Icon** in the top corner.
    * Click the **Save/Share** button to export the log file.
2.  **Windows Logs:**
    * Check the `vcamdroid.log` file inside the VCamdroid installation directory.
    * Copy the text from the latest log file.

**Please include:**
* Phone Model (e.g., Samsung S21, Pixel 6, iPhone 16 Pro)
* OS Version (e.g., Android 14, iOS 17.5)
* Connection Method (USB or Wi-Fi)
