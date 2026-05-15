#include "gui/cameradockpanel.h"

#include <wx/statline.h>

CameraDockPanel::CameraDockPanel(wxWindow* parent)
    : wxPanel(parent, wxID_ANY)
{
    auto* root = new wxBoxSizer(wxVERTICAL);
    auto* label = new wxStaticText(this, wxID_ANY, "Camera controls");
    wxFont f = label->GetFont();
    f.SetWeight(wxFONTWEIGHT_BOLD);
    label->SetFont(f);
    root->Add(label, 0, wxLEFT | wxRIGHT | wxTOP, 8);

    root->Add(new wxStaticLine(this), 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP, 8);

    placeholderLabel = new wxStaticText(
        this, wxID_ANY,
        "Connect an iPhone stream to adjust Portrait Mode, exposure, and white balance.");
    placeholderLabel->Wrap(360);
    root->Add(placeholderLabel, 0, wxALL, 10);

    StreamOptions defaults;
    iosPanel = new IosControlsPanel(this, defaults);
    iosPanel->Hide();
    root->Add(iosPanel, 1, wxEXPAND | wxALL, 4);

    SetSizer(root);
    Hide();
}

void CameraDockPanel::SetVisibleForPlatform(bool isIos, bool streaming)
{
    const bool show = isIos && streaming;
    Show(show);
    if (!show)
        return;

    placeholderLabel->Hide();
    iosPanel->Show();
    if (GetParent())
        GetParent()->Layout();
}

void CameraDockPanel::LoadState(const StreamOptions& state)
{
    (void)state;
}
