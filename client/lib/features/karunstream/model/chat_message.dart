import 'file_offer.dart';

class ChatMessage {
  const ChatMessage({
    required this.messageId,
    required this.senderId,
    required this.receiverId,
    required this.body,
    required this.timestamp,
    this.messageType = 'text',
    this.isEdited = false,
    List<FileOffer>? fileOffers,
  }) : _fileOffers = fileOffers;

  final String messageId;
  final String senderId;
  final String receiverId;
  final String body;
  final DateTime timestamp;
  final String messageType;
  final bool isEdited;
  final List<FileOffer>? _fileOffers;

  List<FileOffer> get fileOffers => _fileOffers ?? const [];

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      messageId: json['msg_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      receiverId: json['receiver_id'] as String? ?? 'global',
      body: json['body'] as String? ?? '',
      messageType: json['message_type'] as String? ?? 'text',
      isEdited: json['is_edited'] as bool? ?? false,
      timestamp: _parseTimestamp(json['timestamp']),
      fileOffers: json['file_offers'] != null
          ? (json['file_offers'] as List)
              .map((o) => FileOffer.fromJson(Map<String, dynamic>.from(o as Map)))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'msg_id': messageId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'body': body,
      'message_type': messageType,
      'is_edited': isEdited,
      'timestamp': timestamp.millisecondsSinceEpoch / 1000,
      'file_offers': fileOffers.map((o) => o.toJson()).toList(),
    };
  }

  ChatMessage copyWith({
    String? body,
    bool? isEdited,
    List<FileOffer>? fileOffers,
  }) {
    return ChatMessage(
      messageId: messageId,
      senderId: senderId,
      receiverId: receiverId,
      body: body ?? this.body,
      timestamp: timestamp,
      messageType: messageType,
      isEdited: isEdited ?? this.isEdited,
      fileOffers: fileOffers ?? this.fileOffers,
    );
  }
}

DateTime _parseTimestamp(Object? timestamp) {
  final seconds = timestamp is num ? timestamp : 0;
  return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
}
