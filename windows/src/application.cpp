#include "application.h"

#include "gui/imgadjdlg.h"
#include "gui/streamconfigdlg.h"
#include "gui/ioscontrolspanel.h"
#include "gui/cameradockpanel.h"
#include "gui/devicesview.h"
#include "gui/qrconview.h"
#include "adb.h"

#include <wx/timer.h>
#include "settings.h"
#include "video/guipreviewscaler.h"
#include <iomanip>

Application::Application()
{
	SetAppearance(Appearance::System);
	wxInitAllImageHandlers();

	SetAppName("VCamdroid");
	
	Settings::Load();
	stateRegistry = Settings::GetDeviceStates();
}

void Application::RecoverStaleState()
{
	adb::kill(6969);
	adb::kill(8554);
	usbmuxBridge.KillAll();
}

void Application::SetupUsbTunnels()
{
	if (!usbmuxBridge.HasConnectedDevice())
		return;

	logger << "[app] iOS device detected via USB, setting up tunnels.\n";
	usbmuxBridge.Reverse(6969);
	usbmuxBridge.Forward(8554);
	usbDeviceConnected = true;
	UpdateUsbStatusLabel();
}

void Application::PollUsbDevices()
{
	const bool connected = usbmuxBridge.HasConnectedDevice();
	if (connected && !usbDeviceConnected)
		SetupUsbTunnels();
	else if (!connected && usbDeviceConnected)
	{
		usbmuxBridge.Kill(6969);
		usbmuxBridge.Kill(8554);
		usbDeviceConnected = false;
		UpdateUsbStatusLabel();
	}
}

void Application::UpdateUsbStatusLabel() const
{
	if (!mainWindow || !mainWindow->GetUsbStatusText())
		return;

	if (usbDeviceConnected)
		mainWindow->GetUsbStatusText()->SetLabel("iPhone connected (USB)");
	else if (usbmuxBridge.HasConnectedDevice())
		mainWindow->GetUsbStatusText()->SetLabel("iPhone detected (USB) — setting up tunnel…");
	else
		mainWindow->GetUsbStatusText()->SetLabel("USB: waiting for iPhone (install Apple Devices / iTunes if needed)");
}

bool Application::OnInit()
{
	if (!wxApp::OnInit())
		return false;

	RecoverStaleState();

	switch (Settings::Get("DIRECTSHOW_RESOLUTION") + Window::MenuIDs::DS_SD)
	{
		case Window::MenuIDs::DS_SD: dsSource = std::make_unique<DirectShowSource>(640, 480); break;
		case Window::MenuIDs::DS_HD: dsSource = std::make_unique<DirectShowSource>(1280, 720); break;
		case Window::MenuIDs::DS_FHD: dsSource = std::make_unique<DirectShowSource>(1920, 1080); break;
		case Window::MenuIDs::DS_QHD: dsSource = std::make_unique<DirectShowSource>(3840, 2160); break;
		default: dsSource = std::make_unique<DirectShowSource>(1280, 720);
	}

	try {
		server = std::make_unique<Server>(6969, *this, &adbBridge);
		server->Start();
	}
	catch (const std::exception& e) {
		wxMessageBox(
			wxString::Format("Critical Error: Could not start network server.\n\nReason: %s\n\nPlease check if port 6969 is in use.", e.what()),
			"Initialization Failed",
			wxOK | wxICON_ERROR | wxCENTRE,
			nullptr
		);

		// Exit application if the server fails to start
		return false;
	}

	SetupUsbTunnels();

	mainWindow = new Window(server->GetHostInfo());

	usbPollTimer = new wxTimer();
	usbPollTimer->Bind(wxEVT_TIMER, [this](wxTimerEvent&) { PollUsbDevices(); });
	usbPollTimer->Start(2000);
	UpdateUsbStatusLabel();

	rtspManager = std::make_unique<RTSP::Manager>(
		*server,
		// OnFrameReceivedCallback
		[&](AVFrame* frame) {
			if (mainWindow && mainWindow->GetCanvas()) {
				mainWindow->GetCanvas()->ProcessRawFrameAsync(frame);
			}
			if (dsSource) {
				dsSource->SendRawFrame(frame);
			}
			snapshotManager.ProcessFrame(frame);
		},
		// OnStatsReceivedCallback
		[&](const RTSP::Receiver::Stats& stats) {
			if (Settings::Get("SHOW_STATS") != 0 && mainWindow)
			{
				std::stringstream ss;
				// Bitrate with 1 decimal precision
				ss << stats.width << "p@" << (int)std::round(stats.fps) << "fps\n" << std::fixed << std::setprecision(1) << stats.bitrate << "Mbps";

				// Safe UI update
				mainWindow->GetEventHandler()->CallAfter([this, labelText = ss.str()]() {
					if (mainWindow && mainWindow->GetStatsText()) {
						mainWindow->GetStatsText()->SetLabelText(labelText);
						// Force layout to prevent overlap if text grows
						mainWindow->GetStatsText()->GetParent()->Layout();
					}
				});
			}
		}
	);

	// Start mDNS discovery for iOS devices on the LAN.
	mdnsBrowser = std::make_unique<Discovery::MdnsBrowser>(
		[this](const Discovery::RawDiscoveryRecord& record) {
			{
				std::lock_guard<std::mutex> lock(discoveredDevicesMutex);
				discoveredDevices[record.instanceName] = record;
			}
			// Update UI on the main thread.
			if (mainWindow) {
				mainWindow->GetEventHandler()->CallAfter([this]() {
					UpdateAvailableDevices();
				});
			}
		},
		[this](const std::string& instanceName) {
			{
				std::lock_guard<std::mutex> lock(discoveredDevicesMutex);
				discoveredDevices.erase(instanceName);
			}
			if (mainWindow) {
				mainWindow->GetEventHandler()->CallAfter([this]() {
					UpdateAvailableDevices();
				});
			}
		}
	);
	mdnsBrowser->Start();

	BindEventListeners();
	mainWindow->Show();

	return true;
}

StreamOptions* Application::TryGetCurrentDeviceStreamOptions()
{
	if (!rtspManager || !rtspManager->HasValidStreamingDevice())
		return nullptr;

	const auto& desc = rtspManager->GetDescriptors()[rtspManager->GetStreamingDevice()];
	return &stateRegistry[desc.name()];
}

void Application::BindEventListeners()
{
	mainWindow->Bind(wxEVT_CLOSE_WINDOW, &Application::OnWindowCloseEvent, this);
	mainWindow->Bind(wxEVT_MENU, &Application::OnMenuEvent, this);

	mainWindow->GetSourceChoice()->Bind(wxEVT_CHOICE, &Application::OnSourceChanged, this);
	mainWindow->GetAdjustmentsButton()->Bind(wxEVT_BUTTON, &Application::ShowAdjustmentsDialog, this);
	mainWindow->GetStreamOptionsButton()->Bind(wxEVT_BUTTON, &Application::ShowStreamConfigDialog, this);

	mainWindow->GetRotateLeftButton()->Bind(wxEVT_BUTTON, [&](const wxEvent& arg) {
		rtspManager->Rotate(-90);
	});

	mainWindow->GetRotateRightButton()->Bind(wxEVT_BUTTON, [&](const wxEvent& arg) {
		rtspManager->Rotate(90);
	});

	mainWindow->GetFlipButton()->Bind(wxEVT_BUTTON, [&](const wxEvent& arg) {
		rtspManager->FlipHorizontally();
	});

	mainWindow->GetFlipVerticalButton()->Bind(wxEVT_BUTTON, [&](const wxEvent& arg) {
		rtspManager->FlipVertically();
	});

	// Check if devices exist before accessing options to prevent crashes
	mainWindow->GetTorchButton()->Bind(wxEVT_BUTTON, [&](const wxEvent& arg) {
		auto* options = TryGetCurrentDeviceStreamOptions();
		if (!options) return;
		options->flashEnabled = !options->flashEnabled;
		rtspManager->SetFlash(options->flashEnabled);
	});

	mainWindow->GetSwapButton()->Bind(wxEVT_BUTTON, [&](const wxEvent& arg) {
		auto* options = TryGetCurrentDeviceStreamOptions();
		if (!options) return;
		auto& optionsRef = *options;
		optionsRef.backCameraActive = !optionsRef.backCameraActive;
		rtspManager->SwapCamera();
	});

	mainWindow->GetZoomInButton()->Bind(wxEVT_BUTTON, [&](const wxEvent& arg) {
		auto* options = TryGetCurrentDeviceStreamOptions();
		if (!options) return;
		auto& optionsRef = *options;
		const auto& desc = rtspManager->GetDescriptors()[rtspManager->GetStreamingDevice()];

		if (desc.isiOS()) {
			// On iOS the lens slider is continuous and capped by the actual
			// device's optical range; clamp generously and let the iPhone
			// re-clamp to its true maximum.
			optionsRef.iosLensZoom = std::min(10.0f, optionsRef.iosLensZoom + 0.5f);
			mainWindow->GetZoomLevelLabel()->SetLabelText(wxString::Format("%.1fx", optionsRef.iosLensZoom));
			rtspManager->SetLensZoom(optionsRef.iosLensZoom);
		} else {
			optionsRef.zoom = std::min(10.0f, optionsRef.zoom + 0.5f);
			mainWindow->GetZoomLevelLabel()->SetLabelText(wxString::Format("%.1fx", optionsRef.zoom));
			rtspManager->Zoom(optionsRef.zoom);
		}
	});

	mainWindow->GetZoomOutButton()->Bind(wxEVT_BUTTON, [&](const wxEvent& arg) {
		auto* options = TryGetCurrentDeviceStreamOptions();
		if (!options) return;
		auto& optionsRef = *options;
		const auto& desc = rtspManager->GetDescriptors()[rtspManager->GetStreamingDevice()];

		if (desc.isiOS()) {
			optionsRef.iosLensZoom = std::max(0.5f, optionsRef.iosLensZoom - 0.5f);
			mainWindow->GetZoomLevelLabel()->SetLabelText(wxString::Format("%.1fx", optionsRef.iosLensZoom));
			rtspManager->SetLensZoom(optionsRef.iosLensZoom);
		} else {
			optionsRef.zoom = std::max(1.0f, optionsRef.zoom - 0.5f);
			mainWindow->GetZoomLevelLabel()->SetLabelText(wxString::Format("%.1fx", optionsRef.zoom));
			rtspManager->Zoom(optionsRef.zoom);
		}
	});

	mainWindow->GetSnapshotButton()->Bind(wxEVT_BUTTON, [&](const wxEvent& arg) {
		if (rtspManager->GetStreamingDevice() < 0) return;
		snapshotManager.RequestSnapshot();
	});

	if (auto* dock = mainWindow->GetCameraDockPanel())
	{
		if (auto* iosPanel = dock->GetIosPanel())
		{
			iosPanel->Bind(EVT_IOS_PORTRAIT_MODE_CHANGED, [this](wxCommandEvent& e)
			{
				auto* panel = static_cast<IosControlsPanel*>(e.GetEventObject());
				auto* options = TryGetCurrentDeviceStreamOptions();
				if (!options || !rtspManager->HasValidStreamingDevice()) return;
				options->iosPortraitModeEnabled = panel->IsPortraitModeEnabled();
				options->iosPortraitStrength = panel->GetPortraitStrength();
				rtspManager->SetPortraitMode(
					options->iosPortraitModeEnabled,
					static_cast<uint8_t>(options->iosPortraitStrength));
			});

			iosPanel->Bind(EVT_IOS_EXPOSURE_CHANGED, [this](wxCommandEvent& e)
			{
				auto* panel = static_cast<IosControlsPanel*>(e.GetEventObject());
				auto* options = TryGetCurrentDeviceStreamOptions();
				if (!options) return;
				options->iosExposureMode = panel->IsManualExposure()
					? StreamOptions::ExposureMode::Manual
					: StreamOptions::ExposureMode::Auto;
				options->iosExposureDurationSeconds = panel->GetExposureDurationSeconds();
				options->iosExposureISO = panel->GetExposureISO();
				options->iosExposureCompensation = panel->GetExposureCompensation();
				if (options->iosExposureMode == StreamOptions::ExposureMode::Manual)
					rtspManager->SetExposure(options->iosExposureDurationSeconds, options->iosExposureISO);
				rtspManager->SetExposureCompensation(options->iosExposureCompensation);
			});

			iosPanel->Bind(EVT_IOS_WHITE_BALANCE_CHANGED, [this](wxCommandEvent& e)
			{
				auto* panel = static_cast<IosControlsPanel*>(e.GetEventObject());
				auto* options = TryGetCurrentDeviceStreamOptions();
				if (!options) return;
				options->iosWhiteBalanceMode = panel->IsManualWhiteBalance()
					? StreamOptions::WhiteBalanceMode::Manual
					: StreamOptions::WhiteBalanceMode::Auto;
				options->iosWhiteBalanceTemperatureK = panel->GetWhiteBalanceTemperatureK();
				options->iosWhiteBalanceTint = panel->GetWhiteBalanceTint();
				if (options->iosWhiteBalanceMode == StreamOptions::WhiteBalanceMode::Manual)
					rtspManager->SetWhiteBalance(options->iosWhiteBalanceTemperatureK, options->iosWhiteBalanceTint);
			});
		}
	}
}

void Application::OnDeviceConnected(DeviceDescriptor& descriptor) const
{
	mainWindow->GetTaskbarIcon()->ShowBalloon("New stream available", "Streaming device " + descriptor.name() + " available!", 10, wxICON_INFORMATION);
	rtspManager->AddDescriptor(descriptor);
	UpdateAvailableDevices();
}

void Application::OnDeviceDisconnected(DeviceDescriptor& descriptor) const
{
	mainWindow->GetTaskbarIcon()->ShowBalloon("Stream ended", "Streaming device " + descriptor.name() + " disconnected!", 10, wxICON_INFORMATION);
	
	// Check if the device that just disconnected was the active streaming device
	// If it was reset the canvas to blank
	int streamingDeviceId = rtspManager->GetStreamingDevice();
	if (streamingDeviceId >= 0)
	{
		const auto& streamingDescriptor = rtspManager->GetDescriptors()[streamingDeviceId];
		if (streamingDescriptor == descriptor)
			mainWindow->GetCanvas()->Clear();
	}

	// Remove from manager (clears streamingDevice when active device disconnects)
	rtspManager->RemoveDescriptor(descriptor);

	if (mainWindow->GetCameraDockPanel())
		mainWindow->GetCameraDockPanel()->SetVisibleForPlatform(false, false);

	mainWindow->GetTorchButton()->Enable(false);

	// Update UI list
	UpdateAvailableDevices();
}

void Application::OnDeviceErrorReported(DeviceDescriptor& descriptor, const Connection::ErrorReport& error) const
{
	auto icon = error.severity == Connection::ErrorReport::SEVERITY_WARNING ? wxICON_WARNING : wxICON_ERROR;
	mainWindow->GetTaskbarIcon()->ShowBalloon(descriptor.name() + " " + error.error, error.description, 1000, icon);
}

void Application::UpdateAvailableDevices() const
{
	auto choice = mainWindow->GetSourceChoice();
	int currentSelectionIndex = rtspManager->GetStreamingDevice();

	choice->Clear();

	const auto& devices = rtspManager->GetDescriptors();

	// Collect discovered-but-not-connected iOS device names.
	std::vector<std::string> discoveredNames;
	{
		std::lock_guard<std::mutex> lock(discoveredDevicesMutex);
		for (const auto& [name, rec] : discoveredDevices)
		{
			bool alreadyConnected = false;
			for (const auto& desc : devices)
			{
				if (desc.name() == name) { alreadyConnected = true; break; }
			}
			if (!alreadyConnected)
				discoveredNames.push_back(name);
		}
	}

	bool hasAny = !devices.empty() || !discoveredNames.empty();

	if (!hasAny)
	{
		choice->Append("No devices");
		choice->SetSelection(0);

		if (mainWindow->GetStatsText())
			mainWindow->GetStatsText()->SetLabelText("----p@--fps\n00.0Mbps");
	}
	else
	{
		choice->Append("Select device");

		// Connected devices first.
		for (auto& desc : devices)
			choice->Append(desc.name());

		// Discovered-but-not-connected iOS devices (via mDNS).
		for (const auto& name : discoveredNames)
			choice->Append(name + "  (Wi-Fi)");

		if (currentSelectionIndex >= 0 && currentSelectionIndex < (int)devices.size())
		{
			choice->SetSelection(currentSelectionIndex + 1);
		}
		else
		{
			choice->SetSelection(0);
		}
	}
}

void Application::OnMenuEvent(wxCommandEvent& event)
{
	switch (event.GetId())
	{
		case Window::MenuIDs::DEVICES:
		{
			std::map<std::string, Discovery::RawDiscoveryRecord> discovered;
			{
				std::lock_guard<std::mutex> lock(discoveredDevicesMutex);
				discovered = discoveredDevices;
			}
			DevicesView devlistview(mainWindow, rtspManager->GetDescriptors(), discovered);
			devlistview.ShowModal();
			break;
		}

		case Window::MenuIDs::QR:
		{
			auto info = server->GetHostInfo();
			QrconView qrview(std::get<0>(info), std::get<1>(info), std::get<2>(info), wxSize(150, 150));
			qrview.ShowModal();
			break;
		}

		case Window::MenuIDs::HIDE2TRAY:
		{
			Settings::Set("MINIMIZE_TASKBAR", event.IsChecked() ? 1 : 0);
			break;
		}

		case Window::MenuIDs::SHOWSTATS:
		{
			Settings::Set("SHOW_STATS", event.IsChecked() ? 1 : 0);
			mainWindow->GetStatsText()->Show(event.IsChecked());
			mainWindow->Layout(); // Refresh layout to hide/show properly
			break;
		}

		case Window::MenuIDs::SAVESTATE:
		{
			Settings::Set("SAVE_DEVICE_STATES", event.IsChecked() ? 1 : 0);
			break;
		}

		case Window::MenuIDs::DS_SD:
		case Window::MenuIDs::DS_HD:
		case Window::MenuIDs::DS_FHD:
		case Window::MenuIDs::DS_QHD:
		{
			Settings::Set("DIRECTSHOW_RESOLUTION", event.GetId() - Window::MenuIDs::DS_SD);
			break;
		}

		case Window::MenuIDs::HELP_OBS:
		{
			wxMessageBox(
				"OBS / Zoom / Teams setup:\n\n"
				"1. Run install.bat once to register the Softcam virtual camera.\n"
				"2. In OBS: Sources → Video Capture Device → \"VCamdroid Camera\" (or Softcam).\n"
				"3. Connect your iPhone in the VCamdroid iOS app (Auto, USB, or Manual).\n"
				"4. Select your phone in the Source dropdown on this window.\n\n"
				"No OBS plugin is required for V1.",
				"Using VCamdroid in OBS",
				wxOK | wxICON_INFORMATION,
				mainWindow);
			break;
		}
	}
}

void Application::OnDiscoveredDeviceSelected(const Discovery::RawDiscoveryRecord& record)
{
	logger << "[app] Connecting to discovered iOS device: " << record.instanceName
	       << " @ " << record.host << ":" << record.controlPort << "\n";

	mainWindow->GetTaskbarIcon()->ShowBalloon(
		"Connecting to " + record.instanceName,
		"Attempting Wi-Fi connection to " + record.host + ":" + std::to_string(record.controlPort),
		5, wxICON_INFORMATION);
}

void Application::OnSourceChanged(wxEvent& event)
{
	int selectionIndex = mainWindow->GetSourceChoice()->GetSelection() - 1;

	if (selectionIndex == wxNOT_FOUND)
		return;

	const auto& connectedDevices = rtspManager->GetDescriptors();

	// Check if this selection is a discovered-but-not-connected device.
	if (selectionIndex >= (int)connectedDevices.size())
	{
		// This is a discovered iOS device from mDNS.
		int discoveredIndex = selectionIndex - (int)connectedDevices.size();
		std::vector<Discovery::RawDiscoveryRecord> discovered;
		{
			std::lock_guard<std::mutex> lock(discoveredDevicesMutex);
			for (const auto& [name, rec] : discoveredDevices)
			{
				bool alreadyConnected = false;
				for (const auto& desc : connectedDevices)
				{
					if (desc.name() == name) { alreadyConnected = true; break; }
				}
				if (!alreadyConnected)
					discovered.push_back(rec);
			}
		}

		if (discoveredIndex >= 0 && discoveredIndex < (int)discovered.size())
			OnDiscoveredDeviceSelected(discovered[discoveredIndex]);

		// Reset selection since this device isn't connected yet.
		mainWindow->GetSourceChoice()->SetSelection(0);
		return;
	}

	int deviceId = selectionIndex;

	if (connectedDevices.empty() || deviceId < 0 || deviceId >= (int)connectedDevices.size())
		return;

	const auto& descriptor = rtspManager->GetDescriptors()[deviceId];

	EnsureStateInitialized(descriptor.name(), descriptor);
	auto& state = stateRegistry[descriptor.name()];

	// Validate Resolution exists in current capabilities
	bool resFound = false;
	const auto& resList = state.backCameraActive ? descriptor.backResolutions() : descriptor.frontResolutions();

	if (!resList.empty())
	{
		for (size_t i = 0; i < resList.size(); i++)
		{
			if (resList[i] == state.resolution)
			{
				resFound = true;
				break;
			}
		}
		if (!resFound)
			state.resolution = resList[0];
	}
	else
	{
		// Handle error case: Device reported 0 resolutions
		mainWindow->GetTaskbarIcon()->ShowBalloon("Error", "Device reported no supported resolutions.", 10, wxICON_WARNING);
	}

	rtspManager->Connect2Stream(deviceId, state);

	if (mainWindow->GetCameraDockPanel())
		mainWindow->GetCameraDockPanel()->SetVisibleForPlatform(descriptor.isiOS(), true);

	mainWindow->GetTorchButton()->Enable(true);

	// Update UI Zoom Label to match state. iOS devices track lens zoom
	// across the entire optical range, Android tracks digital zoom.
	const float displayedZoom = descriptor.isiOS() ? state.iosLensZoom : state.zoom;
	mainWindow->GetZoomLevelLabel()->SetLabelText(wxString::Format("%.1fx", displayedZoom));

	// Push the cached iOS state to the freshly-activated device so the user
	// sees the same image they saw last time.
	if (descriptor.isiOS()) {
		rtspManager->SetLensZoom(state.iosLensZoom);
		if (state.iosExposureMode == StreamOptions::ExposureMode::Manual)
			rtspManager->SetExposure(state.iosExposureDurationSeconds, state.iosExposureISO);
		rtspManager->SetExposureCompensation(state.iosExposureCompensation);
		if (state.iosWhiteBalanceMode == StreamOptions::WhiteBalanceMode::Manual)
			rtspManager->SetWhiteBalance(state.iosWhiteBalanceTemperatureK, state.iosWhiteBalanceTint);
		rtspManager->SetStabilizationMode(state.iosStabilizationMode);
		if (state.iosFocusLockPosition >= 0.0f)
			rtspManager->SetFocusLock(state.iosFocusLockPosition);
		rtspManager->SetPortraitMode(state.iosPortraitModeEnabled, static_cast<uint8_t>(state.iosPortraitStrength));
	}
}

void Application::OnWindowCloseEvent(wxCloseEvent& event)
{
	mainWindow->Hide();

	if (usbPollTimer)
		usbPollTimer->Stop();

	if (mdnsBrowser)
		mdnsBrowser->Stop();

	if (rtspManager)
		rtspManager->StopAll();

	if (server)
		server->Close();

	usbmuxBridge.KillAll();
	adb::kill(6969);
	adb::kill(8554);

	Settings::UpdateDeviceStates(stateRegistry);
	Settings::Save();

	event.Skip();
}

void Application::EnsureStateInitialized(std::string name, const DeviceDescriptor& descriptor)
{
	// operator[] creates the entry if it doesn't exist
	auto& state = stateRegistry[name];

	// Ensure defaults if this is a fresh entry
	if (state.zoom < 1.0f) state.zoom = 1.0f;

	// 1. Initialize Sliders (Default 50 if empty)
	if (descriptor.filters().count(Video::Filter::Category::CORRECTION))
	{
		for (const auto& fname : descriptor.filters().at(Video::Filter::Category::CORRECTION))
		{
			if (state.filterSliderValues.find(fname) == state.filterSliderValues.end())
			{
				state.filterSliderValues[fname] = 50;
			}
		}
	}
}

void Application::ShowAdjustmentsDialog(wxCommandEvent& event)
{
	if (rtspManager->GetDescriptors().empty()) return;

	int currentDeviceId = rtspManager->GetStreamingDevice();
	if (currentDeviceId < 0) return;

	const auto& desc = rtspManager->GetDescriptors()[currentDeviceId];

	EnsureStateInitialized(desc.name(), desc);
	auto& state = stateRegistry[desc.name()];

	ImgAdjDlg dialog(mainWindow, desc, state.filterSliderValues, state.activeEffectFilter);

	dialog.Bind(EVT_FILTER_PARAM_CHANGED, [&](const wxCommandEvent& event) 
	{
		auto name = event.GetString().ToStdString();
		auto value = event.GetInt();

		rtspManager->ApplyCorrectionFilter(name, value);
		state.filterSliderValues[name] = value;
	});

	dialog.Bind(EVT_FILTER_SWITCH_CHANGED, [&](const wxCommandEvent& event) 
	{
		auto name = event.GetString().ToStdString();
		// auto category = event.GetInt();

		rtspManager->ApplyEffectFilter(name);
		state.activeEffectFilter = name;
	});

	dialog.ShowModal();
}

void Application::ShowStreamConfigDialog(wxCommandEvent& event)
{
	int deviceId = rtspManager->GetStreamingDevice();
	if (deviceId < 0 || rtspManager->GetDescriptors().empty())
		return;

	const auto& desc = rtspManager->GetDescriptors()[deviceId];
	std::string deviceName = desc.name();

	EnsureStateInitialized(deviceName, desc);
	auto& state = stateRegistry[deviceName];

	StreamConfigDlg::Config config;

	config.resIndex = 0;
	const auto& resList = state.backCameraActive ? desc.backResolutions() : desc.frontResolutions();
	for (size_t i = 0; i < resList.size(); i++)
	{
		if (resList[i] == state.resolution)
		{
			config.resIndex = i;
			break;
		}
	}

	config.fps = state.fps;
	config.adaptiveBitrate = state.adaptiveBitrate;
	config.bitrate = state.bitrate;
	config.minBitrate = state.minBitrate;
	config.maxBitrate = state.maxBitrate;
	config.stabilizationEnabled = state.stabilizationEnabled;
	config.flashEnabled = state.flashEnabled;
	config.focusMode = state.focusMode;
	config.h265Enabled = state.h265Enabled;

	const StreamOptions* iosOptions = desc.isiOS() ? &state : nullptr;
	StreamConfigDlg dlg(mainWindow, desc, state.backCameraActive, config, iosOptions);

	if (auto* iosPanel = dlg.GetIosPanel())
	{
		iosPanel->Bind(EVT_IOS_LENS_ZOOM_CHANGED, [this, deviceName](wxCommandEvent& e)
		{
			auto* panel = static_cast<IosControlsPanel*>(e.GetEventObject());
			auto zoom = panel->GetLensZoom();
			stateRegistry[deviceName].iosLensZoom = zoom;
			rtspManager->SetLensZoom(zoom);
		});

		iosPanel->Bind(EVT_IOS_EXPOSURE_CHANGED, [this, deviceName](wxCommandEvent& e)
		{
			auto* panel = static_cast<IosControlsPanel*>(e.GetEventObject());
			auto& s = stateRegistry[deviceName];
			s.iosExposureMode = panel->IsManualExposure()
				? StreamOptions::ExposureMode::Manual
				: StreamOptions::ExposureMode::Auto;
			s.iosExposureDurationSeconds = panel->GetExposureDurationSeconds();
			s.iosExposureISO = panel->GetExposureISO();
			s.iosExposureCompensation = panel->GetExposureCompensation();

			if (s.iosExposureMode == StreamOptions::ExposureMode::Manual)
				rtspManager->SetExposure(s.iosExposureDurationSeconds, s.iosExposureISO);

			rtspManager->SetExposureCompensation(s.iosExposureCompensation);
		});

		iosPanel->Bind(EVT_IOS_WHITE_BALANCE_CHANGED, [this, deviceName](wxCommandEvent& e)
		{
			auto* panel = static_cast<IosControlsPanel*>(e.GetEventObject());
			auto& s = stateRegistry[deviceName];
			s.iosWhiteBalanceMode = panel->IsManualWhiteBalance()
				? StreamOptions::WhiteBalanceMode::Manual
				: StreamOptions::WhiteBalanceMode::Auto;
			s.iosWhiteBalanceTemperatureK = panel->GetWhiteBalanceTemperatureK();
			s.iosWhiteBalanceTint = panel->GetWhiteBalanceTint();

			if (s.iosWhiteBalanceMode == StreamOptions::WhiteBalanceMode::Manual)
				rtspManager->SetWhiteBalance(s.iosWhiteBalanceTemperatureK, s.iosWhiteBalanceTint);
		});

		iosPanel->Bind(EVT_IOS_FOCUS_LOCK_CHANGED, [this, deviceName](wxCommandEvent& e)
		{
			auto* panel = static_cast<IosControlsPanel*>(e.GetEventObject());
			auto& s = stateRegistry[deviceName];
			s.iosFocusLockPosition = panel->GetFocusLockPosition();
			rtspManager->SetFocusLock(s.iosFocusLockPosition);
		});

		iosPanel->Bind(EVT_IOS_STABILIZATION_MODE_CHANGED, [this, deviceName](wxCommandEvent& e)
		{
			auto* panel = static_cast<IosControlsPanel*>(e.GetEventObject());
			auto& s = stateRegistry[deviceName];
			s.iosStabilizationMode = panel->GetStabilizationMode();
			rtspManager->SetStabilizationMode(s.iosStabilizationMode);
		});

		iosPanel->Bind(EVT_IOS_RESET_AUTO, [this, deviceName](wxCommandEvent&)
		{
			auto& s = stateRegistry[deviceName];
			s.iosExposureMode = StreamOptions::ExposureMode::Auto;
			s.iosWhiteBalanceMode = StreamOptions::WhiteBalanceMode::Auto;
			s.iosFocusLockPosition = -1.0f;
			rtspManager->ResetCameraToAuto();
		});

		iosPanel->Bind(EVT_IOS_STUDIO_MODE_CHANGED, [this](wxCommandEvent& e)
		{
			auto* panel = static_cast<IosControlsPanel*>(e.GetEventObject());
			rtspManager->SetStudioMode(panel->IsStudioModeEnabled());
		});
	}

	dlg.Bind(EVT_STREAM_RESOLUTION_CHANGED, [this, deviceName](wxCommandEvent& e) 
	{
		wxString resStr = e.GetString(); // "1920 x 1080"
		long w = 0, h = 0;
		resStr.BeforeFirst('x').ToLong(&w);
		resStr.AfterFirst('x').ToLong(&h);

		rtspManager->SetResolution((uint16_t)w, (uint16_t)h);
		stateRegistry[deviceName].resolution = { (int)w, (int)h };
	});

	dlg.Bind(EVT_STREAM_FPS_CHANGED, [this, deviceName](wxCommandEvent& e) 
	{
		int fps = e.GetInt();
		rtspManager->SetFPS(fps);
		stateRegistry[deviceName].fps = fps;
	});

	dlg.Bind(EVT_STREAM_BITRATE_CHANGED, [this, deviceName, &dlg](wxCommandEvent& e) 
	{
		auto& regState = stateRegistry[deviceName];
		regState.adaptiveBitrate = dlg.IsAdaptiveBitrate();
		regState.bitrate = dlg.GetStaticBitrate();
		regState.minBitrate = dlg.GetMinBitrate();
		regState.maxBitrate = dlg.GetMaxBitrate();

		if (regState.adaptiveBitrate) 
		{
			rtspManager->SetAdaptiveBitrate(regState.minBitrate, regState.maxBitrate);
		}
		else 
		{
			rtspManager->SetBitrate(regState.bitrate);
		}
	});

	dlg.Bind(EVT_STREAM_CONFIG_CHANGED, [this, deviceName, &dlg](wxCommandEvent& e) 
	{
		auto& regState = stateRegistry[deviceName];

		if (regState.stabilizationEnabled != dlg.IsStabilizationEnabled()) 
		{
			regState.stabilizationEnabled = dlg.IsStabilizationEnabled();
			rtspManager->SetStabilization(regState.stabilizationEnabled);
		}

		if (regState.flashEnabled != dlg.IsFlashEnabled()) 
		{
			regState.flashEnabled = dlg.IsFlashEnabled();
			rtspManager->SetFlash(regState.flashEnabled);
		}

		if (regState.focusMode != dlg.GetFocusMode()) 
		{
			regState.focusMode = dlg.GetFocusMode();
			rtspManager->SetFocusMode(regState.focusMode);
		}

		if (regState.h265Enabled != dlg.IsH265Enabled()) 
		{
			regState.h265Enabled = dlg.IsH265Enabled();
			rtspManager->SetH265Codec(regState.h265Enabled);
		}
	});

	dlg.ShowModal();
}