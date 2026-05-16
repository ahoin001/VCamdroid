#include "gui/window.h"
#include "gui/cameradockpanel.h"
#include "settings.h"
#include "icon.xpm"

#include <wx/dc.h>
#include <wx/settings.h>
#include <wx/statline.h>

#include <wx/statbox.h>

Window::Window(Server::HostInfo hostinfo)
	: wxFrame(nullptr, wxID_ANY, "VCamdroid", wxDefaultPosition, wxSize(840, 700))
{
	wxPanel* panel = nullptr;
	try {
		panel = new wxPanel(this, wxID_ANY);
	}
	catch (...) {
		wxMessageBox("Failed to create UI Panel.", "Error");
		return;
	}

	const bool dark = wxSystemSettings::GetAppearance().IsDark();
	if (dark)
		panel->SetBackgroundColour(wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOW));
	else
		panel->SetBackgroundColour(wxColour(246, 247, 251));

	wxBoxSizer* topsizer = new wxBoxSizer(wxVERTICAL);

	taskbarIcon = new wxTaskBarIcon();
	taskbarIcon->SetIcon(icon, "VCamdroid");
	taskbarIcon->Bind(wxEVT_TASKBAR_LEFT_DCLICK, &Window::MaximizeFromTaskbar, this);
	Bind(wxEVT_ICONIZE, &Window::MinimizeToTaskbar, this);

	SetIcon(icon);
	InitializeMenu(hostinfo);

	InitializeTopBar(panel, topsizer);

	usbStatusText = new wxStaticText(panel, wxID_ANY, "");
	usbStatusText->SetForegroundColour(wxColour(108, 115, 132));
	topsizer->Add(usbStatusText, 0, wxLEFT | wxRIGHT | wxBOTTOM, 10);

	InitializeCanvasPanel(panel, topsizer);

	cameraDockPanel = new CameraDockPanel(panel);
	topsizer->Add(cameraDockPanel, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, 10);

	InitializeBottomBar(panel, topsizer);

	panel->SetSizer(topsizer);
	panel->Layout();

	Center();
}

Window::~Window()
{
	delete taskbarIcon;
}

void Window::InitializeMenu(Server::HostInfo hostinfo)
{
	wxMenuBar* menuBar = new wxMenuBar();

	const wxString pcIp = std::get<1>(hostinfo);
	const wxString pcPort = std::get<2>(hostinfo);

	wxMenu* appMenu = new wxMenu();

	auto hideTray = appMenu->AppendCheckItem(MenuIDs::HIDE2TRAY, "Keep running in the background");
	hideTray->SetHelp("When minimized, hide this window to the tray instead of the taskbar.");
	hideTray->Check(Settings::Get("MINIMIZE_TASKBAR") == 1);

	auto statsItem = appMenu->AppendCheckItem(MenuIDs::SHOWSTATS, "Show streaming statistics");
	statsItem->SetHelp("Shows resolution, fps and bitrate in the corner.");
	statsItem->Check(Settings::Get("SHOW_STATS") == 1);

	auto presetsItem = appMenu->AppendCheckItem(MenuIDs::SAVESTATE, "Remember settings for each phone");
	presetsItem->Check(Settings::Get("SAVE_DEVICE_STATES") == 1);

	wxMenu* virtualCamMenu = new wxMenu();
	virtualCamMenu->AppendRadioItem(MenuIDs::DS_SD, "640 × 480", "Good for older PCs");
	virtualCamMenu->AppendRadioItem(MenuIDs::DS_HD, "1280 × 720", "Balanced");
	virtualCamMenu->AppendRadioItem(MenuIDs::DS_FHD, "1920 × 1080", "Sharpest");
	virtualCamMenu->AppendRadioItem(MenuIDs::DS_QHD, "3840 × 2160", "Very large");

	auto dsSel = Settings::Get("DIRECTSHOW_RESOLUTION");
	virtualCamMenu->Check((dsSel != -1 ? dsSel : 0) + MenuIDs::DS_SD, true);

	appMenu->AppendSubMenu(virtualCamMenu, "&Virtual camera size",
		"Output resolution other apps see as \"VCamdroid Camera\". Restart after changing.");
	appMenu->AppendSeparator();
	appMenu->Append(wxID_EXIT, "E&xit\tAlt+F4");
	menuBar->Append(appMenu, "&VCamdroid");

	wxMenu* connectMenu = new wxMenu();
	connectMenu->Append(MenuIDs::QR, "&QR code for the phone app…");
	connectMenu->AppendSeparator();
	auto* addrLine = connectMenu->Append(wxID_ANY, wxString::Format("Your PC address:  %s", pcIp));
	addrLine->Enable(false);
	auto* portLine = connectMenu->Append(wxID_ANY, wxString::Format("Connection port:   %s", pcPort));
	portLine->Enable(false);
	menuBar->Append(connectMenu, "&Connect");

	wxMenu* devicesMenu = new wxMenu();
	devicesMenu->Append(MenuIDs::DEVICES, "&Connected devices…");
	menuBar->Append(devicesMenu, "&Devices");

	wxMenu* helpMenu = new wxMenu();
	helpMenu->Append(MenuIDs::HELP_QUICKSTART, "&Quick start guide");
	helpMenu->Append(MenuIDs::HELP_OBS, "&OBS, Zoom & Teams…");
	helpMenu->AppendSeparator();
	helpMenu->Append(wxID_ABOUT, "&About VCamdroid");
	menuBar->Append(helpMenu, "&Help");

	SetMenuBar(menuBar);
}

void Window::InitializeTopBar(wxPanel* parent, wxBoxSizer* topsizer)
{
	const bool darkUi = wxSystemSettings::GetAppearance().IsDark();
	const wxColour labelStrong = darkUi ? wxColour(235, 237, 242) : wxColour(52, 56, 68);
	const wxColour hintMuted = darkUi ? wxColour(165, 170, 185) : wxColour(105, 112, 128);

	auto* box = new wxStaticBoxSizer(wxVERTICAL, parent, "Your camera");

	auto* hint = new wxStaticText(parent, wxID_ANY,
		"Choose your phone, then pick USB or Wi-Fi so it matches the VCamdroid app on your iPhone.");
	hint->SetForegroundColour(hintMuted);
	wxFont hf = hint->GetFont();
	const int ps = hf.GetPointSize();
	hf.SetPointSize(ps > 1 ? ps - 1 : ps);
	hint->SetFont(hf);
	hint->Wrap(760);
	box->Add(hint, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, 8);

	wxBoxSizer* topBarSizer = new wxBoxSizer(wxHORIZONTAL);

	wxStaticText* srcLabel = new wxStaticText(parent, wxID_ANY, "Device");
	wxFont font = srcLabel->GetFont();
	font.SetWeight(wxFONTWEIGHT_SEMIBOLD);
	srcLabel->SetFont(font);
	srcLabel->SetForegroundColour(labelStrong);
	topBarSizer->Add(srcLabel, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 8);

	sourceChoice = new wxChoice(parent, wxID_ANY, wxDefaultPosition, wxSize(190, -1), 1, new wxString[1]{ "No phones yet" });
	topBarSizer->Add(sourceChoice, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 12);

	wxStaticText* iphoneVideoLabel = new wxStaticText(parent, wxID_ANY, "Video path");
	iphoneVideoLabel->SetFont(font);
	iphoneVideoLabel->SetForegroundColour(labelStrong);
	topBarSizer->Add(iphoneVideoLabel, 0, wxALIGN_CENTER_VERTICAL | wxLEFT | wxRIGHT, 8);

	iosLinkModeChoice = new wxChoice(parent, wxID_ANY, wxDefaultPosition, wxSize(230, -1));
	iosLinkModeChoice->Append("Automatic (USB when plugged in)");
	iosLinkModeChoice->Append("USB (with cable)");
	iosLinkModeChoice->Append("Wi-Fi (same network)");
	{
		int modeSel = Settings::Get("IOS_LINK_MODE");
		if (modeSel < 0 || modeSel > 2)
			modeSel = 0;
		iosLinkModeChoice->SetSelection(modeSel);
	}
	iosLinkModeChoice->SetToolTip(
		"Pick what matches your iPhone app.\n"
		"USB: calm and steady when your phone is plugged in.\n"
		"Wi-Fi: wireless on the same home network.\n"
		"Automatic chooses USB when Windows sees your phone.");
	topBarSizer->Add(iosLinkModeChoice, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 8);

	topBarSizer->AddStretchSpacer(1);

	wxBoxSizer* sizer = new wxBoxSizer(wxHORIZONTAL);

	statsText = new wxStaticText(parent, wxID_ANY, "----p@--fps\n00.0mbps", wxDefaultPosition, wxDefaultSize, wxALIGN_RIGHT);

	wxFont statsFont = statsText->GetFont();
	statsFont.SetPointSize(statsFont.GetPointSize() - 1);
	statsText->SetFont(statsFont);
	statsText->SetForegroundColour(hintMuted);

	statsText->Show(Settings::Get("SHOW_STATS") == 1);

	sizer->Add(statsText, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 10);

	streamOptionsButton = new wxBitmapButton(parent, wxID_ANY, wxBitmap("res/setting.png", wxBITMAP_TYPE_PNG));
	streamOptionsButton->SetToolTip("Picture quality & streaming options");
	sizer->Add(streamOptionsButton, 0, wxALIGN_CENTER_VERTICAL);

	topBarSizer->Add(sizer, 0, wxALIGN_CENTER_VERTICAL);

	box->Add(topBarSizer, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, 10);
	topsizer->Add(box, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP, 12);
}

void Window::InitializeCanvasPanel(wxPanel* parent, wxBoxSizer* topsizer)
{
	const bool darkUi = wxSystemSettings::GetAppearance().IsDark();
	const wxColour hintMuted = darkUi ? wxColour(165, 170, 185) : wxColour(105, 112, 128);

	auto* cap = new wxStaticText(parent, wxID_ANY, "Live preview");
	wxFont cf = cap->GetFont();
	cf.SetWeight(wxFONTWEIGHT_SEMIBOLD);
	const int cps = cf.GetPointSize();
	cf.SetPointSize(cps > 1 ? cps - 1 : cps);
	cap->SetFont(cf);
	cap->SetForegroundColour(hintMuted);
	topsizer->Add(cap, 0, wxLEFT | wxRIGHT | wxBOTTOM, 4);

	canvas = new Canvas(parent, wxDefaultPosition, wxSize(420, 315));
	topsizer->Add(canvas, 0, wxALIGN_CENTER_HORIZONTAL | wxLEFT | wxRIGHT | wxBOTTOM, 12);
}

void Window::InitializeBottomBar(wxPanel* parent, wxBoxSizer* topsizer)
{
	const bool darkUi = wxSystemSettings::GetAppearance().IsDark();
	const wxColour hintMuted = darkUi ? wxColour(165, 170, 185) : wxColour(105, 112, 128);

	auto* toolsCaption = new wxStaticText(parent, wxID_ANY, "Adjust your shot");
	wxFont tf = toolsCaption->GetFont();
	tf.SetWeight(wxFONTWEIGHT_SEMIBOLD);
	const int tps = tf.GetPointSize();
	tf.SetPointSize(tps > 1 ? tps - 1 : tps);
	toolsCaption->SetFont(tf);
	toolsCaption->SetForegroundColour(hintMuted);
	topsizer->Add(toolsCaption, 0, wxLEFT | wxRIGHT | wxBOTTOM, 4);

	wxStaticLine* line = new wxStaticLine(parent, wxID_ANY, wxDefaultPosition, wxSize(1, 1), wxLI_HORIZONTAL);
	topsizer->Add(line, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, 10);

	wxBoxSizer* bottomBarSizer = new wxBoxSizer(wxHORIZONTAL);

	// --- GROUP 1: TRANSFORMS ---
	wxBoxSizer* groupTransform = new wxBoxSizer(wxHORIZONTAL);

	rotateLeftButton = new wxBitmapButton(parent, wxID_ANY, wxBitmap("res/rotate-left.png", wxBITMAP_TYPE_PNG));
	rotateLeftButton->SetToolTip("Rotate left");
	groupTransform->Add(rotateLeftButton, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 2);

	rotateRightButton = new wxBitmapButton(parent, wxID_ANY, wxBitmap("res/rotate-right.png", wxBITMAP_TYPE_PNG));
	rotateRightButton->SetToolTip("Rotate right");
	groupTransform->Add(rotateRightButton, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 2);

	flipButton = new wxBitmapButton(parent, wxID_ANY, wxBitmap("res/flip.png", wxBITMAP_TYPE_PNG));
	flipButton->SetToolTip("Flip sideways");
	groupTransform->Add(flipButton, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 2);

	flipVerticalButton = new wxBitmapButton(parent, wxID_ANY, wxBitmap("res/flip-v.png", wxBITMAP_TYPE_PNG));
	flipVerticalButton->SetToolTip("Flip vertically");
	groupTransform->Add(flipVerticalButton, 0, wxALIGN_CENTER_VERTICAL);

	bottomBarSizer->Add(groupTransform, 0, wxALIGN_CENTER_VERTICAL);
	bottomBarSizer->AddStretchSpacer(1);


	// --- GROUP 2: ZOOM ---
	wxBoxSizer* groupZoom = new wxBoxSizer(wxHORIZONTAL);

	zoomOutButton = new wxBitmapButton(parent, wxID_ANY, wxBitmap("res/zoom-out.png", wxBITMAP_TYPE_PNG));
	zoomOutButton->SetToolTip("Zoom out");
	groupZoom->Add(zoomOutButton, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 4);

	zoomLevelLabel = new wxStaticText(parent, wxID_ANY, "1.0x", wxDefaultPosition, wxSize(32, -1), wxALIGN_CENTER);
	wxFont smallFont = zoomLevelLabel->GetFont();
	smallFont.SetPointSize(smallFont.GetPointSize() - 1);
	zoomLevelLabel->SetFont(smallFont);
	zoomLevelLabel->SetForegroundColour(hintMuted);
	groupZoom->Add(zoomLevelLabel, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 4);

	zoomInButton = new wxBitmapButton(parent, wxID_ANY, wxBitmap("res/zoom-in.png", wxBITMAP_TYPE_PNG));
	zoomInButton->SetToolTip("Zoom in");
	groupZoom->Add(zoomInButton, 0, wxALIGN_CENTER_VERTICAL);

	bottomBarSizer->Add(groupZoom, 0, wxALIGN_CENTER_VERTICAL);
	bottomBarSizer->AddStretchSpacer(1);


	// --- GROUP 3: DEVICE ---
	wxBoxSizer* groupDevice = new wxBoxSizer(wxHORIZONTAL);

	torchButton = new wxBitmapButton(parent, wxID_ANY, wxBitmap("res/flash.png", wxBITMAP_TYPE_PNG));
	torchButton->SetToolTip("Light on / off");
	groupDevice->Add(torchButton, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 5);

	swapButton = new wxBitmapButton(parent, wxID_ANY, wxBitmap("res/swap.png", wxBITMAP_TYPE_PNG));
	swapButton->SetToolTip("Front or back camera");
	groupDevice->Add(swapButton, 0, wxALIGN_CENTER_VERTICAL);

	snapshotButton = new wxBitmapButton(parent, wxID_ANY, wxBitmap("res/photo.png", wxBITMAP_TYPE_PNG));
	snapshotButton->SetToolTip("Save a photo");
	groupDevice->Add(snapshotButton, 0, wxALIGN_CENTER_VERTICAL);

	bottomBarSizer->Add(groupDevice, 0, wxALIGN_CENTER_VERTICAL);
	bottomBarSizer->AddStretchSpacer(1);


	// --- GROUP 4: TOOLS ---
	wxBoxSizer* groupTools = new wxBoxSizer(wxHORIZONTAL);

	adjustmentsButton = new wxBitmapButton(parent, wxID_ANY, wxBitmap("res/settings.png", wxBITMAP_TYPE_PNG));
	adjustmentsButton->SetToolTip("Color & filters");
	groupTools->Add(adjustmentsButton, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 2);

	bottomBarSizer->Add(groupTools, 0, wxALIGN_CENTER_VERTICAL);

	topsizer->Add(bottomBarSizer, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, 10);
}

void Window::MinimizeToTaskbar(wxIconizeEvent& evt)
{
	if (Settings::Get("MINIMIZE_TASKBAR") == 1)
	{
		this->Hide();
		evt.Skip();
	}
}

void Window::MaximizeFromTaskbar(wxTaskBarIconEvent& evt)
{
	this->Iconize(false);
	this->SetFocus();
	this->Raise();
	this->Show();
}

Canvas* Window::GetCanvas() { return canvas; }
wxChoice* Window::GetSourceChoice() { return sourceChoice; }
wxChoice* Window::GetIosLinkModeChoice() { return iosLinkModeChoice; }
wxButton* Window::GetStreamOptionsButton() { return streamOptionsButton; }

wxButton* Window::GetRotateLeftButton() { return rotateLeftButton; }
wxButton* Window::GetRotateRightButton() { return rotateRightButton; }
wxButton* Window::GetFlipButton() { return flipButton; }
wxButton* Window::GetFlipVerticalButton() { return flipVerticalButton; }

wxButton* Window::GetZoomInButton() { return zoomInButton; }
wxButton* Window::GetZoomOutButton() { return zoomOutButton; }
wxStaticText* Window::GetZoomLevelLabel() { return zoomLevelLabel; }

wxButton* Window::GetTorchButton() { return torchButton; }
wxButton* Window::GetSwapButton() { return swapButton; }

wxButton* Window::GetAdjustmentsButton() { return adjustmentsButton; }
wxButton* Window::GetSnapshotButton() { return snapshotButton; }

wxStaticText* Window::GetStatsText() { return statsText; }
wxStaticText* Window::GetUsbStatusText() { return usbStatusText; }
CameraDockPanel* Window::GetCameraDockPanel() { return cameraDockPanel; }
wxTaskBarIcon* Window::GetTaskbarIcon() { return taskbarIcon; }