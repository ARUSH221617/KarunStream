import logging
import ipaddress
import socket
from contextlib import suppress
from typing import Any

from app.core.config import Settings

logger = logging.getLogger(__name__)


class MdnsAdvertiser:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._zeroconf: Any | None = None
        self._service_info: Any | None = None

    def start(self) -> None:
        if not self.settings.enable_mdns:
            logger.info("mDNS advertising disabled")
            return

        try:
            from zeroconf import IPVersion, ServiceInfo, Zeroconf
        except ImportError:
            logger.warning("zeroconf is not installed; mDNS advertising unavailable")
            return

        host_ip = self.settings.advertised_ip or _get_lan_ip()
        properties = {
            "server_name": self.settings.server_name,
            "api": f"http://{host_ip}:{self.settings.port}",
            "ws": f"ws://{host_ip}:{self.settings.port}/ws/orchestrator",
        }
        self._service_info = ServiceInfo(
            type_=self.settings.service_type,
            name=f"{self.settings.server_name}.{self.settings.service_type}",
            addresses=[socket.inet_aton(host_ip)],
            port=self.settings.port,
            properties=properties,
            server=f"karunstream-{socket.gethostname()}.local.",
        )
        try:
            self._zeroconf = Zeroconf(ip_version=IPVersion.V4Only)
            self._zeroconf.register_service(self._service_info)
        except Exception as exc:
            logger.warning(
                "mDNS advertising unavailable on this network/container: %s",
                exc.__class__.__name__,
            )
            self.stop()
            return

        logger.info(
            "Advertising %s on %s:%s",
            self.settings.service_type,
            host_ip,
            self.settings.port,
        )

    def stop(self) -> None:
        if self._zeroconf and self._service_info:
            with suppress(Exception):
                self._zeroconf.unregister_service(self._service_info)
            self._zeroconf.close()
            logger.info("mDNS advertising stopped")


def _get_lan_ip() -> str:
    nameservers = _local_nameservers()
    target = nameservers[0] if nameservers else "192.168.1.1"
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        with suppress(OSError):
            probe.connect((target, 80))
            return probe.getsockname()[0]
    return "127.0.0.1"


def _local_nameservers() -> list[str]:
    nameservers: list[str] = []
    with suppress(OSError), open("/etc/resolv.conf", encoding="utf-8") as resolv_conf:
        for line in resolv_conf:
            parts = line.strip().split()
            if len(parts) == 2 and parts[0] == "nameserver":
                with suppress(ValueError):
                    ip = ipaddress.ip_address(parts[1])
                    if ip.version == 4 and not ip.is_loopback:
                        nameservers.append(parts[1])
    return nameservers
