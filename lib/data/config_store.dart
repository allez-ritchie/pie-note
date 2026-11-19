import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 密码存储抽象：生产环境用 Android Keystore（[FlutterSecureStorage]），
/// 单元测试注入内存实现，避免依赖平台通道。
abstract class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// 基于 flutter_secure_storage 的实现（Android Keystore 加密）。
class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// 应用运行配置：后端地址 + 访问密码。
@immutable
class AppConfig {
  const AppConfig({required this.baseUrl, required this.password});

  static const AppConfig empty = AppConfig(baseUrl: '', password: '');

  final String baseUrl;
  final String password;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  bool get hasPassword => password.isNotEmpty;

  AppConfig copyWith({String? baseUrl, String? password}) {
    return AppConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      password: password ?? this.password,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppConfig &&
        other.baseUrl == baseUrl &&
        other.password == password;
  }

  @override
  int get hashCode => Object.hash(baseUrl, password);

  @override
  String toString() => 'AppConfig(baseUrl: $baseUrl, password: ******)';
}

/// 配置持久化。
///
/// - Base URL 等非敏感配置写入 `shared_preferences`；
/// - 访问密码写入 `flutter_secure_storage`（Android Keystore 加密），
///   **绝不**落到 shared_preferences / 日志 / 异常信息。
class ConfigStore {
  ConfigStore({
    SharedPreferences? preferences,
    SecretStore? secretStore,
  })  : _preferences = preferences,
        _secretStore = secretStore ?? SecureSecretStore();

  static const String _baseUrlKey = 'backend.base_url';
  static const String _passwordKey = 'backend.password';
  static const String _themeModeKey = 'ui.theme_mode';

  SharedPreferences? _preferences;
  final SecretStore _secretStore;

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  /// 读取配置。密码读取失败（例如 Keystore 数据损坏）时按「未配置密码」处理，
  /// 由 UI 引导用户重新输入，不允许回退到明文或崩溃。
  Future<AppConfig> load() async {
    final prefs = await _prefs;
    final baseUrl = (prefs.getString(_baseUrlKey) ?? '').trim();
    String password = '';
    try {
      password = (await _secretStore.read(_passwordKey)) ?? '';
    } catch (_) {
      password = '';
    }
    return AppConfig(baseUrl: baseUrl, password: password);
  }

  Future<void> save(AppConfig config) async {
    final prefs = await _prefs;
    await prefs.setString(_baseUrlKey, config.baseUrl.trim());
    if (config.password.isEmpty) {
      await _secretStore.delete(_passwordKey);
    } else {
      await _secretStore.write(_passwordKey, config.password);
    }
  }

  /// 清除后端配置（保留主题等本机偏好）。
  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_baseUrlKey);
    try {
      await _secretStore.delete(_passwordKey);
    } catch (_) {
      // 清理失败不阻塞「退出配置」流程。
    }
  }

  Future<ThemeMode> loadThemeMode() async {
    final prefs = await _prefs;
    switch (prefs.getString(_themeModeKey)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await _prefs;
    await prefs.setString(_themeModeKey, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }
}
