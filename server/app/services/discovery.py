import asyncio
import logging
import ipaddress
import socket
from contextlib import suppress
from typing import Any

from app.core.config import Settings

logger = logging.getLogger(__name__)


class MdnsAdvertiser:
    """Advertise the server over mDNS.

    ``start``/``stop`` are non-blocking: the underlying zeroconf operations
    (which open sockets and wait for network events) run on a worker thread
    so they never stall the event loop or application startup/shutdown.
    Direct synchronous registration is still available via ``start_blocking``
    for tests and embedded use.
    """

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._zeroconf: Any | None = None
        self._service_info: Any | None = None
        self._task: asyncio.Task | None = None

    def start(self) -> None:
        if not self.settings.enable_mdns:
            logger.info("mDNS advertising disabled")
            return
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            # No event loop running – fall back to a blocking registration.
            self.start_blocking()
            return
        self._task = loop.create_task(asyncio.to_thread(self.start_blocking))

    def start_blocking(self) -> None:
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
            self.stop_blocking()
            return

        logger.info(
            "Advertising %s on %s:%s",
            self.settings.service_type,
            host_ip,
            self.settings.port,
        )

    def stop(self) -> None:
        if self._task is not None:
            if self._task.done():
                self._task = None
            else:
                # Registration is still in flight; cancel it instead of
                # blocking shutdown waiting on an unusable network.
                self._task.cancel()
                self._task = None
        self.stop_blocking()

    def stop_blocking(self) -> None:
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
