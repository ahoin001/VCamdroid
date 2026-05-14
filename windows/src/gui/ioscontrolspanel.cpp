#include "gui/ioscontrolspanel.h"

#include <wx/statline.h>

wxDEFINE_EVENT(EVT_IOS_LENS_ZOOM_CHANGED, wxCommandEvent);
wxDEFINE_EVENT(EVT_IOS_EXPOSURE_CHANGED, wxCommandEvent);
wxDEFINE_EVENT(EVT_IOS_WHITE_BALANCE_CHANGED, wxCommandEvent);
wxDEFINE_EVENT(EVT_IOS_STABILIZATION_MODE_CHANGED, wxCommandEvent);
wxDEFINE_EVENT(EVT_IOS_FOCUS_LOCK_CHANGED, wxCommandEvent);
wxDEFINE_EVENT(EVT_IOS_RESET_AUTO, wxCommandEvent);
wxDEFINE_EVENT(EVT_IOS_STUDIO_MODE_CHANGED, wxCommandEvent);

namespace
{
    // Sliders are integer-valued; we encode floats as fixed-point so the
    // slider position maps cleanly to the wire-format float we actually
    // send. These constants are deliberately conservative so the UI is not
    // tempted to send physically impossible values.
    constexpr int kLensSliderMin   = 5;    // 0.5x
    constexpr int kLensSliderMax   = 100;  // 10x (capped well past 5x for safety)
    constexpr int kLensSliderScale = 10;   // 1.0x -> 10

    constexpr int kIsoMin = 25;
    constexpr int kIsoMax = 6400;

    constexpr int kCompMin = -200;  // -2.00 EV
    constexpr int kCompMax = 200;   // +2.00 EV
    constexpr int kCompScale = 100; // ev * 100

    constexpr int kTempMin = 2500;
    constexpr int kTempMax = 10000;

    constexpr int kTintMin = -150;
    constexpr int kTintMax = 150;

    constexpr int kFocusMin = 0;
    constexpr int kFocusMax = 100;
    constexpr int kFocusScale = 100; // 0..1 -> 0..100

    // Common exposure shutter speeds (seconds). We snap to these so the
    // slider feels deliberate rather than spongy.
    const float kShutterTable[] = {
        1.0f/1000.0f, 1.0f/500.0f, 1.0f/250.0f, 1.0f/125.0f,
        1.0f/60.0f,   1.0f/30.0f,  1.0f/15.0f,  1.0f/8.0f,
        1.0f/4.0f,    1.0f/2.0f,   1.0f
    };
    constexpr int kShutterTableSize = static_cast<int>(sizeof(kShutterTable) / sizeof(kShutterTable[0]));

    wxString FormatShutter(float seconds)
    {
        if (seconds >= 1.0f) return wxString::Format("%.1f s", seconds);
        return wxString::Format("1/%d s", static_cast<int>(std::round(1.0f / seconds)));
    }

    int ShutterIndexFor(float seconds)
    {
        int bestIndex = 0;
        float bestDelta = std::numeric_limits<float>::max();
        for (int i = 0; i < kShutterTableSize; ++i)
        {
            float d = std::fabs(kShutterTable[i] - seconds);
            if (d < bestDelta) { bestDelta = d; bestIndex = i; }
        }
        return bestIndex;
    }
}

IosControlsPanel::IosControlsPanel(wxWindow* parent, const StreamOptions& initial)
    : wxPanel(parent, wxID_ANY)
{
    auto* root = new wxBoxSizer(wxVERTICAL);

    auto* outerBox = new wxStaticBoxSizer(wxVERTICAL, this, "iOS Premium Camera Controls");

    auto* inner = new wxBoxSizer(wxVERTICAL);

    BuildLensSection(inner);
    inner->AddSpacer(8);
    BuildExposureSection(inner);
    inner->AddSpacer(8);
    BuildWhiteBalanceSection(inner);
    inner->AddSpacer(8);
    BuildFocusSection(inner);
    inner->AddSpacer(8);
    BuildStabilizationSection(inner);
    inner->AddSpacer(8);
    BuildResetSection(inner);

    outerBox->Add(inner, 1, wxEXPAND | wxALL, 10);
    root->Add(outerBox, 1, wxEXPAND | wxALL, 0);

    SetSizerAndFit(root);

    // Seed initial state.
    lensSlider->SetValue(static_cast<int>(std::round(initial.iosLensZoom * kLensSliderScale)));
    lensLabel->SetLabel(wxString::Format("%.1fx", initial.iosLensZoom));

    exposureModeChoice->SetSelection(initial.iosExposureMode == StreamOptions::ExposureMode::Manual ? 1 : 0);
    exposureDurationSlider->SetValue(ShutterIndexFor(initial.iosExposureDurationSeconds));
    exposureDurationLabel->SetLabel(FormatShutter(initial.iosExposureDurationSeconds));
    exposureIsoSlider->SetValue(static_cast<int>(initial.iosExposureISO));
    exposureIsoLabel->SetLabel(wxString::Format("ISO %d", static_cast<int>(initial.iosExposureISO)));
    exposureCompSlider->SetValue(static_cast<int>(std::round(initial.iosExposureCompensation * kCompScale)));
    exposureCompLabel->SetLabel(wxString::Format("%+.2f EV", initial.iosExposureCompensation));

    whiteBalanceModeChoice->SetSelection(initial.iosWhiteBalanceMode == StreamOptions::WhiteBalanceMode::Manual ? 1 : 0);
    whiteBalanceTempSlider->SetValue(static_cast<int>(initial.iosWhiteBalanceTemperatureK));
    whiteBalanceTempLabel->SetLabel(wxString::Format("%dK", static_cast<int>(initial.iosWhiteBalanceTemperatureK)));
    whiteBalanceTintSlider->SetValue(static_cast<int>(initial.iosWhiteBalanceTint));
    whiteBalanceTintLabel->SetLabel(wxString::Format("%+d", static_cast<int>(initial.iosWhiteBalanceTint)));

    focusLockCheck->SetValue(initial.iosFocusLockPosition >= 0.0f);
    focusLockSlider->SetValue(static_cast<int>(std::round(std::max(0.0f, initial.iosFocusLockPosition) * kFocusScale)));
    focusLockLabel->SetLabel(wxString::Format("%.2f", std::max(0.0f, initial.iosFocusLockPosition)));

    stabilizationChoice->SetSelection(initial.iosStabilizationMode);

    RefreshExposureUI();
    RefreshWhiteBalanceUI();
    RefreshFocusUI();
}

void IosControlsPanel::BuildLensSection(wxBoxSizer* parent)
{
    auto* row = new wxBoxSizer(wxHORIZONTAL);
    row->Add(new wxStaticText(this, wxID_ANY, "Lens zoom"), 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 10);

    lensSlider = new wxSlider(this, wxID_ANY, kLensSliderScale, kLensSliderMin, kLensSliderMax);
    lensSlider->Bind(wxEVT_SLIDER, &IosControlsPanel::OnLensSlider, this);
    row->Add(lensSlider, 1, wxEXPAND | wxRIGHT, 5);

    lensLabel = new wxStaticText(this, wxID_ANY, "1.0x", wxDefaultPosition, wxSize(60, -1), wxALIGN_RIGHT);
    row->Add(lensLabel, 0, wxALIGN_CENTER_VERTICAL);

    parent->Add(row, 0, wxEXPAND);
}

void IosControlsPanel::BuildExposureSection(wxBoxSizer* parent)
{
    auto* header = new wxBoxSizer(wxHORIZONTAL);
    header->Add(new wxStaticText(this, wxID_ANY, "Exposure"), 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 10);

    exposureModeChoice = new wxChoice(this, wxID_ANY);
    exposureModeChoice->Append("Auto");
    exposureModeChoice->Append("Manual");
    exposureModeChoice->SetSelection(0);
    exposureModeChoice->Bind(wxEVT_CHOICE, &IosControlsPanel::OnExposureChanged, this);
    header->Add(exposureModeChoice, 0);
    parent->Add(header, 0, wxBOTTOM, 5);

    auto* grid = new wxFlexGridSizer(3, 3, 5, 8);
    grid->AddGrowableCol(1, 1);

    grid->Add(new wxStaticText(this, wxID_ANY, "Shutter:"), 0, wxALIGN_CENTER_VERTICAL);
    exposureDurationSlider = new wxSlider(this, wxID_ANY, 4, 0, kShutterTableSize - 1);
    exposureDurationSlider->Bind(wxEVT_SLIDER, &IosControlsPanel::OnExposureChanged, this);
    grid->Add(exposureDurationSlider, 1, wxEXPAND);
    exposureDurationLabel = new wxStaticText(this, wxID_ANY, "1/60 s", wxDefaultPosition, wxSize(80, -1), wxALIGN_RIGHT);
    grid->Add(exposureDurationLabel, 0, wxALIGN_CENTER_VERTICAL);

    grid->Add(new wxStaticText(this, wxID_ANY, "ISO:"), 0, wxALIGN_CENTER_VERTICAL);
    exposureIsoSlider = new wxSlider(this, wxID_ANY, 100, kIsoMin, kIsoMax);
    exposureIsoSlider->Bind(wxEVT_SLIDER, &IosControlsPanel::OnExposureChanged, this);
    grid->Add(exposureIsoSlider, 1, wxEXPAND);
    exposureIsoLabel = new wxStaticText(this, wxID_ANY, "ISO 100", wxDefaultPosition, wxSize(80, -1), wxALIGN_RIGHT);
    grid->Add(exposureIsoLabel, 0, wxALIGN_CENTER_VERTICAL);

    grid->Add(new wxStaticText(this, wxID_ANY, "EV:"), 0, wxALIGN_CENTER_VERTICAL);
    exposureCompSlider = new wxSlider(this, wxID_ANY, 0, kCompMin, kCompMax);
    exposureCompSlider->Bind(wxEVT_SLIDER, &IosControlsPanel::OnExposureChanged, this);
    grid->Add(exposureCompSlider, 1, wxEXPAND);
    exposureCompLabel = new wxStaticText(this, wxID_ANY, "+0.00 EV", wxDefaultPosition, wxSize(80, -1), wxALIGN_RIGHT);
    grid->Add(exposureCompLabel, 0, wxALIGN_CENTER_VERTICAL);

    parent->Add(grid, 0, wxEXPAND);
}

void IosControlsPanel::BuildWhiteBalanceSection(wxBoxSizer* parent)
{
    auto* header = new wxBoxSizer(wxHORIZONTAL);
    header->Add(new wxStaticText(this, wxID_ANY, "White balance"), 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 10);

    whiteBalanceModeChoice = new wxChoice(this, wxID_ANY);
    whiteBalanceModeChoice->Append("Auto");
    whiteBalanceModeChoice->Append("Manual");
    whiteBalanceModeChoice->SetSelection(0);
    whiteBalanceModeChoice->Bind(wxEVT_CHOICE, &IosControlsPanel::OnWhiteBalanceChanged, this);
    header->Add(whiteBalanceModeChoice, 0);
    parent->Add(header, 0, wxBOTTOM, 5);

    auto* grid = new wxFlexGridSizer(2, 3, 5, 8);
    grid->AddGrowableCol(1, 1);

    grid->Add(new wxStaticText(this, wxID_ANY, "Temp:"), 0, wxALIGN_CENTER_VERTICAL);
    whiteBalanceTempSlider = new wxSlider(this, wxID_ANY, 5500, kTempMin, kTempMax);
    whiteBalanceTempSlider->Bind(wxEVT_SLIDER, &IosControlsPanel::OnWhiteBalanceChanged, this);
    grid->Add(whiteBalanceTempSlider, 1, wxEXPAND);
    whiteBalanceTempLabel = new wxStaticText(this, wxID_ANY, "5500K", wxDefaultPosition, wxSize(80, -1), wxALIGN_RIGHT);
    grid->Add(whiteBalanceTempLabel, 0, wxALIGN_CENTER_VERTICAL);

    grid->Add(new wxStaticText(this, wxID_ANY, "Tint:"), 0, wxALIGN_CENTER_VERTICAL);
    whiteBalanceTintSlider = new wxSlider(this, wxID_ANY, 0, kTintMin, kTintMax);
    whiteBalanceTintSlider->Bind(wxEVT_SLIDER, &IosControlsPanel::OnWhiteBalanceChanged, this);
    grid->Add(whiteBalanceTintSlider, 1, wxEXPAND);
    whiteBalanceTintLabel = new wxStaticText(this, wxID_ANY, "+0", wxDefaultPosition, wxSize(80, -1), wxALIGN_RIGHT);
    grid->Add(whiteBalanceTintLabel, 0, wxALIGN_CENTER_VERTICAL);

    parent->Add(grid, 0, wxEXPAND);
}

void IosControlsPanel::BuildFocusSection(wxBoxSizer* parent)
{
    auto* row = new wxBoxSizer(wxHORIZONTAL);
    focusLockCheck = new wxCheckBox(this, wxID_ANY, "Lock focus");
    focusLockCheck->Bind(wxEVT_CHECKBOX, &IosControlsPanel::OnFocusChanged, this);
    row->Add(focusLockCheck, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 10);

    focusLockSlider = new wxSlider(this, wxID_ANY, 50, kFocusMin, kFocusMax);
    focusLockSlider->Bind(wxEVT_SLIDER, &IosControlsPanel::OnFocusChanged, this);
    row->Add(focusLockSlider, 1, wxEXPAND | wxRIGHT, 5);

    focusLockLabel = new wxStaticText(this, wxID_ANY, "0.50", wxDefaultPosition, wxSize(80, -1), wxALIGN_RIGHT);
    row->Add(focusLockLabel, 0, wxALIGN_CENTER_VERTICAL);

    parent->Add(row, 0, wxEXPAND);
}

void IosControlsPanel::BuildStabilizationSection(wxBoxSizer* parent)
{
    auto* row = new wxBoxSizer(wxHORIZONTAL);
    row->Add(new wxStaticText(this, wxID_ANY, "Stabilization mode:"), 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 10);

    stabilizationChoice = new wxChoice(this, wxID_ANY);
    stabilizationChoice->Append("Off");
    stabilizationChoice->Append("Standard");
    stabilizationChoice->Append("Cinematic");
    stabilizationChoice->Append("Cinematic Extended");
    stabilizationChoice->SetSelection(1);
    stabilizationChoice->Bind(wxEVT_CHOICE, &IosControlsPanel::OnStabilizationChanged, this);
    row->Add(stabilizationChoice, 1);

    parent->Add(row, 0, wxEXPAND);
}

void IosControlsPanel::BuildResetSection(wxBoxSizer* parent)
{
    auto* row = new wxBoxSizer(wxHORIZONTAL);

    studioModeCheck = new wxCheckBox(this, wxID_ANY, "Studio mode (dim phone screen)");
    studioModeCheck->Bind(wxEVT_CHECKBOX, [this](wxCommandEvent&) {
        wxCommandEvent ev(EVT_IOS_STUDIO_MODE_CHANGED);
        ev.SetEventObject(this);
        ProcessWindowEvent(ev);
    });
    row->Add(studioModeCheck, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 20);

    resetButton = new wxButton(this, wxID_ANY, "Reset to Auto");
    resetButton->Bind(wxEVT_BUTTON, &IosControlsPanel::OnReset, this);
    row->Add(resetButton, 0);
    parent->Add(row, 0, wxALIGN_LEFT);
}

void IosControlsPanel::RefreshExposureUI()
{
    const bool manual = IsManualExposure();
    exposureDurationSlider->Enable(manual);
    exposureIsoSlider->Enable(manual);
    // EV comp is independently useful in auto mode as well.
}

void IosControlsPanel::RefreshWhiteBalanceUI()
{
    const bool manual = IsManualWhiteBalance();
    whiteBalanceTempSlider->Enable(manual);
    whiteBalanceTintSlider->Enable(manual);
}

void IosControlsPanel::RefreshFocusUI()
{
    focusLockSlider->Enable(focusLockCheck->GetValue());
}

void IosControlsPanel::OnLensSlider(wxCommandEvent& /*event*/)
{
    lensLabel->SetLabel(wxString::Format("%.1fx", GetLensZoom()));
    wxCommandEvent ev(EVT_IOS_LENS_ZOOM_CHANGED);
    ev.SetEventObject(this);
    ProcessWindowEvent(ev);
}

void IosControlsPanel::OnExposureChanged(wxCommandEvent& /*event*/)
{
    exposureDurationLabel->SetLabel(FormatShutter(GetExposureDurationSeconds()));
    exposureIsoLabel->SetLabel(wxString::Format("ISO %d", static_cast<int>(GetExposureISO())));
    exposureCompLabel->SetLabel(wxString::Format("%+.2f EV", GetExposureCompensation()));
    RefreshExposureUI();
    wxCommandEvent ev(EVT_IOS_EXPOSURE_CHANGED);
    ev.SetEventObject(this);
    ProcessWindowEvent(ev);
}

void IosControlsPanel::OnWhiteBalanceChanged(wxCommandEvent& /*event*/)
{
    whiteBalanceTempLabel->SetLabel(wxString::Format("%dK", static_cast<int>(GetWhiteBalanceTemperatureK())));
    whiteBalanceTintLabel->SetLabel(wxString::Format("%+d", static_cast<int>(GetWhiteBalanceTint())));
    RefreshWhiteBalanceUI();
    wxCommandEvent ev(EVT_IOS_WHITE_BALANCE_CHANGED);
    ev.SetEventObject(this);
    ProcessWindowEvent(ev);
}

void IosControlsPanel::OnFocusChanged(wxCommandEvent& /*event*/)
{
    focusLockLabel->SetLabel(wxString::Format("%.2f", GetFocusLockPosition() < 0 ? 0.0f : GetFocusLockPosition()));
    RefreshFocusUI();
    wxCommandEvent ev(EVT_IOS_FOCUS_LOCK_CHANGED);
    ev.SetEventObject(this);
    ProcessWindowEvent(ev);
}

void IosControlsPanel::OnStabilizationChanged(wxCommandEvent& /*event*/)
{
    wxCommandEvent ev(EVT_IOS_STABILIZATION_MODE_CHANGED);
    ev.SetEventObject(this);
    ProcessWindowEvent(ev);
}

void IosControlsPanel::OnReset(wxCommandEvent& /*event*/)
{
    exposureModeChoice->SetSelection(0);
    whiteBalanceModeChoice->SetSelection(0);
    focusLockCheck->SetValue(false);
    RefreshExposureUI();
    RefreshWhiteBalanceUI();
    RefreshFocusUI();

    wxCommandEvent ev(EVT_IOS_RESET_AUTO);
    ev.SetEventObject(this);
    ProcessWindowEvent(ev);
}

// ---- Getters ----

float IosControlsPanel::GetLensZoom() const
{
    return static_cast<float>(lensSlider->GetValue()) / kLensSliderScale;
}

bool IosControlsPanel::IsManualExposure() const
{
    return exposureModeChoice->GetSelection() == 1;
}

float IosControlsPanel::GetExposureDurationSeconds() const
{
    int idx = exposureDurationSlider->GetValue();
    idx = std::max(0, std::min(kShutterTableSize - 1, idx));
    return kShutterTable[idx];
}

float IosControlsPanel::GetExposureISO() const
{
    return static_cast<float>(exposureIsoSlider->GetValue());
}

float IosControlsPanel::GetExposureCompensation() const
{
    return static_cast<float>(exposureCompSlider->GetValue()) / kCompScale;
}

bool IosControlsPanel::IsManualWhiteBalance() const
{
    return whiteBalanceModeChoice->GetSelection() == 1;
}

float IosControlsPanel::GetWhiteBalanceTemperatureK() const
{
    return static_cast<float>(whiteBalanceTempSlider->GetValue());
}

float IosControlsPanel::GetWhiteBalanceTint() const
{
    return static_cast<float>(whiteBalanceTintSlider->GetValue());
}

int IosControlsPanel::GetStabilizationMode() const
{
    return stabilizationChoice->GetSelection();
}

bool IosControlsPanel::IsFocusLocked() const
{
    return focusLockCheck->GetValue();
}

float IosControlsPanel::GetFocusLockPosition() const
{
    if (!focusLockCheck->GetValue()) return -1.0f;
    return static_cast<float>(focusLockSlider->GetValue()) / kFocusScale;
}

bool IosControlsPanel::IsStudioModeEnabled() const
{
    return studioModeCheck && studioModeCheck->GetValue();
}
