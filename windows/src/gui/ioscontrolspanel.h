#pragma once

#include <wx/wx.h>
#include <wx/spinctrl.h>

#include "rtsp/streamoptions.h"

wxDECLARE_EVENT(EVT_IOS_LENS_ZOOM_CHANGED, wxCommandEvent);
wxDECLARE_EVENT(EVT_IOS_EXPOSURE_CHANGED, wxCommandEvent);
wxDECLARE_EVENT(EVT_IOS_WHITE_BALANCE_CHANGED, wxCommandEvent);
wxDECLARE_EVENT(EVT_IOS_STABILIZATION_MODE_CHANGED, wxCommandEvent);
wxDECLARE_EVENT(EVT_IOS_FOCUS_LOCK_CHANGED, wxCommandEvent);
wxDECLARE_EVENT(EVT_IOS_RESET_AUTO, wxCommandEvent);
wxDECLARE_EVENT(EVT_IOS_STUDIO_MODE_CHANGED, wxCommandEvent);

/*
    Premium iOS camera control panel. Renders the continuous lens zoom slider,
    exposure (duration/ISO/comp), white balance (temperature/tint), focus
    lock, and stabilization mode. Hidden for Android devices.

    The panel exposes typed getters so the host dialog can read the current
    values when it forwards events to RTSP::Manager. All events bubble up as
    wxCommandEvent for parity with the rest of the dialog stack.
*/
class IosControlsPanel : public wxPanel
{
public:
    IosControlsPanel(wxWindow* parent, const StreamOptions& initial);

    float GetLensZoom() const;

    bool IsManualExposure() const;
    float GetExposureDurationSeconds() const;
    float GetExposureISO() const;
    float GetExposureCompensation() const;

    bool IsManualWhiteBalance() const;
    float GetWhiteBalanceTemperatureK() const;
    float GetWhiteBalanceTint() const;

    int GetStabilizationMode() const;

    bool IsFocusLocked() const;
    float GetFocusLockPosition() const;

    bool IsStudioModeEnabled() const;

private:
    void BuildLensSection(wxBoxSizer* parent);
    void BuildExposureSection(wxBoxSizer* parent);
    void BuildWhiteBalanceSection(wxBoxSizer* parent);
    void BuildFocusSection(wxBoxSizer* parent);
    void BuildStabilizationSection(wxBoxSizer* parent);
    void BuildResetSection(wxBoxSizer* parent);

    void RefreshExposureUI();
    void RefreshWhiteBalanceUI();
    void RefreshFocusUI();

    void OnLensSlider(wxCommandEvent& event);
    void OnExposureChanged(wxCommandEvent& event);
    void OnWhiteBalanceChanged(wxCommandEvent& event);
    void OnFocusChanged(wxCommandEvent& event);
    void OnStabilizationChanged(wxCommandEvent& event);
    void OnReset(wxCommandEvent& event);

    // Lens
    wxSlider* lensSlider = nullptr;
    wxStaticText* lensLabel = nullptr;

    // Exposure
    wxChoice* exposureModeChoice = nullptr;
    wxSlider* exposureDurationSlider = nullptr;
    wxStaticText* exposureDurationLabel = nullptr;
    wxSlider* exposureIsoSlider = nullptr;
    wxStaticText* exposureIsoLabel = nullptr;
    wxSlider* exposureCompSlider = nullptr;
    wxStaticText* exposureCompLabel = nullptr;

    // White balance
    wxChoice* whiteBalanceModeChoice = nullptr;
    wxSlider* whiteBalanceTempSlider = nullptr;
    wxStaticText* whiteBalanceTempLabel = nullptr;
    wxSlider* whiteBalanceTintSlider = nullptr;
    wxStaticText* whiteBalanceTintLabel = nullptr;

    // Focus
    wxCheckBox* focusLockCheck = nullptr;
    wxSlider* focusLockSlider = nullptr;
    wxStaticText* focusLockLabel = nullptr;

    // Stabilization
    wxChoice* stabilizationChoice = nullptr;

    // Studio mode
    wxCheckBox* studioModeCheck = nullptr;

    // Reset
    wxButton* resetButton = nullptr;
};
