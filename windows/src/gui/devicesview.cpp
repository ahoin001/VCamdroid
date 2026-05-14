#include "gui/devicesview.h"
#include <wx/listctrl.h>
#include <algorithm>

DevicesView::DevicesView(wxWindow* parent,
                         const std::vector<DeviceDescriptor>& connectedDevices,
                         const std::map<std::string, Discovery::RawDiscoveryRecord>& discoveredDevices)
    : wxDialog(parent, wxID_ANY, "Devices", wxDefaultPosition, wxSize(650, 350))
{
    auto sizer = new wxBoxSizer(wxVERTICAL);

    auto list = new wxListView(this, wxID_ANY, wxDefaultPosition, wxDefaultSize, wxLC_REPORT | wxLC_SINGLE_SEL);

    list->AppendColumn("#", wxLIST_FORMAT_LEFT, 30);
    list->AppendColumn("Model Name", wxLIST_FORMAT_LEFT, 150);
    list->AppendColumn("Address", wxLIST_FORMAT_LEFT, 180);
    list->AppendColumn("Status", wxLIST_FORMAT_LEFT, 90);
    list->AppendColumn("Max Back", wxLIST_FORMAT_LEFT, 90);
    list->AppendColumn("Max Front", wxLIST_FORMAT_LEFT, 90);

    auto getMaxResString = [](const std::vector<DeviceDescriptor::Resolution>& resList) -> std::string {
        if (resList.empty()) return "-";
        auto maxRes = *std::max_element(resList.begin(), resList.end(),
            [](const DeviceDescriptor::Resolution& a, const DeviceDescriptor::Resolution& b) {
                return (a.first * a.second) < (b.first * b.second);
            });
        return std::to_string(maxRes.first) + "x" + std::to_string(maxRes.second);
    };

    int row = 0;

    // Connected devices.
    for (size_t i = 0; i < connectedDevices.size(); i++)
    {
        const auto& dev = connectedDevices[i];
        long index = list->InsertItem(row, std::to_string(row + 1));

        list->SetItem(index, 1, dev.name());
        list->SetItem(index, 2, dev.url());
        list->SetItem(index, 3, "Connected");
        list->SetItem(index, 4, getMaxResString(dev.backResolutions()));
        list->SetItem(index, 5, getMaxResString(dev.frontResolutions()));
        row++;
    }

    // Discovered-but-not-connected iOS devices.
    for (const auto& [name, rec] : discoveredDevices)
    {
        bool alreadyConnected = false;
        for (const auto& dev : connectedDevices)
        {
            if (dev.name() == name) { alreadyConnected = true; break; }
        }
        if (alreadyConnected) continue;

        long index = list->InsertItem(row, std::to_string(row + 1));
        list->SetItem(index, 1, rec.instanceName);
        list->SetItem(index, 2, rec.host + ":" + std::to_string(rec.controlPort));
        list->SetItem(index, 3, "Discovered");
        list->SetItem(index, 4, "-");
        list->SetItem(index, 5, "-");
        row++;
    }

    sizer->Add(list, 1, wxEXPAND | wxALL, 10);

    auto btnSizer = new wxBoxSizer(wxHORIZONTAL);
    auto closeBtn = new wxButton(this, wxID_OK, "Close");
    btnSizer->Add(closeBtn, 0);
    sizer->Add(btnSizer, 0, wxALIGN_RIGHT | wxALL, 10);

    this->SetSizer(sizer);
    this->CenterOnParent();
}
