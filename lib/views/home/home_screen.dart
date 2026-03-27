import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';
import '../../models/smoking_record.dart';
import '../../utils/theme.dart';
import '../stats/stats_screen.dart';
import '../collection/collection_screen.dart';
import '../settings/settings_screen.dart';
import '../scanner/scanner_screen.dart';
import 'widgets/physics_scene.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      backgroundColor: const Color(0xFFF5EDD6),
      body: PhysicsScene(),
    );
  }
}
