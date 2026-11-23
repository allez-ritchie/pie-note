import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/common/app_platform.dart';

/// 密码存储抽象：生产环境用各平台原生安全存储（[FlutterSecureStorage]），
/// 单元测试注入内存实现，避免依赖平台通道。
abstract class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// 基于 flutter_secure_storage 的实现，底层随平台变化：
/// Android Keystore / iOS Keychain / macOS 钥匙串 / Windows 凭据管理器 /
/// Linux 系统密钥环（Secret Service / libsecret）。
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
/// - 访问密码写入 `flutter_secure_storage`（各平台原生安全存储），
///   **绝不**落到 shared_preferences / 日志 / 异常信息；
/// - 桌面端（尤其 Linux）可能没有可用的系统密钥环，此时 [save] 判为失败并
///   抛出 [SecretStorageException]，不会退化为明文保存。
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
    // 密码先写安全存储、成功后再写 Base URL：后者是「已配置」的判定依据，
    // 顺序反了会在密码写入失败时留下一个没有密码的半配置状态。
    try {
      if (config.password.isEmpty) {
        await _secretStore.delete(_passwordKey);
      } else {
        await _secretStore.write(_passwordKey, config.password);
      }
    } catch (error) {
      throw SecretStorageException(AppPlatform.secretStorageName, error);
    }
    await prefs.setString(_baseUrlKey, config.baseUrl.trim());
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

/// 安全存储不可用（例如 Linux 没有运行中的 Secret Service）。
///
/// 出现该异常时**不会**把密码写进 shared_preferences 之类的明文存储，
/// 而是让保存动作失败、由 UI 提示用户处理系统密钥环。
class SecretStorageException implements Exception {
  const SecretStorageException(this.platformName, this.cause);

  /// 平台安全存储名称，例如「系统密钥环（libsecret）」。
  final String platformName;

  /// 底层异常，仅用于排查，不向用户展示细节。
  final Object cause;

  String get message => '无法写入$platformName，密码未保存。请确认系统密钥环可用后重试。';

  @override
  String toString() => 'SecretStorageException($platformName): $cause';
}
