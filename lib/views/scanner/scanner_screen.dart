import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/smoking_record.dart';
import '../../providers/app_providers.dart';
import '../../utils/theme.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final _barcodeController = TextEditingController();

  @override
  void dispose() {
    _barcodeController.dispose();
    super.dispose();
  }

  void _onSubmit() {
    final code = _barcodeController.text.trim();
    if (code.isEmpty) return;

    final brandDb = ref.read(brandDatabaseProvider);
    final brand = brandDb.findByBarcode(code);

    if (brand != null) {
      final record = SmokingRecord(brandBarcode: brand.barcode);
      ref.read(recordsProvider.notifier).addRecord(record);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已記錄 ${brand.nameZH}'),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('找不到條碼：$code'),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('掃描菸盒條碼'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Camera placeholder
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.amber, width: 2),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.camera_alt, size: 48, color: AppColors.surfaceLight),
                    SizedBox(height: 8),
                    Text(
                      '相機掃描（Prototype 模式）\n請手動輸入條碼',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Manual barcode input
            TextField(
              controller: _barcodeController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: '輸入條碼（EAN-13）',
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.surfaceLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.amber),
                ),
                filled: true,
                fillColor: AppColors.surface,
              ),
              onSubmitted: (_) => _onSubmit(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('查詢'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
