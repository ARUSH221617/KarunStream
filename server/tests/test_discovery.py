from unittest.mock import MagicMock, patch
from app.core.config import Settings
from app.services.discovery import MdnsAdvertiser, _get_lan_ip


def test_mdns_advertiser_disabled() -> None:
    settings = Settings(enable_mdns=False)
    advertiser = MdnsAdvertiser(settings)

    with patch("zeroconf.Zeroconf") as mock_zeroconf:
        advertiser.start()
        mock_zeroconf.assert_not_called()
        assert advertiser._zeroconf is None


def test_mdns_advertiser_start_stop() -> None:
    settings = Settings(
        enable_mdns=True,
        server_name="TestServer",
        service_type="_karunstream._tcp.local.",
        port=8080,
        advertised_ip="192.168.1.100",
    )
    advertiser = MdnsAdvertiser(settings)

    with patch("zeroconf.Zeroconf") as mock_zeroconf_class, \
         patch("zeroconf.ServiceInfo") as mock_service_info_class:

        mock_zeroconf = MagicMock()
        mock_zeroconf_class.return_value = mock_zeroconf

        mock_service_info = MagicMock()
        mock_service_info_class.return_value = mock_service_info

        advertiser.start()

        # Verify ServiceInfo was initialized with correct attributes
        mock_service_info_class.assert_called_once()
        kwargs = mock_service_info_class.call_args[1]
        assert kwargs["type_"] == "_karunstream._tcp.local."
        assert kwargs["name"] == "TestServer._karunstream._tcp.local."
        assert kwargs["port"] == 8080
        assert kwargs["properties"]["v"] == "1.0"
        assert kwargs["properties"]["role"] == "host"
        assert kwargs["properties"]["port"] == "8080"
        assert kwargs["properties"]["caps"] == "resume,chunk_manifest,folders,tus_upload"
        assert kwargs["properties"]["tls"] == ""
        assert kwargs["properties"]["server_name"] == "TestServer"
        assert kwargs["properties"]["api"] == "http://192.168.1.100:8080"
        assert kwargs["properties"]["ws"] == "ws://192.168.1.100:8080/ws/orchestrator"

        # Verify Zeroconf was initialized and registered service
        mock_zeroconf_class.assert_called_once()
        mock_zeroconf.register_service.assert_called_once_with(mock_service_info)

        assert advertiser._zeroconf == mock_zeroconf
        assert advertiser._service_info == mock_service_info

        # Now stop
        advertiser.stop()
        mock_zeroconf.unregister_service.assert_called_once_with(mock_service_info)
        mock_zeroconf.close.assert_called_once()


def test_mdns_advertiser_properties_with_tls_fingerprint() -> None:
    fingerprint = "d" * 64
    settings = Settings(
        enable_mdns=True,
        server_name="SecureServer",
        service_type="_karunstream._tcp.local.",
        port=8443,
        advertised_ip="192.168.1.50",
        tls_fingerprint=fingerprint,
    )
    advertiser = MdnsAdvertiser(settings)

    with patch("zeroconf.Zeroconf") as mock_zeroconf_class, \
         patch("zeroconf.ServiceInfo") as mock_service_info_class:

        mock_zeroconf = MagicMock()
        mock_zeroconf_class.return_value = mock_zeroconf
        mock_service_info = MagicMock()
        mock_service_info_class.return_value = mock_service_info

        advertiser.start()

        kwargs = mock_service_info_class.call_args[1]
        props = kwargs["properties"]
        assert props["v"] == "1.0"
        assert props["role"] == "host"
        assert props["port"] == "8443"
        assert props["caps"] == "resume,chunk_manifest,folders,tus_upload"
        assert props["tls"] == fingerprint
        assert props["server_name"] == "SecureServer"
        assert props["api"] == "http://192.168.1.50:8443"
        assert props["ws"] == "ws://192.168.1.50:8443/ws/orchestrator"

        advertiser.stop()


def test_get_lan_ip() -> None:
    with patch("socket.socket") as mock_socket_class:
        mock_socket = MagicMock()
        mock_socket_class.return_value.__enter__.return_value = mock_socket
        mock_socket.getsockname.return_value = ("192.168.1.50", 12345)

        ip = _get_lan_ip()
        assert ip == "192.168.1.50"
        mock_socket.connect.assert_called_once()
