import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pie_note/state/workspace.dart';

/// 直接驱动 [WorkspaceNotifier]，不依赖 widget 树。
///
/// 用 [ProviderContainer] 拿到 notifier，模拟「打开页面 → 切标签 → 关闭」的
/// 调用序列，验证标签页、激活项与前进后退历史的纯逻辑。
void main() {
  late ProviderContainer container;
  late WorkspaceNotifier workspace;
  late List<WorkspaceState> states;

  setUp(() {
    container = ProviderContainer();
    workspace = container.read(workspaceProvider.notifier);
    states = [];
    container.listen<WorkspaceState>(
      workspaceProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
  });

  tearDown(() => container.dispose());

  WorkspaceState current() => container.read(workspaceProvider);

  test('初始为空，ensureInitialTab 只补一次「笔记本」标签页', () {
    expect(current().tabs, isEmpty);
    expect(current().activeId, isNull);

    workspace.ensureInitialTab(title: '笔记本');
    workspace.ensureInitialTab(title: '笔记本');

    expect(current().tabs, hasLength(1));
    expect(current().tabs.single.kind, WorkspaceTabKind.notebooks);
    expect(current().activeId, current().tabs.single.id);
  });

  test('打开同一条笔记复用已有标签页，不重复创建', () {
    workspace.ensureInitialTab(title: '笔记本');
    final first = workspace.openNote(
      noteId: 'note:1',
      title: '第一篇',
      notebookId: 'notebook:a',
    );
    workspace.openSection(WorkspaceTabKind.search, title: '搜索');

    final again = workspace.openNote(
      noteId: 'note:1',
      title: '第一篇',
      notebookId: 'notebook:a',
    );

    expect(again, first);
    expect(current().tabs.where((tab) => tab.isNote), hasLength(1));
    expect(current().activeId, first);
  });

  test('不同笔记会各开一个标签页，草稿笔记可以重复创建', () {
    final a = workspace.openDraft(title: '新建笔记');
    final b = workspace.openDraft(title: '新建笔记');
    final c = workspace.openNote(noteId: 'note:1', title: '第一篇');

    expect({a, b, c}, hasLength(3));
    expect(current().tabs, hasLength(3));
    expect(current().activeId, c);
    // 新标签页插在末尾，草稿没有 targetId。
    expect(current().tabs[0].targetId, isNull);
    expect(current().tabs[1].targetId, isNull);
  });

  test('笔记列表按 notebookId 复用：全部笔记与具体笔记本是不同标签页', () {
    final all = workspace.openNotes(title: '全部笔记');
    final notebook = workspace.openNotes(
      notebookId: 'notebook:a',
      title: '工作记录',
    );
    final allAgain = workspace.openNotes(title: '全部笔记');

    expect(allAgain, all);
    expect(notebook, isNot(all));
    expect(current().tabs, hasLength(2));
  });

  test('关闭当前标签页时优先激活右侧邻居，没有右侧则回到左侧', () {
    final a = workspace.openSection(WorkspaceTabKind.notebooks, title: '笔记本');
    final b = workspace.openSection(WorkspaceTabKind.search, title: '搜索');
    final c = workspace.openSection(WorkspaceTabKind.settings, title: '设置');
    expect(current().activeId, c);

    workspace.closeTab(c);
    expect(current().activeId, b, reason: '关闭最右侧后应回到左侧邻居');

    workspace.activate(a);
    workspace.closeTab(a);
    expect(current().activeId, b, reason: '关闭左侧标签后应右移');
  });

  test('关闭全部标签页后工作区为空', () {
    final a = workspace.openSection(WorkspaceTabKind.notebooks, title: '笔记本');
    final b = workspace.openSection(WorkspaceTabKind.search, title: '搜索');

    workspace.closeTabs([a, b]);

    expect(current().tabs, isEmpty);
    expect(current().activeId, isNull);
  });

  test('关闭其他 / 关闭右侧只保留预期标签页', () {
    final a = workspace.openSection(WorkspaceTabKind.notebooks, title: '笔记本');
    workspace.openSection(WorkspaceTabKind.search, title: '搜索');
    workspace.openSection(WorkspaceTabKind.settings, title: '设置');

    // 关闭 a 右侧的标签页：只剩 a。
    workspace.closeToRight(a);
    expect(current().tabs.map((tab) => tab.id), [a]);

    // 重新开两个，再验证「关闭其他」。
    workspace.openSection(WorkspaceTabKind.search, title: '搜索');
    workspace.openSection(WorkspaceTabKind.settings, title: '设置');
    workspace.closeOthers(a);
    expect(current().tabs.map((tab) => tab.id), [a]);
    expect(current().activeId, a);
  });

  test('后退 / 前进在标签页之间往返，且新开标签页会清空前进栈', () {
    final a = workspace.openSection(WorkspaceTabKind.notebooks, title: '笔记本');
    final b = workspace.openSection(WorkspaceTabKind.search, title: '搜索');
    expect(current().activeId, b);

    workspace.goBack();
    expect(current().activeId, a);
    expect(current().canGoForward, isTrue);

    workspace.goForward();
    expect(current().activeId, b);

    workspace.goBack();
    workspace.openSection(WorkspaceTabKind.settings, title: '设置');
    expect(current().canGoForward, isFalse, reason: '新开标签页后不应再能前进');
  });

  test('后退历史里被关闭的标签页会被跳过', () {
    final a = workspace.openSection(WorkspaceTabKind.notebooks, title: '笔记本');
    final b = workspace.openSection(WorkspaceTabKind.search, title: '搜索');

    workspace.activate(a);
    workspace.closeTab(b);

    workspace.goBack();
    expect(current().activeId, a);
    expect(current().canGoBack, isFalse);
  });

  test('相对切换在首尾之间循环，按下标激活越界时忽略', () {
    final a = workspace.openSection(WorkspaceTabKind.notebooks, title: '笔记本');
    final b = workspace.openSection(WorkspaceTabKind.search, title: '搜索');
    final c = workspace.openSection(WorkspaceTabKind.settings, title: '设置');
    expect(current().activeId, c);

    workspace.activateRelative(1);
    expect(current().activeId, a, reason: '最后一个往后切应回到第一个');

    workspace.activateRelative(-1);
    expect(current().activeId, c);

    workspace.activateIndex(1);
    expect(current().activeId, b);

    workspace.activateIndex(9);
    expect(current().activeId, b, reason: '越界下标不改激活页');
  });

  test('标签标题、脏标记、摘要同步，空标题不会覆盖已有标题', () {
    final id = workspace.openNote(noteId: 'note:1', title: '旧标题');

    workspace.setTitle(id, '新标题');
    expect(current().tabOf(id)!.title, '新标题');

    workspace.setTitle(id, '   ');
    expect(current().tabOf(id)!.title, '新标题', reason: '空标题应被忽略');

    workspace.setDirty(id, true);
    expect(current().tabOf(id)!.dirty, isTrue);

    workspace.setPreview(id, '正文摘要');
    expect(current().tabOf(id)!.preview, '正文摘要');
  });

  test('新建笔记保存后把草稿标签页绑定到真实笔记 id', () {
    final draft = workspace.openDraft(title: '新建笔记');
    workspace.adoptNoteId(draft, 'note:new', notebookId: 'notebook:a');

    final tab = current().tabOf(draft)!;
    expect(tab.targetId, 'note:new');
    expect(tab.parentId, 'notebook:a');

    // 再次打开同一条笔记时应复用这个标签页，而不是新建。
    final reopened = workspace.openNote(noteId: 'note:new', title: '新笔记');
    expect(reopened, draft);
  });

  test('笔记被删除后关闭指向它的全部标签页', () {
    workspace.openNote(noteId: 'note:1', title: '第一篇');
    workspace.openNote(noteId: 'note:1', title: '第一篇');
    final other = workspace.openNote(noteId: 'note:2', title: '第二篇');

    // 同一笔记只会有一个标签页，额外造一个「同 noteId 不同标签」的场景。
    workspace.closeTabsForNote('note:1');

    expect(current().tabs.where((tab) => tab.targetId == 'note:1'), isEmpty);
    expect(current().tabOf(other), isNotNull);
  });

  test('会话注册与注销用于关闭前的未保存确认', () {
    final id = workspace.openNote(noteId: 'note:1', title: '第一篇');
    final session = _FakeSession(dirty: true);

    workspace.bindSession(id, session);
    expect(workspace.sessionOf(id), same(session));

    workspace.closeTab(id);
    expect(workspace.sessionOf(id), isNull, reason: '关闭标签页时注销会话');
  });
}

class _FakeSession implements WorkspaceTabSession {
  _FakeSession({required this.dirty});

  bool dirty;

  @override
  bool get isDirty => dirty;

  @override
  Future<bool> save() async {
    dirty = false;
    return true;
  }

  @override
  void discardChanges() {
    dirty = false;
  }
}
