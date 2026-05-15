#pragma once

#include <wx/wx.h>

#include "gui/ioscontrolspanel.h"
#include "rtsp/streamoptions.h"

/// Always-visible dock for iOS camera controls (portrait, exposure, WB).
class CameraDockPanel : public wxPanel
{
public:
    CameraDockPanel(wxWindow* parent);

    void SetVisibleForPlatform(bool isIos, bool streaming);
    void LoadState(const StreamOptions& state);
    IosControlsPanel* GetIosPanel() { return iosPanel; }

private:
    IosControlsPanel* iosPanel = nullptr;
    wxStaticText* placeholderLabel = nullptr;
};
