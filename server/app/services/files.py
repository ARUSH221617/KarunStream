from pathlib import Path

from app.models import FileTransferRecord


class FileTransferRegistry:
    def __init__(self) -> None:
        self._records: dict[str, FileTransferRecord] = {}

    def add(self, record: FileTransferRecord) -> FileTransferRecord:
        self._records[record.transfer_id] = record
        return record

    def get(self, transfer_id: str) -> FileTransferRecord | None:
        return self._records.get(transfer_id)

    def remove(self, transfer_id: str) -> FileTransferRecord | None:
        return self._records.pop(transfer_id, None)

    def list_for_peer(self, peer_id: str | None = None) -> list[FileTransferRecord]:
        records = sorted(
            self._records.values(),
            key=lambda record: record.created_at,
            reverse=True,
        )
        if peer_id is None:
            return records
        return [
            record
            for record in records
            if record.sender_id == peer_id or record.recipient_id == peer_id
        ]

    def remove_missing(self) -> None:
        missing_ids = [
            transfer_id
            for transfer_id, record in self._records.items()
            if not Path(record.stored_path).is_file()
        ]
        for transfer_id in missing_ids:
            self._records.pop(transfer_id, None)

    def clear(self) -> None:
        self._records.clear()


file_registry = FileTransferRegistry()
