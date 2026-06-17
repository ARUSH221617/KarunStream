class SharedFolderFile {
  const SharedFolderFile({
    required this.relativePath,
    required this.fileName,
    required this.fileSize,
  });

  final String relativePath;
  final String fileName;
  final int fileSize;

  factory SharedFolderFile.fromJson(Map<String, dynamic> json) {
    return SharedFolderFile(
      relativePath: json['relative_path'] as String? ?? '',
      fileName: json['file_name'] as String? ?? '',
      fileSize: json['file_size'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'relative_path': relativePath,
      'file_name': fileName,
      'file_size': fileSize,
    };
  }
}

class SharedFolder {
  const SharedFolder({
    required this.shareId,
    required this.peerId,
    required this.peerNickname,
    required this.name,
    required this.files,
  });

  final String shareId;
  final String peerId;
  final String peerNickname;
  final String name;
  final List<SharedFolderFile> files;

  factory SharedFolder.fromJson(Map<String, dynamic> json) {
    return SharedFolder(
      shareId: json['share_id'] as String? ?? '',
      peerId: json['peer_id'] as String? ?? '',
      peerNickname: json['peer_nickname'] as String? ?? '',
      name: json['name'] as String? ?? '',
      files: (json['files'] as List? ?? [])
          .map((f) => SharedFolderFile.fromJson(Map<String, dynamic>.from(f as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'share_id': shareId,
      'peer_id': peerId,
      'peer_nickname': peerNickname,
      'name': name,
      'files': files.map((f) => f.toJson()).toList(),
    };
  }
}
