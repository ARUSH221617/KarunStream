import 'package:flutter/material.dart';
import '../widgets/message_composer.dart';
import '../widgets/message_list.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: MessageList(),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MessageComposer(),
          ),
        ],
      ),
    );
  }
}
