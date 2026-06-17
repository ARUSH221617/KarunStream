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
        advertised_ip="192.168.1.100"
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
        assert kwargs["properties"]["server_name"] == "TestServer"
        assert kwargs["properties"]["api"] == "http://192.168.1.100:8080"
        
        # Verify Zeroconf was initialized and registered service
        mock_zeroconf_class.assert_called_once()
        mock_zeroconf.register_service.assert_called_once_with(mock_service_info)
        
        assert advertiser._zeroconf == mock_zeroconf
        assert advertiser._service_info == mock_service_info
        
        # Now stop
        advertiser.stop()
        mock_zeroconf.unregister_service.assert_called_once_with(mock_service_info)
        mock_zeroconf.close.assert_called_once()

def test_get_lan_ip() -> None:
    with patch("socket.socket") as mock_socket_class:
        mock_socket = MagicMock()
        mock_socket_class.return_value.__enter__.return_value = mock_socket
        mock_socket.getsockname.return_value = ("192.168.1.50", 12345)
        
        ip = _get_lan_ip()
        assert ip == "192.168.1.50"
        mock_socket.connect.assert_called_once()
