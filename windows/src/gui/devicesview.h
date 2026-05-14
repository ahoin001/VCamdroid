#pragma once

#include <wx/wx.h>
#include <vector>
#include "net/devicedescriptor.h"
#include "discovery/mdnsdiscovery.h"

class DevicesView : public wxDialog
{
public:
    DevicesView(wxWindow* parent,
                const std::vector<DeviceDescriptor>& connectedDevices,
                const std::map<std::string, Discovery::RawDiscoveryRecord>& discoveredDevices = {});
};
