import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'ui/common/strings.dart';
import 'ui/home/home_shell.dart';
import 'ui/setup/setup_screen.dart';
import 'ui/theme/app_theme.dart';

/// 应用根组件：主题 + 根据配置状态决定进入配置页还是主界面。
class PieNoteApp extends ConsumerWidget {
  const PieNoteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    return MaterialApp(
      title: S.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const _RootGate(),
    );
  }
}

/// 启动门禁：读取配置 → 已配置进入主界面，否则进入配置页。
class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(appConfigProvider);
    return configAsync.when(
      loading: () => const _SplashScreen(),
      error: (error, stackTrace) => const SetupScreen(),
      data: (config) =>
          config.isConfigured ? const HomeShell() : const SetupScreen(),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, scheme.tertiary],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(Icons.edit_note_rounded, size: 42, color: scheme.onPrimary),
            ),
            const SizedBox(height: 24),
            Text(
              S.appName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}
