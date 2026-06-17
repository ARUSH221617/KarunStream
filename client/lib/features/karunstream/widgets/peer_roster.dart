import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/lan_workspace_controller.dart';
import 'karun_empty_state.dart';

class PeerRoster extends ConsumerWidget {
  const PeerRoster({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lanWorkspaceProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.groups_2_outlined),
                const SizedBox(width: 8),
                Text(
                  'Active Peers',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
                'Server peers: ${state.status?.activePeers ?? state.peers.length}'),
            const SizedBox(height: 12),
            Expanded(
              child: state.peers.isEmpty
                  ? const KarunEmptyState(
                      icon: Icons.devices_other_outlined,
                      title: 'Looking for Peers',
                      subtitle: 'No other devices discovered on this subnet yet. Make sure KarunStream is running on them.',
                    )
                  : ListView.separated(
                      itemCount: state.peers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final peer = state.peers[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            child: Text(
                                peer.nickname.characters.first.toUpperCase()),
                          ),
                          title: Text(peer.nickname),
                          subtitle: Text('${peer.platform} • ${peer.ip}'),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
