import 'package:flutter/material.dart';

enum MainTab {
  dashboard(Icons.dashboard_outlined, 'Dashboard'),
  connect(Icons.connect_without_contact_outlined, 'Connect'),
  chat(Icons.forum_outlined, 'Chat'),
  peers(Icons.groups_2_outlined, 'Peers');

  const MainTab(this.iconData, this.label);

  final IconData iconData;
  final String label;
}
