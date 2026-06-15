class ServerStatus {
  const ServerStatus({
    required this.status,
    required this.serverId,
    required this.version,
    required this.activePeers,
  });

  final String status;
  final String serverId;
  final String version;
  final int activePeers;

  factory ServerStatus.fromJson(Map<String, dynamic> json) {
    return ServerStatus(
      status: json['status'] as String? ?? 'unknown',
      serverId: json['server_id'] as String? ?? '',
      version: json['version'] as String? ?? '',
      activePeers: json['active_peers'] as int? ?? 0,
    );
  }
}
