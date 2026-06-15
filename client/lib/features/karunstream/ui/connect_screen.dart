import 'package:flutter/material.dart';
import '../widgets/connection_panel.dart';

class ConnectScreen extends StatelessWidget {
  const ConnectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: ConnectionPanel(),
    );
  }
}
