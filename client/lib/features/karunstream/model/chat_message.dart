class ChatMessage {
  const ChatMessage({
    required this.messageId,
    required this.senderId,
    required this.receiverId,
    required this.body,
    required this.timestamp,
    this.messageType = 'text',
  });

  final String messageId;
  final String senderId;
  final String receiverId;
  final String body;
  final DateTime timestamp;
  final String messageType;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      messageId: json['msg_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      receiverId: json['receiver_id'] as String? ?? 'global',
      body: json['body'] as String? ?? '',
      messageType: json['message_type'] as String? ?? 'text',
      timestamp: _parseTimestamp(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'msg_id': messageId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'body': body,
      'message_type': messageType,
      'timestamp': timestamp.millisecondsSinceEpoch / 1000,
    };
  }
}

DateTime _parseTimestamp(Object? timestamp) {
  final seconds = timestamp is num ? timestamp : 0;
  return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
}
