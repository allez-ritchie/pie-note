import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 工作区标签页的类型。
///
/// 参考 Obsidian / VSCode：一级页面（笔记本、搜索、设置）与文档（笔记）
/// 都是标签页，由 [WorkspaceNotifier] 统一管理打开、激活、关闭与前进后退。
enum WorkspaceTabKind { notebooks, search, settings, notes, note }

/// 一个打开的标签页。
@immutable
class WorkspaceTab {
  const WorkspaceTab({
    required this.id,
    required this.kind,
    required this.title,
    this.targetId,
    this.parentId,
    this.dirty = false,
    this.preview = '',
  });

  /// 标签页自身的稳定 id（不随文档落盘而改变，用来保持页面 State）。
  final String id;

  final WorkspaceTabKind kind;

  /// 标签条 / 总览里展示的标题。
  final String title;

  /// 目标 id：笔记页存 `note:<id>`，笔记列表页存 `notebook:<id>`（全部笔记为 null）。
  final String? targetId;

  /// 归属笔记本：笔记页新建笔记、保存后刷新列表时使用。
  final String? parentId;

  /// 是否存在未保存修改（由编辑页同步）。
  final bool dirty;

  /// 总览卡片里的预览文本（笔记正文摘要）。
  final String preview;

  bool get isNote => kind == WorkspaceTabKind.note;

  bool get isSection =>
      kind == WorkspaceTabKind.notebooks ||
      kind == WorkspaceTabKind.search ||
      kind == WorkspaceTabKind.settings;

  WorkspaceTab copyWith({
    String? title,
    String? targetId,
    String? parentId,
    bool? dirty,
    String? preview,
  }) {
    return WorkspaceTab(
      id: id,
      kind: kind,
      title: title ?? this.title,
      targetId: targetId ?? this.targetId,
      parentId: parentId ?? this.parentId,
      dirty: dirty ?? this.dirty,
      preview: preview ?? this.preview,
    );
  }
}

/// 工作区状态：标签页列表、当前激活页与前进 / 后退历史。
@immutable
class WorkspaceState {
  const WorkspaceState({
    this.tabs = const <WorkspaceTab>[],
    this.activeId,
    this.backStack = const <String>[],
    this.forwardStack = const <String>[],
  });

  final List<WorkspaceTab> tabs;
  final String? activeId;

  /// 后退 / 前进历史里只存标签页 id，关闭标签页时同步清理。
  final List<String> backStack;
  final List<String> forwardStack;

  bool get hasTabs => tabs.isNotEmpty;

  bool get isEmpty => tabs.isEmpty;

  WorkspaceTab? get activeTab {
    final id = activeId;
    if (id == null) return null;
    for (final tab in tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  /// 当前激活页在 [tabs] 中的下标；没有激活页时为 0。
  int get activeIndex {
    final id = activeId;
    if (id == null) return 0;
    final index = tabs.indexWhere((tab) => tab.id == id);
    return index < 0 ? 0 : index;
  }

  WorkspaceTab? tabOf(String id) {
    for (final tab in tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  bool get canGoBack => backStack.any((id) => tabOf(id) != null);

  bool get canGoForward => forwardStack.any((id) => tabOf(id) != null);
}

/// 编辑类标签页向工作区暴露的会话接口。
///
/// 关闭标签页时，工作区先问 [isDirty]，需要时调用 [save] / [discardChanges]，
/// 从而把「未保存拦截」从页面的 Navigator 退出逻辑里解耦出来。
abstract interface class WorkspaceTabSession {
  bool get isDirty;

  /// 保存成功返回 true；失败返回 false（页面自行提示错误）。
  Future<bool> save();

  /// 放弃改动（标签页随后会被销毁）。
  void discardChanges();
}

/// 工作区与标签页页面之间的回调绑定。
///
/// 编辑页通过它把标题、脏标记、预览同步到标签条，并接收「关闭」请求；
/// 页面本身不依赖 Riverpod，单独推入路由（[NoteEditorScreen] 的旧用法）时传 null。
@immutable
class WorkspaceTabBinding {
  const WorkspaceTabBinding({
    this.onDirtyChanged,
    this.onTitleChanged,
    this.onPreviewChanged,
    this.onSessionChanged,
    this.onNoteSaved,
    this.onRequestClose,
    this.onClosed,
  });

  /// 未保存状态变化。
  final ValueChanged<bool>? onDirtyChanged;

  /// 展示标题变化（标题输入框、正文首行兜底等）。
  final ValueChanged<String>? onTitleChanged;

  /// 正文摘要变化（加载完成、保存成功时），用于移动端标签总览的预览卡片。
  final ValueChanged<String>? onPreviewChanged;

  /// 会话注册 / 注销，关闭标签页时工作区用它询问未保存状态。
  final ValueChanged<WorkspaceTabSession?>? onSessionChanged;

  /// 新建笔记首次保存成功后回传笔记 id，使标签页与笔记建立稳定绑定。
  final ValueChanged<String>? onNoteSaved;

  /// 请求关闭标签页（带未保存确认）。
  final VoidCallback? onRequestClose;

  /// 立即关闭标签页（例如笔记已删除，无需再确认）。
  final VoidCallback? onClosed;
}

/// 工作区控制器：标签页的打开、激活、关闭与历史前进 / 后退。
///
/// 只保存标签页元数据；页面 State 由外壳的 [IndexedStack] 保活，
/// 编辑中的草稿、滚动位置在切换标签页时不会丢失。
class WorkspaceNotifier extends Notifier<WorkspaceState> {
  int _sequence = 0;
  final Map<String, WorkspaceTabSession> _sessions = {};

  @override
  WorkspaceState build() => const WorkspaceState();

  String _nextId() => 'tab-${++_sequence}';

  /// 启动后确保至少有一个「笔记本」标签页。
  void ensureInitialTab({required String title}) {
    if (state.tabs.isNotEmpty) return;
    _insert(
      WorkspaceTab(
        id: _nextId(),
        kind: WorkspaceTabKind.notebooks,
        title: title,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 打开
  // ---------------------------------------------------------------------------

  /// 打开一级页面（笔记本 / 搜索 / 设置），已有则激活。
  String openSection(WorkspaceTabKind kind, {required String title}) {
    assert(
      kind == WorkspaceTabKind.notebooks ||
          kind == WorkspaceTabKind.search ||
          kind == WorkspaceTabKind.settings,
      'openSection 只接受一级页面标签',
    );
    for (final tab in state.tabs) {
      if (tab.kind == kind) return _activate(tab.id);
    }
    return _insert(WorkspaceTab(id: _nextId(), kind: kind, title: title));
  }

  /// 打开某个笔记本的笔记列表；[notebookId] 为 null 表示「全部笔记」。
  String openNotes({String? notebookId, required String title}) {
    for (final tab in state.tabs) {
      if (tab.kind == WorkspaceTabKind.notes && tab.targetId == notebookId) {
        return _activate(tab.id);
      }
    }
    return _insert(
      WorkspaceTab(
        id: _nextId(),
        kind: WorkspaceTabKind.notes,
        title: title,
        targetId: notebookId,
      ),
    );
  }

  /// 打开一条笔记；已经打开时直接切到那个标签页（Obsidian 的默认行为）。
  String openNote({
    required String noteId,
    required String title,
    String? notebookId,
  }) {
    for (final tab in state.tabs) {
      if (tab.kind == WorkspaceTabKind.note && tab.targetId == noteId) {
        return _activate(tab.id);
      }
    }
    return _insert(
      WorkspaceTab(
        id: _nextId(),
        kind: WorkspaceTabKind.note,
        title: title,
        targetId: noteId,
        parentId: notebookId,
      ),
    );
  }

  /// 新建一条草稿笔记（每次都是独立标签页，保存后自动绑定到笔记 id）。
  String openDraft({String? notebookId, required String title}) {
    return _insert(
      WorkspaceTab(
        id: _nextId(),
        kind: WorkspaceTabKind.note,
        title: title,
        parentId: notebookId,
      ),
    );
  }

  String _insert(WorkspaceTab tab) {
    final previous = state.activeId;
    state = WorkspaceState(
      tabs: [...state.tabs, tab],
      activeId: tab.id,
      backStack:
          previous == null ? state.backStack : [...state.backStack, previous],
      forwardStack: const <String>[],
    );
    return tab.id;
  }

  // ---------------------------------------------------------------------------
  // 激活与前进 / 后退
  // ---------------------------------------------------------------------------

  String _activate(String id) {
    if (state.activeId == id) return id;
    final previous = state.activeId;
    state = WorkspaceState(
      tabs: state.tabs,
      activeId: id,
      backStack:
          previous == null ? state.backStack : [...state.backStack, previous],
      forwardStack: const <String>[],
    );
    return id;
  }

  /// 激活标签页（历史前进后退、标签条点击、总览点击共用）。
  void activate(String id) {
    if (state.tabOf(id) == null) return;
    _activate(id);
  }

  /// 键盘 / 手势切换：在标签页之间循环。
  void activateRelative(int delta) {
    if (state.tabs.isEmpty || delta == 0) return;
    final total = state.tabs.length;
    final next = (state.activeIndex + delta) % total;
    _activate(state.tabs[(next + total) % total].id);
  }

  /// 按下标激活（`Ctrl/Cmd + 1..9` 用）。
  void activateIndex(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    _activate(state.tabs[index].id);
  }

  void goBack() {
    final target = _popExisting(state.backStack);
    if (target == null) return;
    _go(target.id, rest: target.rest, pushForward: state.activeId);
  }

  void goForward() {
    final target = _popExisting(state.forwardStack);
    if (target == null) return;
    _go(target.id, rest: target.rest, pushBack: state.activeId);
  }

  void _go(
    String id, {
    required List<String> rest,
    String? pushBack,
    String? pushForward,
  }) {
    final back =
        pushBack == null ? state.backStack : [...state.backStack, pushBack];
    final forward =
        pushForward == null
            ? state.forwardStack
            : [pushForward, ...state.forwardStack];
    state = WorkspaceState(
      tabs: state.tabs,
      activeId: id,
      backStack: pushBack == null ? rest : back,
      forwardStack: pushForward == null ? rest : forward,
    );
  }

  /// 从历史栈尾部取出仍然存在的标签页 id，顺带丢掉已关闭页面的记录。
  ({String id, List<String> rest})? _popExisting(List<String> stack) {
    final rest = <String>[];
    for (var i = stack.length - 1; i >= 0; i--) {
      final id = stack[i];
      if (state.tabOf(id) != null) {
        rest.addAll(stack.take(i));
        return (id: id, rest: rest);
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 关闭
  // ---------------------------------------------------------------------------

  /// 关闭一个标签页；若关闭的是当前页，优先激活右侧邻居，没有则左侧。
  void closeTab(String id) {
    final index = state.tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return;
    final tabs = [...state.tabs]..removeAt(index);
    var activeId = state.activeId;
    if (activeId == id) {
      activeId =
          tabs.isEmpty
              ? null
              : tabs[index < tabs.length ? index : tabs.length - 1].id;
    }
    _sessions.remove(id);
    state = WorkspaceState(
      tabs: tabs,
      activeId: activeId,
      backStack: _without(state.backStack, id),
      forwardStack: _without(state.forwardStack, id),
    );
  }

  /// 关闭给定 id 中仍然存在的标签页（关闭其他 / 右侧 / 全部）。
  void closeTabs(Iterable<String> ids) {
    for (final id in ids.toList(growable: false)) {
      closeTab(id);
    }
  }

  /// 关闭指向某条笔记的全部标签页（笔记被删除后调用）。
  void closeTabsForNote(String noteId) {
    final ids = state.tabs
        .where(
          (tab) => tab.kind == WorkspaceTabKind.note && tab.targetId == noteId,
        )
        .map((tab) => tab.id)
        .toList(growable: false);
    closeTabs(ids);
  }

  /// 关闭当前标签页右侧的全部标签页。
  void closeToRight(String id) {
    final index = state.tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return;
    closeTabs(state.tabs.skip(index + 1).map((tab) => tab.id));
  }

  /// 关闭除 [id] 之外的全部标签页。
  void closeOthers(String id) {
    closeTabs(state.tabs.where((tab) => tab.id != id).map((tab) => tab.id));
  }

  // ---------------------------------------------------------------------------
  // 会话与标签元数据同步
  // ---------------------------------------------------------------------------

  void bindSession(String tabId, WorkspaceTabSession? session) {
    if (session == null) {
      _sessions.remove(tabId);
    } else {
      _sessions[tabId] = session;
    }
  }

  WorkspaceTabSession? sessionOf(String tabId) => _sessions[tabId];

  void setDirty(String id, bool dirty) {
    final tab = state.tabOf(id);
    if (tab == null || tab.dirty == dirty) return;
    _replace(tab.copyWith(dirty: dirty));
  }

  void setTitle(String id, String title) {
    final tab = state.tabOf(id);
    if (tab == null) return;
    final normalized = title.trim().isEmpty ? tab.title : title.trim();
    if (tab.title == normalized) return;
    _replace(tab.copyWith(title: normalized));
  }

  void setPreview(String id, String preview) {
    final tab = state.tabOf(id);
    if (tab == null || tab.preview == preview) return;
    _replace(tab.copyWith(preview: preview));
  }

  /// 新建笔记保存成功：把草稿标签页绑定到真实笔记 id，并记录所属笔记本。
  void adoptNoteId(String tabId, String noteId, {String? notebookId}) {
    final tab = state.tabOf(tabId);
    if (tab == null) return;
    _replace(tab.copyWith(targetId: noteId, parentId: notebookId));
  }

  void _replace(WorkspaceTab tab) {
    state = WorkspaceState(
      tabs: [
        for (final current in state.tabs) current.id == tab.id ? tab : current,
      ],
      activeId: state.activeId,
      backStack: state.backStack,
      forwardStack: state.forwardStack,
    );
  }

  static List<String> _without(List<String> source, String id) =>
      source.where((value) => value != id).toList(growable: false);
}

final workspaceProvider = NotifierProvider<WorkspaceNotifier, WorkspaceState>(
  WorkspaceNotifier.new,
);
