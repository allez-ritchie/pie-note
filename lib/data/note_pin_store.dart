import 'package:shared_preferences/shared_preferences.dart';

/// 置顶笔记的本地存储。
///
/// 为什么放在本地：Open Notebook 的 `NoteResponse` 只有
/// `id / title / content / note_type / created / updated`，**没有置顶字段**，
/// `PUT /api/notes/{id}` 也只接受 title/content/note_type（见 AGENTS.md 第 2.2 节）。
/// 置顶属于浏览偏好而不是笔记内容，因此不写进正文（避免污染 Markdown、
/// 破坏块间空白），而是作为**本设备**的偏好存在 shared_preferences 里。
///
/// 注意：这也意味着置顶不跨设备同步；UI 上必须明确标注「仅本设备」。
class NotePinStore {
  NotePinStore({SharedPreferences? preferences}) : _preferences = preferences;

  static const String storageKey = 'notes.pinned';

  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  /// 读取置顶集合；存储损坏时降级为空集合，不让列表崩溃。
  Future<Set<String>> load() async {
    try {
      final prefs = await _prefs;
      return (prefs.getStringList(storageKey) ?? const <String>[]).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> save(Set<String> ids) async {
    final prefs = await _prefs;
    await prefs.setStringList(storageKey, ids.toList(growable: false));
  }
}
