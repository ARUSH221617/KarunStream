class FileTransfer {
  const FileTransfer({
    required this.transferId,
    required this.senderId,
    required this.recipientId,
    required this.fileName,
    required this.bytes,
    required this.sha256,
    required this.downloadUrl,
    required this.createdAt,
    required this.durationSeconds,
    this.storedPath,
  });

  final String transferId;
  final String senderId;
  final String recipientId;
  final String fileName;
  final int bytes;
  final String sha256;
  final String? storedPath;
  final String downloadUrl;
  final DateTime createdAt;
  final double durationSeconds;

  factory FileTransfer.fromJson(Map<String, dynamic> json) {
    return FileTransfer(
      transferId: json['transfer_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      recipientId: json['recipient_id'] as String? ?? '',
      fileName: json['file_name'] as String? ?? '',
      bytes: json['bytes'] as int? ?? 0,
      sha256: json['sha256'] as String? ?? '',
      storedPath: json['stored_path'] as String?,
      downloadUrl: json['download_url'] as String? ?? '',
      createdAt: _parseTimestamp(json['created_at']),
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transfer_id': transferId,
      'sender_id': senderId,
      'recipient_id': recipientId,
      'file_name': fileName,
      'bytes': bytes,
      'sha256': sha256,
      if (storedPath != null) 'stored_path': storedPath,
      'download_url': downloadUrl,
      'created_at': createdAt.millisecondsSinceEpoch / 1000,
      'duration_seconds': durationSeconds,
    };
  }
}

DateTime _parseTimestamp(Object? timestamp) {
  final seconds = timestamp is num ? timestamp : 0;
  return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
}
