import 'package:flutter/material.dart';
import '../../utils/theme.dart';

class GroupPlaceholderScreen extends StatelessWidget {
  const GroupPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('菸友圈')),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group, size: 48, color: AppColors.surfaceLight),
            SizedBox(height: 12),
            Text(
              '菸友圈即將推出',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '群聊 · 共享菸灰缸 · 群組統計',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
