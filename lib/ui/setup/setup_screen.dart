import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/config_store.dart';
import '../../data/note_repository.dart';
import '../../state/providers.dart';
import '../common/strings.dart';
import 'setup_strings.dart';

/// 首次启动的后端配置页，也用于设置页的「修改后端」。
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({
    super.key,
    this.initialBaseUrl,
    this.initialPassword,
    this.isEditing = false,
  });

  final String? initialBaseUrl;
  final String? initialPassword;
  final bool isEditing;

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _baseUrlController;
  late final TextEditingController _passwordController;

  bool _obscurePassword = true;
  bool _testing = false;
  bool _saving = false;
  ConnectionTestResult? _testResult;
  String? _formError;

  @override
  void initState() {
    super.initState();
    final config = ref.read(appConfigProvider).valueOrNull;
    _baseUrlController = TextEditingController(
      text: widget.initialBaseUrl ?? config?.baseUrl ?? '',
    );
    _passwordController = TextEditingController(
      text: widget.initialPassword ?? config?.password ?? '',
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<ConnectionTestResult> _runTest() async {
    setState(() {
      _testing = true;
      _testResult = null;
      _formError = null;
    });
    final result = await ref.read(appConfigProvider.notifier).testConnection(
          baseUrl: _baseUrlController.text,
          password: _passwordController.text,
        );
    if (!mounted) return result;
    setState(() {
      _testing = false;
      _testResult = result;
    });
    return result;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _formError = null;
    });
    final result = await ref.read(appConfigProvider.notifier).testConnection(
          baseUrl: _baseUrlController.text,
          password: _passwordController.text,
        );
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _saving = false;
        _testResult = result;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      return;
    }
    try {
      await ref.read(appConfigProvider.notifier).save(
            baseUrl: _baseUrlController.text,
            password: _passwordController.text,
          );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } on SecretStorageException catch (e) {
      // 密码写不进系统安全存储时不落任何明文，明确提示用户。
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(SetupStrings.saved)),
    );
    if (widget.isEditing) {
      Navigator.of(context).pop();
    }
  }

  String? _validateBaseUrl(String? value) {
    if (value == null || value.trim().isEmpty) return SetupStrings.baseUrlEmpty;
    try {
      normalizeBaseUrl(value);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isEditing = widget.isEditing;

    return Scaffold(
      appBar: isEditing
          ? AppBar(title: const Text(SetupStrings.editTitle))
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isEditing) ...[
                      Center(
                        child: Container(
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
                          child: Icon(
                            Icons.edit_note_rounded,
                            size: 42,
                            color: scheme.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        S.appName,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        S.appSlogan,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                    Text(
                      SetupStrings.sectionBackend,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _baseUrlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      validator: _validateBaseUrl,
                      onChanged: (_) {
                        if (_testResult != null || _formError != null) {
                          setState(() {
                            _testResult = null;
                            _formError = null;
                          });
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: SetupStrings.baseUrlLabel,
                        hintText: SetupStrings.baseUrlHint,
                        helperText: SetupStrings.baseUrlHelper,
                        prefixIcon: Icon(Icons.link_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _save(),
                      decoration: InputDecoration(
                        labelText: SetupStrings.passwordLabel,
                        hintText: SetupStrings.passwordHint,
                        helperText: SetupStrings.passwordHelper,
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_testResult != null) ...[
                      _ConnectionBanner(result: _testResult!),
                      const SizedBox(height: 16),
                    ],
                    if (_formError != null) ...[
                      Text(
                        _formError!,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                      ),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: _testing || _saving ? null : _runTest,
                      icon: _testing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering_rounded),
                      label: Text(
                        _testing ? SetupStrings.testing : SetupStrings.testConnection,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _testing || _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded),
                      label: Text(
                        _saving
                            ? SetupStrings.saving
                            : isEditing
                                ? SetupStrings.save
                                : SetupStrings.saveAndEnter,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      isEditing ? SetupStrings.editHint : SetupStrings.networkHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.result});

  final ConnectionTestResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = result.ok;
    final background = ok ? scheme.secondaryContainer : scheme.errorContainer;
    final foreground = ok ? scheme.onSecondaryContainer : scheme.onErrorContainer;
    final message = ok
        ? (result.serverVersion == null || result.serverVersion!.isEmpty
            ? SetupStrings.testSuccess
            : '${SetupStrings.testSuccess} · 版本 ${result.serverVersion}')
        : result.message;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 20,
            color: foreground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
