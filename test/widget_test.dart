import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pie_note/app.dart';
import 'package:pie_note/data/config_store.dart';
import 'package:pie_note/state/providers.dart';
import 'package:pie_note/ui/setup/setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 内存版密码存储：替代 flutter_secure_storage，避免平台通道依赖。
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('未配置后端时启动进入配置页', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final store = ConfigStore(
      preferences: preferences,
      secretStore: _MemorySecretStore(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [configStoreProvider.overrideWithValue(store)],
        child: const PieNoteApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SetupScreen), findsOneWidget);
  });
}
