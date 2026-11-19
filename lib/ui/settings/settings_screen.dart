import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/note_repository.dart';
import '../../state/providers.dart';
import '../common/navigation.dart';
import '../common/strings.dart';
import '../common/widgets.dart';
import 'settings_strings.dart';

/// 设置页：后端连接、外观、关于、网络说明与危险操作。
///
/// 整页用 [ListView] 组织，按分区拆成私有小 Widget；provider 的 loading /
/// data / error 三态直接用 [AsyncValue] 表达，只有连接测试等一次性交互
/// 才使用局部状态。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // 连接测试进行中标记：一次性交互状态、结果不落盘，故放在局部状态里。
  bool _testing = false;

  // 最近一次连接测试结果，用内联 banner 展示。
  ConnectionTestResult? _testResult;

  /// 用当前已保存的配置做连接测试（不落盘、不影响已有配置）。
  Future<void> _runTest() async {
    final config = ref.read(appConfigProvider).valueOrNull;
    if (config == null || !config.isConfigured) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final result = await ref.read(appConfigProvider.notifier).testConnection(
          baseUrl: config.baseUrl,
          password: config.password,
        );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
    // 测试通过说明地址与密码有效，顺便刷新服务端版本。
    if (result.ok) ref.invalidate(serverConfigProvider);
  }

  /// 打开配置页修改后端地址与密码。
  Future<void> _openSetup() async {
    final config = ref.read(appConfigProvider).valueOrNull;
    setState(() => _testResult = null);
    await AppNavigator.openSetup(
      context,
      initialBaseUrl: config?.baseUrl ?? '',
      initialPassword: config?.password ?? '',
      isEditing: true,
    );
    if (!mounted) return;
    // 返回后配置可能已变化，重新拉取服务端版本。
    ref.invalidate(serverConfigProvider);
  }

  /// 清除后端配置：二次确认（危险操作），成功后提示并由根组件自动回到配置页。
  Future<void> _clearConfig() async {
    final confirmed = await showConfirmDialog(
      context,
      title: SettingsStrings.clearDialogTitle,
      message: SettingsStrings.clearDialogMessage,
      confirmLabel: SettingsStrings.clearConfirm,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    // 清除后本页会被根组件移除，提前取根 ScaffoldMessenger 以便继续提示。
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(appConfigProvider.notifier).clear();
      messenger.showSnackBar(const SnackBar(content: Text(SettingsStrings.clearSuccess)));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${SettingsStrings.clearFailed}：${describeError(error)}')),
      );
    }
  }

  /// 切换主题并立即保存；失败时提示重试。
  Future<void> _setTheme(ThemeMode mode) async {
    try {
      await ref.read(themeModeProvider.notifier).setMode(mode);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${SettingsStrings.themeSaveFailed}：${describeError(error)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider).valueOrNull;
    final baseUrl = (config?.baseUrl ?? '').trim();
    final configured = config?.isConfigured ?? false;
    // 服务端版本：loading / error 由展示层兜底，不阻塞整页。
    final version = ref.watch(serverConfigProvider).whenData((value) => value.version);
    // 读不到主题时默认跟随系统。
    final themeMode = ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;

    return Scaffold(
      appBar: AppBar(title: const Text(SettingsStrings.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _backendSection(
            baseUrl: baseUrl,
            hasPassword: config?.hasPassword ?? false,
            configured: configured,
            version: version,
          ),
          const SizedBox(height: 20),
          _appearanceSection(themeMode),
          const SizedBox(height: 20),
          _aboutSection(baseUrl),
          const SizedBox(height: 20),
          _networkSection(),
          const SizedBox(height: 20),
          _dangerSection(configured: configured),
        ],
      ),
    );
  }

  Widget _backendSection({
    required String baseUrl,
    required bool hasPassword,
    required bool configured,
    required AsyncValue<String?> version,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    return _Section(
      title: SettingsStrings.sectionBackend,
      children: [
        if (!configured) const _HintLine(text: SettingsStrings.notConfiguredHint),
        _InfoRow(
          label: SettingsStrings.baseUrlLabel,
          value: Text(
            baseUrl.isEmpty ? SettingsStrings.notConfigured : baseUrl,
            style: baseUrl.isEmpty
                ? valueStyle?.copyWith(color: scheme.onSurfaceVariant)
                : valueStyle,
          ),
        ),
        _InfoRow(
          label: SettingsStrings.passwordLabel,
          value: Row(
            children: [
              Icon(hasPassword ? Icons.lock_rounded : Icons.lock_open_rounded,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                hasPassword ? SettingsStrings.passwordSaved : SettingsStrings.passwordMissing,
                style: valueStyle,
              ),
            ],
          ),
          caption: SettingsStrings.passwordNote,
        ),
        _InfoRow(
          label: SettingsStrings.serverVersionLabel,
          value: _versionValue(version, valueStyle),
        ),
        if (_testResult != null) _TestBanner(result: _testResult!),
        OutlinedButton.icon(
          onPressed: _testing || !configured ? null : _runTest,
          icon: _testing
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wifi_tethering_rounded),
          label: Text(_testing ? SettingsStrings.testing : SettingsStrings.testConnection),
        ),
        FilledButton.tonalIcon(
          onPressed: _openSetup,
          icon: const Icon(Icons.tune_rounded),
          label: Text(
            configured ? SettingsStrings.changeBackend : SettingsStrings.configureBackend,
          ),
        ),
      ],
    );
  }

  /// 服务端版本展示：加载中小进度、失败或缺失显示「未知」。
  Widget _versionValue(AsyncValue<String?> version, TextStyle? style) {
    final unknown = Text(SettingsStrings.unknownVersion, style: style);
    return version.when(
      data: (value) =>
          (value == null || value.trim().isEmpty) ? unknown : Text(value, style: style),
      loading: () => const SizedBox(
        width: 16, height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) => unknown,
    );
  }

  Widget _appearanceSection(ThemeMode themeMode) {
    final theme = Theme.of(context);
    return _Section(
      title: SettingsStrings.sectionAppearance,
      children: [
        Text(SettingsStrings.appearanceSubtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text(SettingsStrings.themeSystem)),
            ButtonSegment(value: ThemeMode.light, label: Text(SettingsStrings.themeLight)),
            ButtonSegment(value: ThemeMode.dark, label: Text(SettingsStrings.themeDark)),
          ],
          selected: {themeMode},
          showSelectedIcon: false,
          expandedInsets: EdgeInsets.zero,
          onSelectionChanged: (selection) => _setTheme(selection.first),
        ),
      ],
    );
  }

  Widget _aboutSection(String baseUrl) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    final bodyStyle =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.45);
    return _Section(
      title: SettingsStrings.sectionAbout,
      children: [
        _InfoRow(label: SettingsStrings.aboutAppName, value: Text(S.appName, style: valueStyle)),
        _InfoRow(label: SettingsStrings.aboutVersion, value: Text(S.appVersion, style: valueStyle)),
        _InfoRow(
          label: SettingsStrings.aboutBackend,
          value: Text(SettingsStrings.backendDescription, style: bodyStyle),
        ),
        _InfoRow(
          label: SettingsStrings.aboutApi,
          value: Text(baseUrl.isEmpty ? SettingsStrings.notConfigured : baseUrl,
              style: valueStyle),
        ),
        const _HintLine(text: SettingsStrings.imageNotice),
      ],
    );
  }

  Widget _networkSection() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bodyStyle =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.5);
    return _Section(
      title: SettingsStrings.sectionNetwork,
      children: [
        Row(
          children: [
            Icon(Icons.lan_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(SettingsStrings.networkTitle,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        Text(SettingsStrings.networkBody1, style: bodyStyle),
        Text(SettingsStrings.networkBody2, style: bodyStyle),
        Text(SettingsStrings.networkBody3, style: bodyStyle),
      ],
    );
  }

  Widget _dangerSection({required bool configured}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Section(
      title: SettingsStrings.sectionDanger,
      children: [
        Text(SettingsStrings.clearSubtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45)),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: configured ? _clearConfig : null,
          icon: const Icon(Icons.delete_forever_rounded),
          label: const Text(SettingsStrings.clearButton),
        ),
      ],
    );
  }
}

/// 分区标题 + 卡片容器，统一各分区的间距与视觉。
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
          child: Text(title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              )),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 14,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

/// 信息行：左侧固定宽度标签 + 右侧内容（可带一行说明）。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.caption});

  final String label;
  final Widget value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(label,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              value,
              if (caption != null)
                Text(caption!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
                      height: 1.35,
                    )),
            ],
          ),
        ),
      ],
    );
  }
}

/// 弱化样式的带图标提示行。
class _HintLine extends StatelessWidget {
  const _HintLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4)),
        ),
      ],
    );
  }
}

/// 连接测试结果的内联 banner（成功含版本号，失败含错误原因）。
class _TestBanner extends StatelessWidget {
  const _TestBanner({required this.result});

  final ConnectionTestResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ok = result.ok;
    final background = ok ? scheme.secondaryContainer : scheme.errorContainer;
    final foreground = ok ? scheme.onSecondaryContainer : scheme.onErrorContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              size: 18, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_message(),
                style: theme.textTheme.bodySmall?.copyWith(color: foreground, height: 1.4)),
          ),
        ],
      ),
    );
  }

  String _message() {
    if (!result.ok) return result.message;
    final version = result.serverVersion?.trim() ?? '';
    final text = version.isEmpty
        ? SettingsStrings.testSuccess
        : SettingsStrings.testSuccessWithVersion(version);
    return result.authEnabled ? text : '$text · ${SettingsStrings.testAuthDisabledSuffix}';
  }
}
