import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_models.dart';
import '../../state/note_actions.dart';
import '../../state/providers.dart';
import '../../state/workspace.dart';
import '../common/formatters.dart';
import '../common/layout.dart';
import '../common/navigation.dart';
import '../common/strings.dart';
import '../common/widgets.dart';
import '../home/workspace_navigator.dart';
import 'move_to_notebook_dialog.dart';
import 'notes_strings.dart';

enum _NoteSort { updated, created, title }

/// 单条笔记的⋯菜单项。
enum _NoteAction { rename, move, pin, duplicate, delete }

/// 列表里的一行：分节标题或笔记卡片。
sealed class _ListEntry {
  const _ListEntry();
}

class _HeaderEntry extends _ListEntry {
  const _HeaderEntry(this.title);

  final String title;
}

class _NoteEntry extends _ListEntry {
  const _NoteEntry(this.note);

  final Note note;
}

/// 某个笔记本下的笔记列表；[notebookId] 为 null 表示全部笔记。
///
/// 窄屏作为二级页面推入（带返回键）；宽屏由 [NotebooksScreen] 的双栏布局
/// 直接嵌在右侧，此时用 [showBackButton] 去掉返回键、用 [padded] 收敛内容宽度。
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({
    super.key,
    required this.title,
    this.notebookId,
    this.showBackButton = true,
    this.padded = false,
    this.embedded = false,
  });

  final String title;
  final String? notebookId;

  /// 是否显示返回按钮（双栏内嵌时为 false）。
  final bool showBackButton;

  /// 是否限制内容最大宽度并居中（桌面宽窗口可读性更好）。
  final bool padded;

  /// 是否作为工作区标签页嵌入：打开笔记 / 新建笔记改为操作标签页。
  final bool embedded;

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final TextEditingController _filterController = TextEditingController();
  _NoteSort _sort = _NoteSort.updated;
  String _filter = '';

  /// 多选状态。只存 id：列表刷新后仍然对得上，已消失的 id 在构建时被过滤。
  final Set<String> _selected = <String>{};
  bool _selectionMode = false;
  bool _busy = false;

  /// Shift 连选的起点（上一次点选的笔记 id）。
  String? _anchorId;

  late final NoteActions _actions = NoteActions(ref);

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _invalidateLists() {
    ref.invalidate(notesProvider(widget.notebookId));
    ref.invalidate(allNotesProvider);
    ref.invalidate(notebooksProvider);
  }

  void _showSnack(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  Future<void> _openNote(Note note) async {
    if (widget.embedded) {
      // 已打开的笔记会切到原标签页；列表在切回本页时自动刷新（见 build）。
      WorkspaceNavigator.openNote(
        ref,
        noteId: note.id,
        title: note.displayTitle,
        notebookId: widget.notebookId,
      );
      return;
    }
    final changed = await AppNavigator.openEditor(context, noteId: note.id);
    if (changed == true) _invalidateLists();
  }

  Future<void> _createNote() async {
    if (widget.embedded) {
      WorkspaceNavigator.openDraft(ref, notebookId: widget.notebookId);
      return;
    }
    final changed = await AppNavigator.openEditor(
      context,
      notebookId: widget.notebookId,
    );
    if (changed == true) _invalidateLists();
  }

  // ---------------------------------------------------------------------------
  // 单条笔记操作（⋯ 菜单）
  // ---------------------------------------------------------------------------

  Future<void> _handleAction(Note note, _NoteAction action) async {
    switch (action) {
      case _NoteAction.rename:
        await _renameNote(note);
      case _NoteAction.move:
        await _moveNote(note);
      case _NoteAction.pin:
        await _togglePin(<Note>[note]);
      case _NoteAction.duplicate:
        await _duplicateNote(note);
      case _NoteAction.delete:
        await _deleteNotes(<Note>[note]);
    }
  }

  Future<void> _renameNote(Note note) async {
    final initial = note.title.trim().isEmpty ? note.displayTitle : note.title;
    final title = await showTextInputDialog(
      context,
      title: NotesStrings.renameTitle,
      initialValue: initial,
      hintText: NotesStrings.renameHint,
      confirmLabel: S.save,
    );
    if (title == null || !mounted) return;
    if (title.trim() == note.title.trim()) return;
    try {
      final outcome = await _actions.rename(note, title);
      _showSnack(
        outcome.headingUpdated
            ? '${NotesStrings.renamedToast}（正文标题行已同步）'
            : NotesStrings.renamedToast,
      );
    } catch (error) {
      _showSnack('${NotesStrings.renameFailed}：${describeError(error)}');
    }
  }

  Future<MoveTarget?> _pickMoveTarget({required List<Note> notes}) {
    return showMoveToNotebookDialog(
      context,
      currentNotebookId: widget.notebookId,
    );
  }

  Future<void> _moveNote(Note note) async {
    final target = await _pickMoveTarget(notes: <Note>[note]);
    if (target == null || !mounted) return;
    if (target.notebookId == widget.notebookId) {
      // 源列表就是目标笔记本：后端无法「原地移动」，这里直接忽略。
      _showSnack(NotesStrings.moveSameNotebookHint);
      return;
    }
    await _runBusy(() async {
      try {
        await _actions.move(note, targetNotebookId: target.notebookId);
        _showSnack(NotesStrings.movedToToast(target.label));
      } catch (error) {
        _showSnack('${NotesStrings.moveFailed}：${describeError(error)}');
      }
    });
  }

  Future<void> _duplicateNote(Note note) async {
    await _runBusy(() async {
      try {
        await _actions.duplicate(note, notebookId: widget.notebookId);
        _showSnack(NotesStrings.duplicateToast);
      } catch (error) {
        _showSnack('${NotesStrings.duplicateFailed}：${describeError(error)}');
      }
    });
  }

  /// 置顶 / 取消置顶：全部已置顶则取消，否则统一置顶。
  Future<void> _togglePin(List<Note> notes) async {
    if (notes.isEmpty) return;
    final pinned = ref.read(pinnedNotesProvider).valueOrNull ?? const <String>{};
    final allPinned = notes.every((note) => pinned.contains(note.id));
    await _actions.setPinned(
      notes.map((note) => note.id),
      pinned: !allPinned,
    );
    if (!mounted) return;
    final shown = _effectiveSelection(notes);
    if (shown.isEmpty) return; // 批量操作后被调用方统一提示
    _showSnack(
      allPinned
          ? NotesStrings.batchUnpinnedToast(shown.length)
          : NotesStrings.batchPinnedToast(shown.length),
    );
  }

  /// 批量/单条操作用同一段「忙碌 + 进度条」包装。
  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 删除
  // ---------------------------------------------------------------------------

  Future<void> _deleteNotes(List<Note> notes) async {
    if (notes.isEmpty) return;
    final single = notes.length == 1;
    final confirmed = await showConfirmDialog(
      context,
      title: single ? NotesStrings.deleteTitle : NotesStrings.batchDeleteTitle,
      message: single
          ? NotesStrings.deleteMessage(notes.first.displayTitle)
          : NotesStrings.batchDeleteMessage(notes.length),
      confirmLabel: NotesStrings.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _runBusy(() async {
      try {
        final failed = await _actions.deleteAll(notes.map((note) => note.id));
        if (!mounted) return;
        final succeeded = notes.length - failed;
        if (failed == 0) {
          _showSnack(
            single
                ? NotesStrings.deletedToast
                : NotesStrings.batchDeletedToast(succeeded),
          );
        } else if (succeeded == 0) {
          _showSnack(NotesStrings.batchAllFailed(failed));
        } else {
          _showSnack(
            '${NotesStrings.batchDeletedToast(succeeded)}，'
            '${NotesStrings.batchPartialFailure(failed, notes.length)}',
          );
        }
      } catch (error) {
        _showSnack(describeError(error));
      }
    });
    if (mounted) _exitSelection();
  }

  // ---------------------------------------------------------------------------
  // 批量操作
  // ---------------------------------------------------------------------------

  /// 当前选择里仍然可见的笔记（过滤后可能变少）。
  List<Note> _effectiveSelection(List<Note> scope) {
    if (!_selectionMode) return const <Note>[];
    return scope.where((note) => _selected.contains(note.id)).toList(growable: false);
  }

  void _enterSelection(Note note) {
    setState(() {
      _selectionMode = true;
      _selected
        ..clear()
        ..add(note.id);
      _anchorId = note.id;
    });
  }

  void _exitSelection() {
    if (!_selectionMode && _selected.isEmpty) return;
    setState(() {
      _selectionMode = false;
      _selected.clear();
      _anchorId = null;
    });
  }

  void _toggleSelected(Note note) {
    setState(() {
      if (!_selected.remove(note.id)) {
        _selected.add(note.id);
        _anchorId = note.id;
      }
    });
  }

  /// Shift 连选：从锚点到目标之间全选（已选中的不取消）。
  void _selectRange(List<Note> visible, Note target) {
    final anchorId = _anchorId;
    final targetIndex = visible.indexWhere((note) => note.id == target.id);
    final anchorIndex =
        anchorId == null ? -1 : visible.indexWhere((note) => note.id == anchorId);
    if (targetIndex < 0) return;
    if (anchorIndex < 0) {
      _toggleSelected(target);
      return;
    }
    final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final end = anchorIndex < targetIndex ? targetIndex : anchorIndex;
    setState(() {
      for (var index = start; index <= end; index++) {
        _selected.add(visible[index].id);
      }
      _anchorId = target.id;
    });
  }

  void _selectAll(List<Note> visible) {
    setState(() {
      _selectionMode = true;
      _selected
        ..clear()
        ..addAll(visible.map((note) => note.id));
      _anchorId = visible.isEmpty ? null : visible.last.id;
    });
  }

  void _invertSelection(List<Note> visible) {
    final visibleIds = visible.map((note) => note.id).toSet();
    setState(() {
      _selectionMode = true;
      final inverted = visibleIds.difference(_selected);
      _selected
        ..clear()
        ..addAll(inverted);
      _anchorId = null;
    });
  }

  Future<void> _batchMove(List<Note> notes) async {
    final target = await _pickMoveTarget(notes: notes);
    if (target == null || !mounted) return;
    // 源列表就是目标笔记本时无需移动（也不能原地移动），直接忽略。
    final effective = target.notebookId == widget.notebookId
        ? const <Note>[]
        : notes;
    if (effective.isEmpty) {
      _showSnack(NotesStrings.moveSameNotebookHint);
      return;
    }
    await _runBusy(() async {
      final failed = await _actions.moveAll(
        effective,
        targetNotebookId: target.notebookId,
      );
      if (!mounted) return;
      final succeeded = effective.length - failed;
      if (failed == 0) {
        _showSnack(NotesStrings.batchMovedToast(succeeded, target.label));
      } else if (succeeded == 0) {
        _showSnack(NotesStrings.batchAllFailed(failed));
      } else {
        _showSnack(
          '${NotesStrings.batchMovedToast(succeeded, target.label)}，'
          '${NotesStrings.batchPartialFailure(failed, effective.length)}',
        );
      }
    });
    if (mounted) _exitSelection();
  }

  Future<void> _batchDuplicate(List<Note> notes) async {
    await _runBusy(() async {
      final failed = await _actions.duplicateAll(
        notes,
        notebookId: widget.notebookId,
      );
      if (!mounted) return;
      final succeeded = notes.length - failed;
      if (failed == 0) {
        _showSnack(NotesStrings.batchDuplicatedToast(succeeded));
      } else if (succeeded == 0) {
        _showSnack(NotesStrings.batchAllFailed(failed));
      } else {
        _showSnack(
          '${NotesStrings.batchDuplicatedToast(succeeded)}，'
          '${NotesStrings.batchPartialFailure(failed, notes.length)}',
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // 排序与筛选
  // ---------------------------------------------------------------------------

  List<Note> _visibleNotes(List<Note> notes) {
    final keyword = _filter.trim().toLowerCase();
    final filtered = keyword.isEmpty
        ? notes
        : notes
            .where((note) =>
                note.displayTitle.toLowerCase().contains(keyword) ||
                note.content.toLowerCase().contains(keyword))
            .toList();
    final sorted = List<Note>.of(filtered);
    int compareDate(DateTime? a, DateTime? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return b.compareTo(a);
    }

    switch (_sort) {
      case _NoteSort.updated:
        sorted.sort((a, b) => compareDate(a.updated, b.updated));
      case _NoteSort.created:
        sorted.sort((a, b) => compareDate(a.created, b.created));
      case _NoteSort.title:
        sorted.sort((a, b) =>
            a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
    }
    return sorted;
  }

  /// 构造「笔记 id → 正文」索引，用于列表摘要。
  ///
  /// 后端 `GET /api/notes?notebook_id=...` 为了性能**不返回 content**
  /// （见 AGENTS.md 第 2.3 节），而 `GET /api/notes`（不带过滤）会返回正文。
  /// 因此这里复用 [allNotesProvider] 的结果补齐摘要；拿不到时降级为不显示摘要。
  Map<String, String> _contentIndex(List<Note> notes) {
    final needsContent = notes.any((note) => note.content.isEmpty);
    if (!needsContent) return const {};
    final allNotes = ref.watch(allNotesProvider).valueOrNull;
    if (allNotes == null) return const {};
    return {
      for (final note in allNotes)
        if (note.content.isNotEmpty) note.id: note.content,
    };
  }

  /// 置顶优先排序：置顶组保持当前排序，其余跟在后面。
  List<_ListEntry> _buildEntries(List<Note> visible, Set<String> pinned) {
    final pinnedNotes = <Note>[];
    final others = <Note>[];
    for (final note in visible) {
      (pinned.contains(note.id) ? pinnedNotes : others).add(note);
    }
    final entries = <_ListEntry>[];
    if (pinnedNotes.isNotEmpty) {
      entries.add(const _HeaderEntry(NotesStrings.pinnedSection));
      entries.addAll(pinnedNotes.map(_NoteEntry.new));
    }
    if (others.isNotEmpty) {
      if (pinnedNotes.isNotEmpty) {
        entries.add(const _HeaderEntry(NotesStrings.othersSection));
      }
      entries.addAll(others.map(_NoteEntry.new));
    }
    return entries;
  }

  // ---------------------------------------------------------------------------
  // 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // 从笔记标签页切回列表时刷新一次：编辑 / 删除可能已改变标题与更新时间。
    ref.listen<WorkspaceState>(workspaceProvider, (previous, next) {
      if (previous?.activeId == next.activeId) return;
      if (next.activeTab?.kind != WorkspaceTabKind.notes) return;
      _invalidateLists();
    });
    final notesAsync = ref.watch(notesProvider(widget.notebookId));
    final pinned = ref.watch(pinnedNotesProvider).valueOrNull ?? const <String>{};

    return PopScope(
      // 多选时系统返回键先退出多选，不直接退出页面。
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitSelection();
      },
      child: Scaffold(
        appBar: _selectionMode
            ? _buildSelectionAppBar(notesAsync.valueOrNull ?? const <Note>[])
            : _buildAppBar(notesAsync.hasValue),
        bottomNavigationBar: _selectionMode
            ? _buildBatchBar(notesAsync.valueOrNull ?? const <Note>[])
            : null,
        // 手机端由底部悬浮工具栏的「+」承担新建；桌面端保留右下角按钮。
        floatingActionButton: _selectionMode
            ? null
            : Responsive.useSideNavigation(context)
                ? FloatingActionButton.extended(
                    onPressed: _createNote,
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text(NotesStrings.create),
                  )
                : null,
        body: notesAsync.when(
          loading: () => const AppLoadingView(message: S.loading),
          error: (error, _) => AppErrorView(
            title: NotesStrings.loadErrorTitle,
            message: describeError(error),
            onRetry: () => ref.invalidate(notesProvider(widget.notebookId)),
          ),
          data: (notes) {
            final visible = _visibleNotes(notes);
            final entries = _buildEntries(visible, pinned);
            final contentIndex = _contentIndex(notes);
            final content = Column(
              children: [
                // 多选时筛选框仍然有用（先筛选再全选），只是不能再改排序入口。
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: TextField(
                    controller: _filterController,
                    onChanged: (value) => setState(() => _filter = value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: NotesStrings.filterHint,
                      prefixIcon: const Icon(Icons.filter_list_rounded, size: 20),
                      suffixIcon: _filter.isEmpty
                          ? null
                          : IconButton(
                              tooltip: S.clear,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _filterController.clear();
                                setState(() => _filter = '');
                              },
                            ),
                    ),
                  ),
                ),
                if (_busy)
                  const LinearProgressIndicator(minHeight: 2)
                else
                  const SizedBox(height: 2),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(notesProvider(widget.notebookId));
                      try {
                        await ref.read(notesProvider(widget.notebookId).future);
                      } catch (_) {
                        // 错误由 AsyncValue 渲染。
                      }
                    },
                    child: visible.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: MediaQuery.sizeOf(context).height * 0.5,
                                child: _buildEmpty(notes.isEmpty),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return switch (entry) {
                                _HeaderEntry(:final title) =>
                                  _ListSectionHeader(title: title),
                                _NoteEntry(:final note) => Padding(
                                    key: ValueKey(note.id),
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _NoteTile(
                                      note: note,
                                      contentOverride: contentIndex[note.id],
                                      pinned: pinned.contains(note.id),
                                      selectionMode: _selectionMode,
                                      selected: _selected.contains(note.id),
                                      onTap: () => _handleTap(visible, note),
                                      onLongPress: () => _enterSelection(note),
                                      onToggleSelected: () {
                                        if (HardwareKeyboard.instance.isShiftPressed) {
                                          _selectRange(visible, note);
                                        } else {
                                          _toggleSelected(note);
                                        }
                                      },
                                      onAction: (action) => _handleAction(note, action),
                                    ),
                                  ),
                              };
                            },
                          ),
                  ),
                ),
              ],
            );
            if (!widget.padded) return content;
            return ContentFrame(maxWidth: 860, child: content);
          },
        ),
      ),
    );
  }

  /// 点击一行：多选时切换选中；桌面端按住 Ctrl/Cmd / Shift 也可直接选。
  void _handleTap(List<Note> visible, Note note) {
    if (_selectionMode) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _selectRange(visible, note);
      } else {
        _toggleSelected(note);
      }
      return;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed || keyboard.isControlPressed || keyboard.isMetaPressed) {
      _enterSelection(note);
      if (keyboard.isShiftPressed) _selectRange(visible, note);
      return;
    }
    _openNote(note);
  }

  AppBar _buildAppBar(bool hasNotes) {
    return AppBar(
      automaticallyImplyLeading: widget.showBackButton,
      title: Text(widget.title),
      actions: [
        if (hasNotes)
          IconButton(
            tooltip: NotesStrings.selectTooltip,
            onPressed: () => setState(() {
              _selectionMode = true;
              _anchorId = null;
            }),
            icon: const Icon(Icons.checklist_rounded),
          ),
        PopupMenuButton<_NoteSort>(
          tooltip: NotesStrings.sortTooltip,
          onSelected: (value) => setState(() => _sort = value),
          initialValue: _sort,
          icon: const Icon(Icons.sort_rounded),
          itemBuilder: (context) => const [
            PopupMenuItem(value: _NoteSort.updated, child: Text(NotesStrings.sortUpdated)),
            PopupMenuItem(value: _NoteSort.created, child: Text(NotesStrings.sortCreated)),
            PopupMenuItem(value: _NoteSort.title, child: Text(NotesStrings.sortTitle)),
          ],
        ),
        IconButton(
          tooltip: S.refresh,
          onPressed: () => ref.invalidate(notesProvider(widget.notebookId)),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  AppBar _buildSelectionAppBar(List<Note> scope) {
    final selected = _effectiveSelection(scope);
    return AppBar(
      leading: IconButton(
        tooltip: NotesStrings.exitSelection,
        onPressed: _exitSelection,
        icon: const Icon(Icons.close_rounded),
      ),
      title: Text(NotesStrings.selectedCount(selected.length)),
      actions: [
        IconButton(
          tooltip: NotesStrings.selectAll,
          onPressed: () => _selectAll(_visibleNotes(scope)),
          icon: const Icon(Icons.select_all_rounded),
        ),
        IconButton(
          tooltip: NotesStrings.invertSelection,
          onPressed: () => _invertSelection(_visibleNotes(scope)),
          icon: const Icon(Icons.flip_to_back_rounded),
        ),
        PopupMenuButton<_NoteAction>(
          tooltip: NotesStrings.batchMore,
          enabled: selected.isNotEmpty && !_busy,
          onSelected: (action) {
            switch (action) {
              case _NoteAction.rename:
              case _NoteAction.move:
                return;
              case _NoteAction.pin:
                _togglePin(selected);
              case _NoteAction.duplicate:
                _batchDuplicate(selected);
              case _NoteAction.delete:
                _deleteNotes(selected);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _NoteAction.duplicate,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.copy_all_rounded),
                title: Text(NotesStrings.batchDuplicate),
              ),
            ),
            PopupMenuItem(
              value: _NoteAction.delete,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline_rounded),
                title: Text(NotesStrings.delete),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 底部批量操作条：置顶 / 移至 / 复制 / 删除。
  ///
  /// 放在底部而不是 AppBar：窄屏上 4 个图标 + 「已选 N 项」会挤爆标题栏，
  /// 底部条也更接近手机上的拇指可达区域（参考 Google Keep / Joplin）。
  Widget _buildBatchBar(List<Note> scope) {
    final selected = _effectiveSelection(scope);
    final enabled = selected.isNotEmpty && !_busy;
    final pinned = ref.watch(pinnedNotesProvider).valueOrNull ?? const <String>{};
    final allPinned = selected.isNotEmpty &&
        selected.every((note) => pinned.contains(note.id));
    return BottomAppBar(
      height: 68,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          _BatchAction(
            icon: allPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            label: allPinned ? NotesStrings.unpin : NotesStrings.pin,
            onPressed: enabled ? () => _togglePin(selected) : null,
          ),
          _BatchAction(
            icon: Icons.drive_file_move_outlined,
            label: NotesStrings.moveToNotebook,
            onPressed: enabled ? () => _batchMove(selected) : null,
          ),
          _BatchAction(
            icon: Icons.copy_all_rounded,
            label: NotesStrings.batchDuplicate,
            onPressed: enabled ? () => _batchDuplicate(selected) : null,
          ),
          _BatchAction(
            icon: Icons.delete_outline_rounded,
            label: NotesStrings.delete,
            destructive: true,
            onPressed: enabled ? () => _deleteNotes(selected) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool notebookEmpty) {
    if (!notebookEmpty) {
      return AppEmptyView(
        icon: Icons.search_off_rounded,
        title: NotesStrings.filterEmptyTitle,
        message: NotesStrings.filterEmptyMessage,
        actionLabel: S.clearFilter,
        onAction: () {
          _filterController.clear();
          setState(() => _filter = '');
        },
      );
    }
    return AppEmptyView(
      icon: Icons.description_outlined,
      title: widget.notebookId == null
          ? NotesStrings.emptyAllTitle
          : NotesStrings.emptyTitle,
      message: widget.notebookId == null
          ? NotesStrings.emptyAllMessage
          : NotesStrings.emptyMessage,
      actionLabel: NotesStrings.create,
      onAction: _createNote,
    );
  }
}

/// 分节标题（置顶 / 其它笔记）。
class _ListSectionHeader extends StatelessWidget {
  const _ListSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

/// 底部批量条上的一个操作（图标 + 短标签）。
class _BatchAction extends StatelessWidget {
  const _BatchAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = onPressed == null
        ? scheme.onSurfaceVariant.withValues(alpha: 0.38)
        : destructive
            ? scheme.error
            : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表里的一条笔记。
class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.note,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleSelected,
    required this.onAction,
    required this.pinned,
    required this.selectionMode,
    required this.selected,
    this.contentOverride,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelected;
  final ValueChanged<_NoteAction> onAction;
  final bool pinned;

  /// 是否处于多选模式（显示勾选圈、隐藏⋯菜单）。
  final bool selectionMode;
  final bool selected;

  /// 列表接口未返回正文时，用内容索引里的正文生成摘要。
  final String? contentOverride;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final override = contentOverride;
    final snippet = (override == null || override.isEmpty)
        ? note.snippet()
        : Note.snippetOf(override);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? scheme.primary : Colors.transparent,
          width: selected ? 1.4 : 0,
        ),
      ),
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      child: InkWell(
        onTap: selectionMode ? onToggleSelected : onTap,
        onLongPress: selectionMode ? null : onLongPress,
        child: Padding(
          padding: EdgeInsets.fromLTRB(selectionMode ? 8 : 16, 14, 6, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectionMode) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 6),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 22,
                    color: selected ? scheme.primary : scheme.outline,
                  ),
                ),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (pinned) ...[
                          Icon(
                            Icons.push_pin_rounded,
                            size: 15,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            note.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        if (note.isAi) ...[
                          const SizedBox(width: 6),
                          const _AiBadge(),
                        ],
                      ],
                    ),
                    if (snippet.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '${NotesStrings.updatedAt} ${Formatters.relativeTime(note.updated)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (!selectionMode)
                PopupMenuButton<_NoteAction>(
                  tooltip: NotesStrings.moreTooltip,
                  onSelected: onAction,
                  icon: const Icon(Icons.more_vert_rounded),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: _NoteAction.rename,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.drive_file_rename_outline_rounded),
                        title: Text(S.rename),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _NoteAction.move,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.drive_file_move_outlined),
                        title: Text(NotesStrings.moveToNotebook),
                      ),
                    ),
                    PopupMenuItem(
                      value: _NoteAction.pin,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          pinned
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                        ),
                        title: Text(
                          pinned ? NotesStrings.unpin : NotesStrings.pin,
                        ),
                        subtitle: const Text(
                          NotesStrings.pinLocalOnlyHint,
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _NoteAction.duplicate,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.content_copy_rounded),
                        title: Text(NotesStrings.duplicate),
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _NoteAction.delete,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline_rounded),
                        title: Text(NotesStrings.delete),
                      ),
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

class _AiBadge extends StatelessWidget {
  const _AiBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        NotesStrings.aiBadge,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onTertiaryContainer,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
