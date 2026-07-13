import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/lan_workspace_controller.dart';
import '../model/conversation.dart';
import '../model/karun_peer.dart';
import '../widgets/message_composer.dart';
import '../widgets/message_list.dart';
import '../../../theme/app_colors.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    // Fetch conversations list when chat screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(lanWorkspaceProvider.notifier).fetchConversations();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lanWorkspaceProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;

        if (isWide) {
          return Row(
            children: [
              // Sidebar
              SizedBox(
                width: 320,
                child: Card(
                  margin: const EdgeInsets.only(right: 8),
                  clipBehavior: Clip.antiAlias,
                  child: _buildSidebar(state, context, isDark),
                ),
              ),
              // Chat Details area
              Expanded(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: _buildChatArea(state, context),
                ),
              ),
            ],
          );
        } else {
          // Narrow screen (mobile layout)
          // If a conversation is selected, show the chat area, otherwise show the sidebar
          if (state.activeConversationId != null) {
            return Card(
              clipBehavior: Clip.antiAlias,
              child: PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, result) {
                  if (!didPop) {
                    ref.read(lanWorkspaceProvider.notifier).selectConversation(null);
                  }
                },
                child: Stack(
                  children: [
                    _buildChatArea(state, context),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: SafeArea(
                        child: IconButton.filledTonal(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () {
                            ref.read(lanWorkspaceProvider.notifier).selectConversation(null);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else {
            return Card(
              clipBehavior: Clip.antiAlias,
              child: _buildSidebar(state, context, isDark),
            );
          }
        }
      },
    );
  }

  Widget _buildSidebar(LanWorkspaceState state, BuildContext context, bool isDark) {
    final theme = Theme.of(context);

    // List of active conversations from server
    final serverConvs = state.conversations.where((c) {
      if (_searchQuery.isEmpty) return true;
      return c.title?.toLowerCase().contains(_searchQuery) ?? false;
    }).toList();

    // Discovered peers for Direct Messages
    final dmPeers = state.peers.where((p) {
      if (p.peerId == state.peerId) return false;
      if (_searchQuery.isEmpty) return true;
      return p.nickname.toLowerCase().contains(_searchQuery);
    }).toList();

    return Column(
      children: [
        // Sidebar Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Conversations',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : AppColors.navy,
                ),
              ),
              IconButton(
                tooltip: 'Create Group or Channel',
                icon: Icon(Icons.add_comment_rounded, color: theme.colorScheme.primary),
                onPressed: state.isConnected ? () => _showCreateConversationDialog(context, state) : null,
              ),
            ],
          ),
        ),

        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search chats or peers...',
              prefixIcon: const Icon(Icons.search),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
            ),
          ),
        ),

        const SizedBox(height: 8),

        // List
        Expanded(
          child: state.isConnected
              ? ListView(
                  children: [
                    // Global chat item
                    _buildGlobalChatItem(state, theme),

                    // Groups & Channels Section
                    if (serverConvs.isNotEmpty) ...[
                      _buildSectionHeader(theme, 'Groups & Channels'),
                      for (final conv in serverConvs) _buildConversationItem(conv, state, theme),
                    ],

                    // Direct Messages Section
                    if (dmPeers.isNotEmpty) ...[
                      _buildSectionHeader(theme, 'Subnet Peers (DMs)'),
                      for (final peer in dmPeers) _buildPeerChatItem(peer, state, theme),
                    ],

                    if (serverConvs.isEmpty && dmPeers.isEmpty && _searchQuery.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No matching chats found.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor),
                        ),
                      ),
                  ],
                )
              : const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Not connected to a server. Connect via the Dashboard to start chatting.'),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 1.2,
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildGlobalChatItem(LanWorkspaceState state, ThemeData theme) {
    final isSelected = state.activeConversationId == null;
    return ListMessageItem(
      title: 'Global LAN Room',
      subtitle: 'Broadcast to everyone on this network',
      avatarIcon: Icons.public_rounded,
      avatarColor: AppColors.orange,
      isSelected: isSelected,
      onTap: () {
        ref.read(lanWorkspaceProvider.notifier).selectConversation(null);
      },
    );
  }

  Widget _buildConversationItem(Conversation conv, LanWorkspaceState state, ThemeData theme) {
    final isSelected = state.activeConversationId == conv.conversationId;
    final isGroup = conv.conversationType == 'group';
    final typeLabel = isGroup ? 'Group' : 'Channel';

    return ListMessageItem(
      title: conv.title ?? 'Untitled $typeLabel',
      subtitle: conv.description ?? '$typeLabel Conversation',
      avatarIcon: isGroup ? Icons.groups_rounded : Icons.campaign_rounded,
      avatarColor: isGroup ? AppColors.slate : Colors.purple,
      isSelected: isSelected,
      onTap: () {
        ref.read(lanWorkspaceProvider.notifier).selectConversation(conv.conversationId);
      },
    );
  }

  Widget _buildPeerChatItem(KarunPeer peer, LanWorkspaceState state, ThemeData theme) {
    // Check if there is an existing private conversation for this peer
    final privateKey = [state.peerId, peer.peerId]..sort();
    final keyStr = '${privateKey[0]}:${privateKey[1]}';
    final existingConv = state.conversations.cast<Conversation?>().firstWhere(
          (c) => c?.conversationType == 'private' && c?.title == keyStr,
          orElse: () => null,
        );

    final isSelected = state.activeConversationId != null &&
        (state.activeConversationId == peer.peerId ||
            (existingConv != null && state.activeConversationId == existingConv.conversationId));

    return ListMessageItem(
      title: peer.nickname,
      subtitle: 'Start private chat (${peer.platform})',
      avatarChar: peer.nickname.characters.first.toUpperCase(),
      avatarColor: AppColors.slate,
      isSelected: isSelected,
      onTap: () async {
        // Resolve private chat conversation
        final notifier = ref.read(lanWorkspaceProvider.notifier);
        if (existingConv != null) {
          notifier.selectConversation(existingConv.conversationId);
        } else {
          // Send creation request for private chat
          await notifier.createConversation(
            'private',
            initialMembers: [peer.peerId],
          );
        }
      },
    );
  }

  Widget _buildChatArea(LanWorkspaceState state, BuildContext context) {

    if (state.activeConversationId == null) {
      // Global chat selected
      return Stack(
        children: [
          const Positioned.fill(child: MessageList()),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _buildChatHeader(
              title: 'Global LAN Room',
              subtitle: 'Local broadcast room',
              icon: Icons.public_rounded,
              actions: const [],
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MessageComposer(),
          ),
        ],
      );
    }

    final activeConv = state.conversations.cast<Conversation?>().firstWhere(
          (c) => c?.conversationId == state.activeConversationId,
          orElse: () => null,
        );

    if (activeConv == null) {
      // Might be loading or created via fallback
      return const Center(child: CircularProgressIndicator());
    }

    final isGroup = activeConv.conversationType == 'group';
    final isChannel = activeConv.conversationType == 'channel';
    final isPrivate = activeConv.conversationType == 'private';

    String title = activeConv.title ?? 'Private Chat';
    String subtitle = activeConv.description ?? 'Conversation';
    IconData icon = Icons.chat_bubble_outline_rounded;

    if (isPrivate) {
      // Find the other member's nickname
      final otherPeerId = activeConv.members.firstWhere(
        (m) => m != state.peerId,
        orElse: () => 'Unknown',
      );
      final peer = state.peers.cast<KarunPeer?>().firstWhere(
            (p) => p?.peerId == otherPeerId,
            orElse: () => null,
          );
      title = peer?.nickname ?? 'Private Chat';
      subtitle = peer != null ? '${peer.platform} • Online' : 'Offline Peer';
      icon = Icons.person_outline_rounded;
    } else if (isGroup) {
      icon = Icons.groups_rounded;
      subtitle = '${activeConv.members.length} members';
    } else if (isChannel) {
      icon = Icons.campaign_rounded;
      subtitle = 'Broadcast Channel';
    }

    return Stack(
      children: [
        Positioned.fill(
          child: state.isLoadingMessages
              ? const Center(child: CircularProgressIndicator())
              : const MessageList(),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: _buildChatHeader(
            title: title,
            subtitle: subtitle,
            icon: icon,
            actions: [
              if (isGroup || isChannel)
                IconButton(
                  tooltip: 'View Members / Info',
                  icon: const Icon(Icons.info_outline_rounded),
                  onPressed: () => _showMembersListDialog(context, activeConv, state),
                ),
              if (isGroup || isChannel)
                IconButton(
                  tooltip: 'Add Member',
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  onPressed: () => _showAddMemberDialog(context, activeConv, state),
                ),
            ],
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: MessageComposer(),
        ),
      ],
    );
  }

  Widget _buildChatHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> actions,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.navy : Colors.white).withValues(alpha: 0.9),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const SizedBox(width: 48), // Padding space for back button on mobile
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }

  // DIALOGS

  void _showCreateConversationDialog(BuildContext context, LanWorkspaceState state) {
    String type = 'group';
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final List<String> selectedPeerIds = [];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final peers = state.peers.where((p) => p.peerId != state.peerId).toList();

            return AlertDialog(
              title: const Text('New Conversation'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type Switcher
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'group',
                            label: Text('Group Chat'),
                            icon: Icon(Icons.groups_rounded),
                          ),
                          ButtonSegment(
                            value: 'channel',
                            label: Text('Channel'),
                            icon: Icon(Icons.campaign_rounded),
                          ),
                        ],
                        selected: {type},
                        onSelectionChanged: (selection) {
                          setDialogState(() {
                            type = selection.first;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      // Title Textfield
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'Title *',
                          hintText: 'Enter conversation title',
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Description Textfield
                      TextField(
                        controller: descController,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText: 'Enter optional description',
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (peers.isNotEmpty) ...[
                        const Text(
                          'Select Members:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: peers.length,
                            itemBuilder: (context, index) {
                              final peer = peers[index];
                              final isSelected = selectedPeerIds.contains(peer.peerId);
                              return CheckboxListTile(
                                title: Text(peer.nickname),
                                subtitle: Text(peer.platform),
                                value: isSelected,
                                onChanged: (val) {
                                  setDialogState(() {
                                    if (val == true) {
                                      selectedPeerIds.add(peer.peerId);
                                    } else {
                                      selectedPeerIds.remove(peer.peerId);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      ] else ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'No other subnet peers discovered yet to invite.',
                            style: TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL'),
                ),
                FilledButton(
                  onPressed: () {
                    final title = titleController.text.trim();
                    if (title.isEmpty) return;
                    ref.read(lanWorkspaceProvider.notifier).createConversation(
                          type,
                          title: title,
                          description: descController.text.trim(),
                          initialMembers: [state.peerId, ...selectedPeerIds],
                        );
                    Navigator.pop(context);
                  },
                  child: const Text('CREATE'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddMemberDialog(BuildContext context, Conversation conv, LanWorkspaceState state) {
    showDialog(
      context: context,
      builder: (context) {
        final invitedPeers = state.peers.where((p) {
          return p.peerId != state.peerId && !conv.members.contains(p.peerId);
        }).toList();

        return AlertDialog(
          title: const Text('Add Member'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: SizedBox(
            width: 320,
            child: invitedPeers.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'All discovered subnet peers are already members of this chat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: invitedPeers.length,
                    itemBuilder: (context, index) {
                      final peer = invitedPeers[index];
                      return ListTile(
                        leading: CircleAvatar(child: Text(peer.nickname.characters.first.toUpperCase())),
                        title: Text(peer.nickname),
                        subtitle: Text(peer.platform),
                        trailing: FilledButton.tonal(
                          onPressed: () {
                            ref
                                .read(lanWorkspaceProvider.notifier)
                                .addMemberToActiveConversation(peer.peerId);
                            Navigator.pop(context);
                          },
                          child: const Text('ADD'),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  void _showMembersListDialog(BuildContext context, Conversation conv, LanWorkspaceState state) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${conv.title} Members'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: SizedBox(
            width: 320,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: conv.members.length,
              itemBuilder: (context, index) {
                final memberId = conv.members[index];
                // Check if we have this peer details in our peers registry
                final peer = state.peers.cast<KarunPeer?>().firstWhere(
                      (p) => p?.peerId == memberId,
                      orElse: () => null,
                    );
                final name = peer?.nickname ?? (memberId == state.peerId ? '${state.nickname} (You)' : 'Offline Peer');
                final platform = peer?.platform ?? 'unknown';

                return ListTile(
                  leading: CircleAvatar(child: Text(name.characters.first.toUpperCase())),
                  title: Text(name),
                  subtitle: Text(platform),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }
}

class ListMessageItem extends StatelessWidget {
  const ListMessageItem({
    super.key,
    required this.title,
    required this.subtitle,
    this.avatarIcon,
    this.avatarChar,
    required this.avatarColor,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData? avatarIcon;
  final String? avatarChar;
  final Color avatarColor;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: isSelected ? theme.colorScheme.primary : avatarColor.withValues(alpha: 0.2),
          foregroundColor: isSelected ? Colors.white : avatarColor,
          child: avatarIcon != null ? Icon(avatarIcon, size: 20) : Text(avatarChar ?? ''),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
