import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/lan_workspace_controller.dart';

class MessageComposer extends ConsumerStatefulWidget {
  const MessageComposer({super.key});

  @override
  ConsumerState<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends ConsumerState<MessageComposer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected =
        ref.watch(lanWorkspaceProvider.select((state) => state.isConnected));

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            enabled: isConnected,
            decoration: const InputDecoration(
              hintText: 'Send a local LAN message...',
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: isConnected ? _send : null,
          icon: const Icon(Icons.send_rounded),
        ),
      ],
    );
  }

  void _send() {
    ref.read(lanWorkspaceProvider.notifier).sendChat(_controller.text);
    _controller.clear();
  }
}
