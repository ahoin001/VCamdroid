#pragma once

#include <tuple>
#include <thread>
#include <asio.hpp>
#include <string>
#include <memory>

#include "connection.h"
#include "net/devicebridge.h"

class Server : std::enable_shared_from_this<Server>
{
public:
	using tcp = asio::ip::tcp;
	using udp = asio::ip::udp;
	using HostInfo = std::tuple<std::string, std::string, std::string>;

	struct ConnectionListener
	{
		virtual void OnDeviceConnected(DeviceDescriptor& descriptor) const = 0;
		virtual void OnDeviceDisconnected(DeviceDescriptor& descriptor) const = 0;
		virtual void OnDeviceErrorReported(DeviceDescriptor& descriptor, const Connection::ErrorReport& error) const = 0;
	};

	struct DeviceInfo
	{
		std::string name;
		std::string address;
		unsigned short port;
	};

	/// Constructs the server with an optional device bridge. When a bridge
	/// is provided, port forwarding is delegated to it instead of using
	/// raw adb:: calls. Pass nullptr for no bridge (iOS Wi-Fi path).
	Server(int port, const ConnectionListener& connectionListener,
	       IDeviceBridge* bridge = nullptr);

	/// Gets host device's info (name, IPv4 address and port)
	HostInfo GetHostInfo();

	void Send(int id, const unsigned char* bytes, size_t size) const;
	void Start();
	void Close();

private:
	int port;

	const ConnectionListener& connectionListener;
	IDeviceBridge* bridge = nullptr;

	asio::io_context context;

	tcp::acceptor acceptor;
	udp::endpoint remote_endpoint;

	std::thread thread;

	std::vector<std::shared_ptr<Connection>> connections;

	void TCPDoAccept();
	void OnConnectionDisconnected(std::shared_ptr<Connection> connection);
	void OnConnectionReportingError(std::shared_ptr<Connection> connection, const uint8_t* bytes, size_t size);
};
