class Conversation {
  const Conversation({
    required this.conversationId,
    required this.conversationType,
    this.title,
    this.description,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.isArchived = false,
    this.members = const [],
  });

  final String conversationId;
  final String conversationType; // 'private', 'group', 'channel'
  final String? title;
  final String? description;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;
  final List<String> members;

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      conversationId: json['conversation_id'] as String? ?? '',
      conversationType: json['conversation_type'] as String? ?? 'group',
      title: json['title'] as String?,
      description: json['description'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: _parseTimestamp(json['created_at']),
      updatedAt: _parseTimestamp(json['updated_at']),
      isArchived: json['is_archived'] as bool? ?? false,
      members: json['members'] != null
          ? List<String>.from(json['members'] as List)
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'conversation_id': conversationId,
      'conversation_type': conversationType,
      'title': title,
      'description': description,
      'created_by': createdBy,
      'created_at': createdAt.millisecondsSinceEpoch / 1000,
      'updated_at': updatedAt.millisecondsSinceEpoch / 1000,
      'is_archived': isArchived,
      'members': members,
    };
  }
}

DateTime _parseTimestamp(Object? timestamp) {
  final seconds = timestamp is num ? timestamp : 0;
  return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
}
