#pragma once

#include <wx/wx.h>

#include "gui/window.h"
#include "net/server.h"
#include "rtsp/manager.h"
#include "directshowsource.h"
#include "rtsp/streamoptions.h"
#include "snapshotmanager.h"
#include "discovery/mdnsdiscovery.h"
#include "net/adbbridge.h"
#include "net/usbmuxbridge.h"

class Application : public wxApp, public Server::ConnectionListener
{
public:
	Application();

	virtual bool OnInit();
	
	virtual void OnDeviceConnected(DeviceDescriptor& descriptor) const override;
	virtual void OnDeviceDisconnected(DeviceDescriptor& descriptor) const override;
	virtual void OnDeviceErrorReported(DeviceDescriptor& descriptor, const Connection::ErrorReport& error) const override;

private:
	Window* mainWindow = nullptr;

	StreamOptions::Registry stateRegistry;

	std::unique_ptr<Server> server;
	std::unique_ptr<RTSP::Manager> rtspManager;
	std::unique_ptr<DirectShowSource> dsSource;
	SnapshotManager snapshotManager;

	// Device bridges for USB port forwarding.
	AdbBridge adbBridge;
	UsbmuxBridge usbmuxBridge;

	// mDNS auto-discovery for iOS devices on the LAN.
	std::unique_ptr<Discovery::MdnsBrowser> mdnsBrowser;
	mutable std::mutex discoveredDevicesMutex;
	mutable std::map<std::string, Discovery::RawDiscoveryRecord> discoveredDevices;

	StreamOptions& GetCurrentDeviceStreamOptions();
	void BindEventListeners();

	void UpdateAvailableDevices() const;
	void OnDiscoveredDeviceSelected(const Discovery::RawDiscoveryRecord& record);

	void OnSourceChanged(wxEvent& event);

	void ShowAdjustmentsDialog(wxCommandEvent& event);
	void ShowStreamConfigDialog(wxCommandEvent& event);
	
	void OnMenuEvent(wxCommandEvent& event);
	void OnWindowCloseEvent(wxCloseEvent& event);

	void EnsureStateInitialized(std::string name, const DeviceDescriptor& descriptor);
};