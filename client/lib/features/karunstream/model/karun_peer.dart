class KarunPeer {
  const KarunPeer({
    required this.peerId,
    required this.nickname,
    required this.platform,
    required this.ip,
    this.avatarIndex,
  });

  final String peerId;
  final String nickname;
  final String platform;
  final String ip;
  final int? avatarIndex;

  factory KarunPeer.fromJson(Map<String, dynamic> json) {
    return KarunPeer(
      peerId: json['peer_id'] as String? ?? '',
      nickname: json['nickname'] as String? ?? 'Anonymous',
      platform: json['platform'] as String? ?? 'unknown',
      ip: json['ip'] as String? ?? 'unknown',
      avatarIndex: json['avatar_index'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'peer_id': peerId,
      'nickname': nickname,
      'platform': platform,
      'ip': ip,
      if (avatarIndex != null) 'avatar_index': avatarIndex,
    };
  }
}
