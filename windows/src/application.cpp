#include "application.h"

#include "gui/imgadjdlg.h"
#include "gui/streamconfigdlg.h"
#include "gui/ioscontrolspanel.h"
#include "gui/devicesview.h"
#include "gui/qrconview.h"
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

bool Application::OnInit()
{
	if (!wxApp::OnInit())
		return false;

	switch (Settings::Get("DIRECTSHOW_RESOLUTION") + Window::MenuIDs::DS_SD)
	{
		case Window::MenuIDs::DS_SD: dsSource = std::make_unique<DirectShowSource>(640, 480); break;
		case Window::MenuIDs::DS_HD: dsSource = std::make_unique<DirectShowSource>(1280, 720); break;
		case Window::MenuIDs::DS_FHD: dsSource = std::make_unique<DirectShowSource>(1920, 1080); break;
		case Window::MenuIDs::DS_QHD: dsSource = std::make_unique<DirectShowSource>(3840, 2160); break;
		default: dsSource = std::make_unique<DirectShowSource>(1280, 720);
	}

	try {
		server = std::make_unique<Server>(6969, *this);
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

	mainWindow = new Window(server->GetHostInfo());

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

	BindEventListeners();
	mainWindow->Show();

	return true;
}

StreamOptions& Application::GetCurrentDeviceStreamOptions()
{
	auto deviceId = rtspManager->GetStreamingDevice();
	// Safety check: if no device is streaming, return a dummy or handle error
	// For now assuming caller checks availability, but using .at() checks bounds
	const auto& desc = rtspManager->GetDescriptors().at(deviceId);
	return stateRegistry[desc.name()];
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
		if (rtspManager->GetStreamingDevice() < 0) return;
		auto& options = GetCurrentDeviceStreamOptions();
		auto flash = options.flashEnabled = !options.flashEnabled;
		rtspManager->SetFlash(flash);
	});

	mainWindow->GetSwapButton()->Bind(wxEVT_BUTTON, [&](const wxEvent& arg) {
		if (rtspManager->GetStreamingDevice() < 0) return;
		auto& options = GetCurrentDeviceStreamOptions();
		options.backCameraActive = !options.backCameraActive;
		rtspManager->SwapCamera();
	});

	mainWindow->GetZoomInButton()->Bind(wxEVT_BUTTON, [&](const wxEvent& arg) {
		if (rtspManager->GetStreamingDevice() < 0) return;
		auto& options = GetCurrentDeviceStreamOptions();
		const auto& desc = rtspManager->GetDescriptors()[rtspManager->GetStreamingDevice()];

		if (desc.isiOS()) {
			// On iOS the lens slider is continuous and capped by the actual
			// device's optical range; clamp generously and let the iPhone
			// re-clamp to its true maximum.
			options.iosLensZoom = std::min(10.0f, options.iosLensZoom + 0.5f);
			mainWindow->GetZoomLevelLabel()->SetLabelText(wxString::Format("%.1fx", options.iosLensZoom));
			rtspManager->SetLensZoom(options.iosLensZoom);
		} else {
			options.zoom = std::min(10.0f, options.zoom + 0.5f);
			mainWindow->GetZoomLevelLabel()->SetLabelText(wxString::Format("%.1fx", options.zoom));
			rtspManager->Zoom(options.zoom);
		}
	});

	mainWindow->GetZoomOutButton()->Bind(wxEVT_BUTTON, [&](const wxEvent& arg) {
		if (rtspManager->GetStreamingDevice() < 0) return;
		auto& options = GetCurrentDeviceStreamOptions();
		const auto& desc = rtspManager->GetDescriptors()[rtspManager->GetStreamingDevice()];

		if (desc.isiOS()) {
			options.iosLensZoom = std::max(0.5f, options.iosLensZoom - 0.5f);
			mainWindow->GetZoomLevelLabel()->SetLabelText(wxString::Format("%.1fx", options.iosLensZoom));
			rtspManager->SetLensZoom(options.iosLensZoom);
		} else {
			options.zoom = std::max(1.0f, options.zoom - 0.5f);
			mainWindow->GetZoomLevelLabel()->SetLabelText(wxString::Format("%.1fx", options.zoom));
			rtspManager->Zoom(options.zoom);
		}
	});

	mainWindow->GetSnapshotButton()->Bind(wxEVT_BUTTON, [&](const wxEvent& arg) {
		if (rtspManager->GetStreamingDevice() < 0) return;
		snapshotManager.RequestSnapshot();
	});
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

	// Remove from manager
	rtspManager->RemoveDescriptor(descriptor);

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

	if (devices.empty())
	{
		// Logic Change: If empty, add placeholder and select it
		choice->Append("No devices");
		choice->SetSelection(0);

		// Optional: Clear stats since nothing is playing
		if (mainWindow->GetStatsText())
			mainWindow->GetStatsText()->SetLabelText("----p@--fps\n00.0Mbps");
	}
	else
	{
		choice->Append("Select device");

		// Repopulate
		for (auto& desc : devices)
			choice->Append(desc.name());

		if (currentSelectionIndex >= 0 && currentSelectionIndex < (int)devices.size())
		{
			// Only restore selection if valid
			choice->SetSelection(currentSelectionIndex + 1);
		}
		else
		{
			// If the previously selected device is gone, or we stopped, select nothing
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
			DevicesView devlistview(mainWindow, rtspManager->GetDescriptors());
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
	}
}

void Application::OnSourceChanged(wxEvent& event)
{
	int deviceId = mainWindow->GetSourceChoice()->GetSelection() - 1;

	// Safety: Handle empty list or "No devices" placeholder
	if (deviceId == wxNOT_FOUND || rtspManager->GetDescriptors().empty())
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
	}
}

void Application::OnWindowCloseEvent(wxCloseEvent& event)
{
	// Hide window for responsive UI close feeling
	mainWindow->Hide();

	rtspManager.reset();
	server->Close();

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