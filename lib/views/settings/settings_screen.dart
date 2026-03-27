import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';
import '../../utils/theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buttMode = ref.watch(cigaretteButtModeProvider);
    final interval = ref.watch(buttIntervalMinutesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _sectionHeader('顯示設定'),
          _switchTile(
            icon: Icons.auto_awesome,
            title: '煙蒂模式',
            subtitle: '每根菸旁顯示煙蒂',
            value: buttMode,
            onChanged: (v) =>
                ref.read(cigaretteButtModeProvider.notifier).state = v,
          ),
          if (buttMode)
            _sliderTile(
              icon: Icons.timer,
              title: '最短間隔',
              subtitle: '$interval 分鐘',
              value: interval.toDouble(),
              min: 5,
              max: 120,
              divisions: 23,
              onChanged: (v) =>
                  ref.read(buttIntervalMinutesProvider.notifier).state = v.round(),
            ),
          const Divider(color: AppColors.surfaceLight, height: 32),
          _sectionHeader('關於'),
          _infoTile(
            icon: Icons.info_outline,
            title: '版本',
            trailing: 'v0.1.0 prototype',
          ),
          _infoTile(
            icon: Icons.phone,
            title: '戒菸專線',
            trailing: '0800-636363',
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '吸菸有害健康。如需戒菸協助，請撥打衛福部免費戒菸專線 0800-636363。',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.amber,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.amber,
      ),
    );
  }

  Widget _sliderTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: AppColors.textSecondary, size: 22),
          title: Text(title, style: const TextStyle(color: AppColors.textPrimary)),
          subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: AppColors.amber,
            inactiveColor: AppColors.surfaceLight,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String trailing,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary)),
      trailing: Text(trailing, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
    );
  }
}
