class FileOffer {
  const FileOffer({
    required this.transferId,
    required this.senderId,
    required this.fileName,
    required this.fileSize,
    required this.sha256,
    this.receiverId,
    this.chunkSize,
  });

  final String transferId;
  final String senderId;
  final String? receiverId;
  final String fileName;
  final int fileSize;
  final String sha256;
  final int? chunkSize;

  factory FileOffer.fromJson(Map<String, dynamic> json) {
    return FileOffer(
      transferId: json['transfer_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      receiverId: json['receiver_id'] as String?,
      fileName: json['file_name'] as String? ?? '',
      fileSize: json['file_size'] as int? ?? 0,
      sha256: json['sha256'] as String? ?? '',
      chunkSize: json['chunk_size'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transfer_id': transferId,
      'sender_id': senderId,
      if (receiverId != null) 'receiver_id': receiverId,
      'file_name': fileName,
      'file_size': fileSize,
      'sha256': sha256,
      if (chunkSize != null) 'chunk_size': chunkSize,
    };
  }
}
