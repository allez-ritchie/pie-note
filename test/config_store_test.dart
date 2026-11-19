import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pie_note/data/config_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 内存版密码存储：完全替代 flutter_secure_storage，避免平台通道依赖。
class _MemorySecretStore implements SecretStore {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

/// 模拟 Keystore 数据损坏：读取时抛异常。
class _ThrowingSecretStore implements SecretStore {
  @override
  Future<String?> read(String key) async => throw StateError('keystore corrupted');

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;
  late _MemorySecretStore secrets;
  late ConfigStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
    secrets = _MemorySecretStore();
    store = ConfigStore(preferences: preferences, secretStore: secrets);
  });

  test('初始 load 返回空配置', () async {
    final config = await store.load();

    expect(config, AppConfig.empty);
    expect(config.baseUrl, isEmpty);
    expect(config.password, isEmpty);
    expect(config.isConfigured, isFalse);
    expect(config.hasPassword, isFalse);
  });

  test('save 后 load 往返一致', () async {
    const config = AppConfig(baseUrl: 'http://host:5055', password: 'pw');

    await store.save(config);

    final loaded = await store.load();
    expect(loaded, config);
    expect(loaded.baseUrl, 'http://host:5055');
    expect(loaded.password, 'pw');
    expect(loaded.isConfigured, isTrue);
    expect(loaded.hasPassword, isTrue);
  });

  test('密码只进 SecretStore，不写入 SharedPreferences', () async {
    await store.save(const AppConfig(baseUrl: 'http://host:5055', password: 'pw'));

    expect(secrets.data.values, contains('pw'));
    for (final key in preferences.getKeys()) {
      expect(
        preferences.get(key),
        isNot('pw'),
        reason: 'SharedPreferences 中不允许出现明文密码（key=$key）',
      );
    }
  });

  test('clear 后 baseUrl 与密码都为空', () async {
    await store.save(const AppConfig(baseUrl: 'http://host:5055', password: 'pw'));

    await store.clear();

    final config = await store.load();
    expect(config.baseUrl, isEmpty);
    expect(config.password, isEmpty);
    expect(config.isConfigured, isFalse);
    expect(secrets.data, isEmpty);
  });

  test('保存空密码时会删除已存密码', () async {
    await store.save(const AppConfig(baseUrl: 'http://host:5055', password: 'pw'));

    await store.save(const AppConfig(baseUrl: 'http://host:5055', password: ''));

    expect((await store.load()).password, isEmpty);
    expect(secrets.data, isEmpty);
  });

  test('save 会去掉 baseUrl 首尾空白', () async {
    await store.save(const AppConfig(baseUrl: '  http://host:5055  ', password: 'pw'));

    expect((await store.load()).baseUrl, 'http://host:5055');
  });

  test('密码读取失败时回退为空密码且不崩溃', () async {
    final corrupted = ConfigStore(
      preferences: preferences,
      secretStore: _ThrowingSecretStore(),
    );

    final config = await corrupted.load();

    expect(config.baseUrl, isEmpty);
    expect(config.password, isEmpty);
    expect(config.isConfigured, isFalse);
  });

  test('主题模式默认 system，set light/dark 后往返一致', () async {
    expect(await store.loadThemeMode(), ThemeMode.system);

    await store.saveThemeMode(ThemeMode.light);
    expect(await store.loadThemeMode(), ThemeMode.light);

    await store.saveThemeMode(ThemeMode.dark);
    expect(await store.loadThemeMode(), ThemeMode.dark);

    await store.saveThemeMode(ThemeMode.system);
    expect(await store.loadThemeMode(), ThemeMode.system);
  });
}
