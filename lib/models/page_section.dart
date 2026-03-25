import 'package:flutter/material.dart';

class PageSection {
  const PageSection({
    required this.title,
    required this.category,
    required this.subtitle,
    required this.accent,
    required this.icon,
    required this.actions,
    required this.bullets,
  });

  final String title;
  final String category;
  final String subtitle;
  final Color accent;
  final IconData icon;
  final List<String> actions;
  final List<String> bullets;
}
