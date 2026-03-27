import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/app_providers.dart';
import 'utils/theme.dart';
import 'views/home/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: CigaretteBugApp()));
}

class CigaretteBugApp extends StatelessWidget {
  const CigaretteBugApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CigaretteBug',
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      home: const _AppLoader(),
    );
  }
}

/// Loads brand database and records before showing the main scene.
class _AppLoader extends ConsumerStatefulWidget {
  const _AppLoader();

  @override
  ConsumerState<_AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends ConsumerState<_AppLoader> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final brandDb = ref.read(brandDatabaseProvider);
    await brandDb.load();
    await ref.read(recordsProvider.notifier).load();
    if (mounted) setState(() => _initialized = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5EDD6),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF6B5B3E)),
        ),
      );
    }
    return const HomeScreen();
  }
}
