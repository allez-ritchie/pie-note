import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/workspace.dart';
import '../common/layout.dart';
import '../common/strings.dart';
import '../notebooks/notebooks_screen.dart';
import '../notebooks/notes_screen.dart';
import '../notes/note_editor_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import 'desktop_tab_strip.dart';
import 'mobile_floating_bar.dart';
import 'mobile_tab_overview.dart';
import 'workspace_navigator.dart';
import 'workspace_strings.dart';

/// 多标签工作区外壳。
///
/// - **桌面 / 宽窗口**：左侧一级导航（笔记本 / 搜索 / 设置）+ 顶部标签条
///   （参考 VSCode / Obsidian 桌面端），标签可关闭、右键管理、快捷键切换；
/// - **手机 / 窄窗口**：页面铺满，底部悬浮胶囊工具栏（参考 Obsidian 移动端）
///   负责前进后退、搜索、新建、打开标签总览；滚动页面时自动隐藏、下划显示。
///
/// 标签页内容放在 [IndexedStack] 中常驻：切换标签不会丢失编辑草稿、搜索词
/// 或滚动位置。
class WorkspaceShell extends ConsumerStatefulWidget {
  const WorkspaceShell({super.key});

  @override
  ConsumerState<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends ConsumerState<WorkspaceShell> {
  /// 底部悬浮胶囊（56）+ 离底间距（12）+ 余量，避免挡住页面底部可点区域。
  static const double _floatingBarInset = 84;

  /// 移动端悬浮工具栏的显隐（由滚动方向驱动）。
  final FloatingBarController _barController = FloatingBarController();

  @override
  void initState() {
    super.initState();
    // 标签快捷键走全局键盘监听而不是 Focus 树：切换标签后焦点可能落在
    // 刚刚离屏的页面上，Focus 树里的 CallbackShortcuts 会失效。
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    // 首帧之后补一个「笔记本」标签页，避免在 build 期间改状态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(workspaceProvider.notifier)
          .ensureInitialTab(title: S.tabNotebooks);
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _barController.dispose();
    super.dispose();
  }

  /// 桌面标签快捷键：Ctrl/Cmd + W / T / Tab / 1..9。
  ///
  /// 只在按下（非重复）时触发，避免长按连续切页；组合键不参与文本输入，
  /// 因此不会影响编辑器里正常打字。
  bool _handleGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    final primary = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (!primary || keyboard.isAltPressed) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyW) {
      _closeActive();
      return true;
    }
    if (key == LogicalKeyboardKey.keyT) {
      _newNoteTab();
      return true;
    }
    if (key == LogicalKeyboardKey.tab) {
      _workspace.activateRelative(keyboard.isShiftPressed ? -1 : 1);
      return true;
    }
    final index = _digitIndexOf(key);
    if (index != null) {
      _workspace.activateIndex(index);
      return true;
    }
    return false;
  }

  WorkspaceNotifier get _workspace => ref.read(workspaceProvider.notifier);

  // ---------------------------------------------------------------------------
  // 关闭（含未保存确认）
  // ---------------------------------------------------------------------------

  /// 关闭一批标签页：先汇总未保存的编辑页，弹一次确认对话框。
  Future<void> _closeTabs(List<String> ids) async {
    final tabs = ref.read(workspaceProvider).tabs;
    final targets = <WorkspaceTab>[
      for (final tab in tabs)
        if (ids.contains(tab.id)) tab,
    ];
    if (targets.isEmpty) return;

    final dirty = <WorkspaceTab>[
      for (final tab in targets)
        if (_workspace.sessionOf(tab.id)?.isDirty ?? false) tab,
    ];
    if (dirty.isNotEmpty) {
      final action = await _confirmCloseDirty(dirty);
      if (action == null || action == _CloseAction.cancel) return;
      if (action == _CloseAction.save) {
        for (final tab in dirty) {
          final saved = await _workspace.sessionOf(tab.id)?.save() ?? true;
          if (!saved) return;
        }
      } else {
        for (final tab in dirty) {
          _workspace.sessionOf(tab.id)?.discardChanges();
        }
      }
    }
    for (final tab in targets) {
      _workspace.sessionOf(tab.id)?.discardChanges();
      _workspace.closeTab(tab.id);
    }
  }

  Future<_CloseAction?> _confirmCloseDirty(List<WorkspaceTab> dirty) {
    final title =
        dirty.length == 1 ? dirty.first.title : '${dirty.length} 个标签页';
    return showDialog<_CloseAction>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text(WorkspaceStrings.closeDirtyTitle),
            content: Text(WorkspaceStrings.closeDirtyMessage(title)),
            actions: [
              TextButton(
                onPressed:
                    () => Navigator.of(dialogContext).pop(_CloseAction.cancel),
                child: const Text(WorkspaceStrings.closeDirtyCancel),
              ),
              TextButton(
                onPressed:
                    () => Navigator.of(dialogContext).pop(_CloseAction.discard),
                child: const Text(WorkspaceStrings.closeWithoutSaving),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed:
                    () => Navigator.of(dialogContext).pop(_CloseAction.save),
                child: const Text(WorkspaceStrings.saveAndClose),
              ),
            ],
          ),
    );
  }

  /// 强制关闭（笔记已删除等场景）：不再询问未保存状态，直接丢弃草稿。
  void _forceCloseTabs(List<String> ids) {
    for (final id in ids) {
      _workspace.sessionOf(id)?.discardChanges();
      _workspace.closeTab(id);
    }
  }

  Future<void> _closeActive() async {
    final active = ref.read(workspaceProvider).activeId;
    if (active == null) return;
    await _closeTabs([active]);
  }

  void _newNoteTab() {
    final state = ref.read(workspaceProvider);
    final active = state.activeTab;
    // 在当前笔记所属笔记本 / 当前笔记列表里新建，保持上下文。
    final notebookId = switch (active?.kind) {
      WorkspaceTabKind.notes => active!.targetId,
      WorkspaceTabKind.note => active!.parentId,
      _ => null,
    };
    WorkspaceNavigator.openDraft(ref, notebookId: notebookId);
    _barController.show();
  }

  // ---------------------------------------------------------------------------
  // 标签页内容
  // ---------------------------------------------------------------------------

  Widget _buildTabBody(WorkspaceTab tab) {
    switch (tab.kind) {
      case WorkspaceTabKind.notebooks:
        return const NotebooksScreen();
      case WorkspaceTabKind.search:
        return const SearchScreen();
      case WorkspaceTabKind.settings:
        return const SettingsScreen();
      case WorkspaceTabKind.notes:
        return NotesScreen(
          key: ValueKey('notes-body-${tab.id}'),
          title: tab.title,
          notebookId: tab.targetId,
          showBackButton: false,
          padded: true,
          embedded: true,
        );
      case WorkspaceTabKind.note:
        return NoteEditorScreen(
          key: ValueKey('note-body-${tab.id}'),
          noteId: tab.targetId,
          notebookId: tab.parentId,
          tabId: tab.id,
          binding: WorkspaceTabBinding(
            onDirtyChanged: (dirty) => _workspace.setDirty(tab.id, dirty),
            onTitleChanged: (title) => _workspace.setTitle(tab.id, title),
            onPreviewChanged:
                (preview) => _workspace.setPreview(tab.id, preview),
            onSessionChanged:
                (session) => _workspace.bindSession(tab.id, session),
            onNoteSaved:
                (noteId) => _workspace.adoptNoteId(
                  tab.id,
                  noteId,
                  notebookId: tab.parentId,
                ),
            onRequestClose: () => _closeTabs([tab.id]),
            // 笔记已删除：无需再确认，直接关掉标签页。
            onClosed: () => _forceCloseTabs([tab.id]),
          ),
        );
    }
  }

  /// 只构建访问过的标签页，未访问的先用占位，避免一次打开多个编辑器就并发拉正文。
  Widget _buildStack(WorkspaceState state, Set<String> visited) {
    return IndexedStack(
      index: state.activeIndex,
      children: [
        for (final tab in state.tabs)
          KeyedSubtree(
            key: ValueKey('stack-${tab.id}'),
            child:
                visited.contains(tab.id)
                    ? _buildTabBody(tab)
                    : const SizedBox.shrink(),
          ),
      ],
    );
  }

  /// 已经构建过的标签页：只给访问过的标签页真正构建页面，
  /// 未访问的先用占位，避免一次打开多个编辑器时并发拉取正文。
  final Set<String> _visited = <String>{};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider);
    final active = state.activeTab;
    if (active != null) _visited.add(active.id);

    final body =
        state.isEmpty
            ? _EmptyWorkspace(
              onOpenNotebooks:
                  () => WorkspaceNavigator.openSection(
                    ref,
                    WorkspaceTabKind.notebooks,
                  ),
              onOpenSearch:
                  () => WorkspaceNavigator.openSection(
                    ref,
                    WorkspaceTabKind.search,
                  ),
              onNewNote: () => WorkspaceNavigator.openDraft(ref),
            )
            : _buildStack(state, _visited);

    // 手机 / Android 的系统返回键：工作区里先按标签页历史后退，
    // 没有可后退的历史时才交给系统（退出 App）。笔记标签页自己处理
    // 关闭（含未保存确认），这里不重复消费。
    final handleSystemBack =
        state.canGoBack && active?.kind != WorkspaceTabKind.note;

    return PopScope(
      canPop: !handleSystemBack,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !handleSystemBack) return;
        _workspace.goBack();
      },
      child:
          Responsive.useSideNavigation(context)
              ? _buildDesktop(state, body)
              : _buildMobile(state, body),
    );
  }

  Widget _buildDesktop(WorkspaceState state, Widget body) {
    final activeKind = state.activeTab?.kind;
    final railIndex = switch (activeKind) {
      WorkspaceTabKind.search => 1,
      WorkspaceTabKind.settings => 2,
      WorkspaceTabKind.notebooks => 0,
      _ => 0,
    };
    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            right: false,
            child: NavigationRail(
              selectedIndex: railIndex,
              onDestinationSelected: (index) {
                final kind = switch (index) {
                  0 => WorkspaceTabKind.notebooks,
                  1 => WorkspaceTabKind.search,
                  _ => WorkspaceTabKind.settings,
                };
                WorkspaceNavigator.openSection(ref, kind);
              },
              labelType: NavigationRailLabelType.all,
              leading: const _RailBrand(),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder_rounded),
                  label: Text(S.tabNotebooks),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.search_rounded),
                  selectedIcon: Icon(Icons.search_rounded),
                  label: Text(S.tabSearch),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: Text(S.tabSettings),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                DesktopTabStrip(
                  tabs: state.tabs,
                  activeId: state.activeId,
                  onActivate: _workspace.activate,
                  onClose: (id) => _closeTabs([id]),
                  onCloseOthers:
                      (id) => _closeTabs([
                        for (final tab in state.tabs)
                          if (tab.id != id) tab.id,
                      ]),
                  onCloseToRight: (id) {
                    final index = state.tabs.indexWhere((tab) => tab.id == id);
                    if (index < 0) return;
                    _closeTabs([
                      for (final tab in state.tabs.skip(index + 1)) tab.id,
                    ]);
                  },
                  onCloseAll:
                      () => _closeTabs([for (final tab in state.tabs) tab.id]),
                  onNewNote: _newNoteTab,
                ),
                const Divider(height: 1),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile(WorkspaceState state, Widget body) {
    return Scaffold(
      body: Stack(
        children: [
          // 滚动通知驱动悬浮工具栏：上划（内容向下滚动）隐藏，下划显示。
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.depth != 0) return false;
                _barController.handleScroll(notification);
                return false;
              },
              // 给底部胶囊让出空间：正文、编辑器工具条都不会被盖住。
              child: Padding(
                padding: const EdgeInsets.only(bottom: _floatingBarInset),
                child: body,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MobileFloatingBar(
              controller: _barController,
              tabCount: state.tabs.length,
              canGoBack: state.canGoBack,
              canGoForward: state.canGoForward,
              onBack: _workspace.goBack,
              onForward: _workspace.goForward,
              onSearch:
                  () => WorkspaceNavigator.openSection(
                    ref,
                    WorkspaceTabKind.search,
                  ),
              onNewNote: _newNoteTab,
              onTabs: () => _openTabOverview(state),
              onMenu: () => _showMobileMenu(state),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openTabOverview(WorkspaceState state) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder:
            (_) => MobileTabOverview(
              onActivate: (id) {
                _workspace.activate(id);
                Navigator.of(context).pop();
              },
              onClose: (id) => _closeTabs([id]),
              onNewNote: () {
                Navigator.of(context).pop();
                _newNoteTab();
              },
            ),
      ),
    );
  }

  Future<void> _showMobileMenu(WorkspaceState state) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: const Text(S.tabNotebooks),
                  onTap: () => Navigator.of(sheetContext).pop('notebooks'),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_rounded),
                  title: const Text(S.tabSettings),
                  onTap: () => Navigator.of(sheetContext).pop('settings'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.close_rounded),
                  title: const Text(WorkspaceStrings.closeCurrent),
                  enabled: state.hasTabs,
                  onTap: () => Navigator.of(sheetContext).pop('close'),
                ),
                ListTile(
                  leading: const Icon(Icons.layers_clear_rounded),
                  title: const Text(WorkspaceStrings.closeAll),
                  enabled: state.hasTabs,
                  onTap: () => Navigator.of(sheetContext).pop('closeAll'),
                ),
              ],
            ),
          ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'notebooks':
        WorkspaceNavigator.openSection(ref, WorkspaceTabKind.notebooks);
      case 'settings':
        WorkspaceNavigator.openSection(ref, WorkspaceTabKind.settings);
      case 'close':
        await _closeActive();
      case 'closeAll':
        await _closeTabs([for (final tab in state.tabs) tab.id]);
    }
  }
}

enum _CloseAction { save, discard, cancel }

/// `Ctrl/Cmd + 1..9` 对应的标签页下标（数字键含小键盘）。
int? _digitIndexOf(LogicalKeyboardKey key) {
  final digits = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.digit1: 0,
    LogicalKeyboardKey.digit2: 1,
    LogicalKeyboardKey.digit3: 2,
    LogicalKeyboardKey.digit4: 3,
    LogicalKeyboardKey.digit5: 4,
    LogicalKeyboardKey.digit6: 5,
    LogicalKeyboardKey.digit7: 6,
    LogicalKeyboardKey.digit8: 7,
    LogicalKeyboardKey.digit9: 8,
    LogicalKeyboardKey.numpad1: 0,
    LogicalKeyboardKey.numpad2: 1,
    LogicalKeyboardKey.numpad3: 2,
    LogicalKeyboardKey.numpad4: 3,
    LogicalKeyboardKey.numpad5: 4,
    LogicalKeyboardKey.numpad6: 5,
    LogicalKeyboardKey.numpad7: 6,
    LogicalKeyboardKey.numpad8: 7,
    LogicalKeyboardKey.numpad9: 8,
  };
  return digits[key];
}

/// 空工作区：没有任何标签页时的引导页。
class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace({
    required this.onOpenNotebooks,
    required this.onOpenSearch,
    required this.onNewNote,
  });

  final VoidCallback onOpenNotebooks;
  final VoidCallback onOpenSearch;
  final VoidCallback onNewNote;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.tab_rounded,
                  size: 34,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                WorkspaceStrings.emptyTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                WorkspaceStrings.emptyMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: onOpenNotebooks,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text(WorkspaceStrings.openNotebooks),
                  ),
                  OutlinedButton.icon(
                    onPressed: onOpenSearch,
                    icon: const Icon(Icons.search_rounded),
                    label: const Text(WorkspaceStrings.openSearch),
                  ),
                  FilledButton.icon(
                    onPressed: onNewNote,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text(WorkspaceStrings.newTab),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 侧边栏顶部的品牌标记。
class _RailBrand extends StatelessWidget {
  const _RailBrand();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.tertiary],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.edit_note_rounded,
              size: 24,
              color: scheme.onPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            S.appName,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
