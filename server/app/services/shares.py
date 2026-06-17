from app.models import SharedFolderRecord


class SharedFolderRegistry:
    def __init__(self) -> None:
        self._shares: dict[str, SharedFolderRecord] = {}

    def add(self, record: SharedFolderRecord) -> SharedFolderRecord:
        self._shares[record.share_id] = record
        return record

    def remove(self, share_id: str) -> SharedFolderRecord | None:
        return self._shares.pop(share_id, None)

    def remove_by_peer(self, peer_id: str) -> list[str]:
        removed_ids: list[str] = []
        for share_id, record in list(self._shares.items()):
            if record.peer_id == peer_id:
                self._shares.pop(share_id)
                removed_ids.append(share_id)
        return removed_ids

    def get(self, share_id: str) -> SharedFolderRecord | None:
        return self._shares.get(share_id)

    def list_shares(self) -> list[SharedFolderRecord]:
        return list(self._shares.values())


share_registry = SharedFolderRegistry()
