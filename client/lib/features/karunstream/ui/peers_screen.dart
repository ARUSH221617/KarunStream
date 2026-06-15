import 'package:flutter/material.dart';
import '../widgets/peer_roster.dart';

class PeersScreen extends StatelessWidget {
  const PeersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: PeerRoster(),
    );
  }
}
