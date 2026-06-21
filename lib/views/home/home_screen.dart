import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import '../stats/stats_screen.dart';
import '../collection/collection_screen.dart';
import '../settings/settings_screen.dart';
import 'widgets/physics_scene.dart';

/// Root shell: a legible bottom NavigationBar over the four real destinations.
/// The physics canvas is full-bleed behind the bar so packs roll up to the top
/// (mirrors YoiLog's deliberate bottom-tab layout) instead of being navigated
/// by unlabeled circles floating on the simulation.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _pages = [
    PhysicsScene(),
    StatsScreen(),
    CollectionScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        height: 64,
        elevation: 0,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.amber.withValues(alpha: 0.22),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined, color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.home, color: AppColors.amberLight),
              label: '首頁'),
          NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined,
                  color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.bar_chart, color: AppColors.amberLight),
              label: '統計'),
          NavigationDestination(
              icon: Icon(Icons.collections_bookmark_outlined,
                  color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.collections_bookmark,
                  color: AppColors.amberLight),
              label: '圖鑑'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined,
                  color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.settings, color: AppColors.amberLight),
              label: '設定'),
        ],
      ),
    );
  }
}
