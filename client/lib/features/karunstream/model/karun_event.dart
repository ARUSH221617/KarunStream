class KarunEvent {
  const KarunEvent({
    required this.eventType,
    required this.payload,
  });

  final String eventType;
  final Map<String, dynamic> payload;

  factory KarunEvent.fromJson(Map<String, dynamic> json) {
    return KarunEvent(
      eventType: json['event_type'] as String? ?? 'ERROR',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'event_type': eventType,
      'payload': payload,
    };
  }
}
