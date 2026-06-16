import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/ui/widgets/alert_banner.dart';
import '../state/lan_workspace_controller.dart';

class ConnectionPanel extends ConsumerStatefulWidget {
  const ConnectionPanel({super.key});

  @override
  ConsumerState<ConnectionPanel> createState() => _ConnectionPanelState();
}

class _ConnectionPanelState extends ConsumerState<ConnectionPanel> {
  late final TextEditingController _serverController;
  late final TextEditingController _nicknameController;

  @override
  void initState() {
    super.initState();
    final state = ref.read(lanWorkspaceProvider);
    _serverController = TextEditingController(text: 'http://127.0.0.1:8080');
    _nicknameController = TextEditingController(text: state.nickname);
  }

  @override
  void dispose() {
    _serverController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lanWorkspaceProvider);

    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.hasBoundedHeight
                    ? constraints.maxHeight - 48
                    : 0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.private_connectivity_outlined,
                      size: 40, color: Color(0xFFFF8B00)),
                  const SizedBox(height: 16),
                  Text(
                    'Offline-first LAN workspace',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Discover the local Docker server, chat in real time, and prepare high-speed local file transfers without cloud relays.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.8),
                        ),
                  ),
                  const SizedBox(height: 24),
                  if (state.isConnected) ...[
                    AlertBanner.success(
                      message:
                          'Successfully connected to ${state.serverUri?.host ?? 'server'}',
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (state.isConnecting && state.serverUri == null) ...[
                    const AlertBanner(
                      message: 'Searching for local servers on your network...',
                      icon: Icons.search,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (state.error != null) ...[
                    AlertBanner.error(message: state.error!),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _nicknameController,
                    enabled: !state.isConnected && !state.isConnecting,
                    decoration: const InputDecoration(
                      labelText: 'Your Nickname',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    onChanged:
                        ref.read(lanWorkspaceProvider.notifier).updateNickname,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _serverController,
                    enabled: !state.isConnected && !state.isConnecting,
                    decoration: const InputDecoration(
                      labelText: 'Manual Server URL',
                      prefixIcon: Icon(Icons.dns_outlined),
                      hintText: 'http://192.168.1.5:8080',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: state.isConnected
                              ? FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFE60F41),
                                  foregroundColor: Colors.white,
                                )
                              : null,
                          onPressed: state.isConnecting
                              ? null
                              : () {
                                  if (state.isConnected) {
                                    ref
                                        .read(lanWorkspaceProvider.notifier)
                                        .disconnect();
                                    return;
                                  }
                                  final uri = Uri.tryParse(
                                    _serverController.text.trim(),
                                  );
                                  if (uri != null) {
                                    ref
                                        .read(lanWorkspaceProvider.notifier)
                                        .connect(uri);
                                  }
                                },
                          icon: state.isConnecting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(state.isConnected
                                  ? Icons.link_off
                                  : Icons.link),
                          label: Text(state.isConnected
                              ? 'Disconnect'
                              : state.isConnecting
                                  ? 'Connecting...'
                                  : 'Connect'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        tooltip: 'Auto-discover',
                        onPressed: state.isConnecting || state.isConnected
                            ? null
                            : () {
                                final manualUri = Uri.tryParse(
                                  _serverController.text.trim(),
                                );
                                ref
                                    .read(lanWorkspaceProvider.notifier)
                                    .autoDiscoverAndConnect(
                                  preferredCandidates: [
                                    if (manualUri != null) manualUri,
                                  ],
                                );
                              },
                        icon: const Icon(Icons.radar),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
