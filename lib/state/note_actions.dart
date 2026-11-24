import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/api_models.dart';
import '../../data/note_actions.dart';
import '../../data/note_repository.dart';
import '../../data/note_text_edits.dart';
import 'providers.dart';
import 'workspace.dart';

/// 笔记列表与编辑器共用的「单条笔记操作」。
///
/// 抽出来是为了让列表的⋯菜单、编辑器的⋯菜单、批量操作走**同一套语义**：
/// - 重命名：`title` 必改；正文首行是 `# 标题` 时同步改写（见 [NoteTextEdits]）；
/// - 移至笔记本：后端没有移动接口，用「复制 + 删除」实现，笔记 id 会变，
///   打开着的标签页必须改绑；
/// - 置顶：后端没有字段，只写本设备偏好（见 `PinnedNotesNotifier`）；
/// - 删除：硬删除，调用方负责二次确认。
///
/// 所有方法都只做「一次操作 + 必要的缓存失效」，**不弹任何 UI**，
/// 提示文案由调用方根据结果决定，避免数据层依赖 BuildContext。
class NoteActions {
  NoteActions(this._ref);

  final WidgetRef _ref;

  NoteRepository? get _repository => _ref.read(repositoryProvider);

  /// 重命名笔记。
  ///
  /// 同步改写正文首行标题会让正文内容变化，因此走 `PUT` 同时提交
  /// `title` 与 `content`；首行不是标题时只提交 `title`，正文一个字节不动。
  Future<RenameOutcome> rename(Note note, String title) async {
    final repository = _repository;
    if (repository == null) {
      throw const ApiException('尚未配置后端地址', kind: ApiErrorKind.badRequest);
    }
    final normalized = title.trim();
    if (normalized == note.title) {
      return RenameOutcome(note: note, headingUpdated: false);
    }
    // 列表接口可能不带正文，只改标题时不需要为了首行标题再拉一次正文。
    final headingUpdated =
        note.content.isNotEmpty && NoteTextEdits.hasHeadingFirstLine(note.content);
    final saved = await repository.updateNote(
      note.id,
      title: normalized,
      content: headingUpdated
          ? NoteTextEdits.renameFirstHeading(note.content, normalized)
          : null,
    );
    _invalidateLists();
    _syncTabTitle(saved);
    return RenameOutcome(note: saved, headingUpdated: headingUpdated);
  }

  /// 创建副本；副本放进 [notebookId] 指定的笔记本（null 表示不归属笔记本）。
  Future<Note> duplicate(Note note, {String? notebookId}) async {
    final repository = _repository;
    if (repository == null) {
      throw const ApiException('尚未配置后端地址', kind: ApiErrorKind.badRequest);
    }
    // 副本要完整正文：列表接口按笔记本过滤时不返回 content，先取详情。
    final source = note.content.isEmpty ? await repository.fetchNote(note.id) : note;
    final copy = await repository.createNote(
      title: '${source.displayTitle} 副本',
      content: source.content,
      noteType: source.isAi ? 'ai' : 'human',
      notebookId: notebookId,
    );
    _invalidateLists();
    return copy;
  }

  /// 把一条笔记移到目标笔记本（`null` = 不属于任何笔记本）。
  ///
  /// 返回的新笔记 id 与旧的不同：调用方要把已打开的标签页从 [note] 改绑到
  /// [MoveOutcome.note]。置顶状态跟随笔记一起迁移（否则移动后置顶会丢）。
  Future<MoveOutcome> move(Note note, {required String? targetNotebookId}) async {
    final repository = _repository;
    if (repository == null) {
      throw const ApiException('尚未配置后端地址', kind: ApiErrorKind.badRequest);
    }
    // 移动是「复制服务端正文 + 删除原笔记」：如果这篇笔记正在标签页里编辑，
    // 必须先落盘，否则未保存的修改会随删除一起丢掉。
    await _flushDirtyTabs(note.id);
    final moved = await repository.moveNote(
      note.id,
      targetNotebookId: targetNotebookId,
    );
    // 置顶跟人走：把旧 id 的置顶记录迁移到新 id。
    final pins = _ref.read(pinnedNotesProvider.notifier);
    final wasPinned = (_ref.read(pinnedNotesProvider).valueOrNull ?? const <String>{})
        .contains(note.id);
    await pins.remove(<String>[note.id]);
    if (wasPinned) await pins.setPinned(<String>[moved.id], pinned: true);

    _invalidateLists();
    _rebindTabs(note.id, moved.id, notebookId: targetNotebookId);
    return MoveOutcome(note: moved, sourceNoteId: note.id);
  }

  /// 置顶 / 取消置顶一组笔记（只写本设备偏好）。
  Future<void> setPinned(Iterable<String> noteIds, {required bool pinned}) {
    return _ref.read(pinnedNotesProvider.notifier).setPinned(noteIds, pinned: pinned);
  }

  /// 删除一组笔记，逐条请求并汇总失败数。
  ///
  /// 后端没有批量端点，只能是 N 次请求；部分失败时必须把失败数报给用户，
  /// 不能让「删了一半」看起来像成功。返回失败条数。
  Future<int> deleteAll(Iterable<String> noteIds) async {
    final repository = _repository;
    if (repository == null) {
      throw const ApiException('尚未配置后端地址', kind: ApiErrorKind.badRequest);
    }
    final ids = noteIds.toList(growable: false);
    var failed = 0;
    for (final id in ids) {
      try {
        await repository.deleteNote(id);
        // 删掉的笔记不应该继续置顶。
        await _ref.read(pinnedNotesProvider.notifier).remove(<String>[id]);
        _closeTabsForNote(id);
      } on ApiException {
        failed++;
      }
    }
    _invalidateLists();
    return failed;
  }

  /// 移动一组笔记到同一个目标笔记本，返回失败条数。
  Future<int> moveAll(
    Iterable<Note> notes, {
    required String? targetNotebookId,
  }) async {
    var failed = 0;
    for (final note in notes) {
      try {
        await move(note, targetNotebookId: targetNotebookId);
      } on ApiException {
        failed++;
      }
    }
    return failed;
  }

  /// 复制一组笔记，返回失败条数。
  Future<int> duplicateAll(
    Iterable<Note> notes, {
    required String? notebookId,
  }) async {
    var failed = 0;
    for (final note in notes) {
      try {
        await duplicate(note, notebookId: notebookId);
      } on ApiException {
        failed++;
      }
    }
    return failed;
  }

  /// 笔记列表 / 笔记本计数 / 全部笔记缓存统一失效。
  ///
  /// `notesProvider` 是 family：批量操作可能跨笔记本，只失效当前列表会留下脏数据，
  /// 因此直接失效整个 family。
  void _invalidateLists() {
    _ref.invalidate(allNotesProvider);
    _ref.invalidate(notebooksProvider);
    _ref.invalidate(notesProvider);
  }

  /// 重命名后同步标签条标题（已打开的笔记标签页）。
  void _syncTabTitle(Note note) {
    final workspace = _ref.read(workspaceProvider.notifier);
    final state = _ref.read(workspaceProvider);
    for (final tab in state.tabs) {
      if (tab.isNote && tab.targetId == note.id) {
        workspace.setTitle(tab.id, note.displayTitle);
      }
    }
  }

  /// 笔记 id 变化（移动 = 复制 + 删除）后，把已打开的标签页改绑到新 id，
  /// 避免标签页指向一条已删除的笔记。
  void _rebindTabs(String oldId, String newId, {String? notebookId}) {
    final workspace = _ref.read(workspaceProvider.notifier);
    final state = _ref.read(workspaceProvider);
    for (final tab in state.tabs) {
      if (!tab.isNote || tab.targetId != oldId) continue;
      workspace.rebindNoteId(
        tab.id,
        noteId: newId,
        notebookId: notebookId,
      );
    }
  }

  /// 关闭指向被删除笔记的全部标签页（编辑器自己删自己时由工作区处理，
  /// 这里是列表批量删除的路径，标签页里可能是未保存草稿，交由工作区关闭）。
  void _closeTabsForNote(String noteId) {
    _ref.read(workspaceProvider.notifier).closeTabsForNote(noteId);
  }

  /// 把这条笔记正在编辑的标签页先保存掉；保存失败则中止移动。
  ///
  /// 直接失败会比「悄悄丢掉用户刚写的段落」好：调用方会把异常转成提示。
  Future<void> _flushDirtyTabs(String noteId) async {
    final notifier = _ref.read(workspaceProvider.notifier);
    final tabs = _ref
        .read(workspaceProvider)
        .tabs
        .where((tab) => tab.isNote && tab.targetId == noteId);
    for (final tab in tabs) {
      final session = notifier.sessionOf(tab.id);
      if (session == null || !session.isDirty) continue;
      final saved = await session.save();
      if (!saved) {
        throw const ApiException(
          '笔记有未保存的修改且保存失败，已取消移动',
          kind: ApiErrorKind.unknown,
        );
      }
    }
  }
}
