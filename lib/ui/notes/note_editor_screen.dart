import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_models.dart';
import '../../state/note_actions.dart';
import '../../state/providers.dart';
import '../../state/workspace.dart';
import '../common/formatters.dart';
import '../common/layout.dart';
import '../common/strings.dart';
import '../common/widgets.dart';
import '../home/workspace_strings.dart';
import '../notebooks/move_to_notebook_dialog.dart';
import '../notebooks/notes_strings.dart';
import 'editor_strings.dart';
import 'live_preview_editor.dart';
import 'markdown_outline.dart';
import 'markdown_tasks.dart';
import 'markdown_toolbar.dart';
import 'markdown_view.dart';
import 'notes_outline_panel.dart';

enum _LeaveAction { save, discard, cancel }

/// 编辑器视图模式，对应 Obsidian「视图 + 模式」的简化：
/// - [live] 实时预览：渲染态直接编辑，点按段落就在该段位置显示源码（Live Preview）；
/// - [source] 源码模式：整篇 Markdown 纯文本编辑；
/// - [reading] 阅读视图：只渲染不可编辑，任务复选框仍可勾选。
enum EditorViewMode { live, source, reading }

/// 编辑页⋯菜单项（置顶 / 移至笔记本 / 创建副本 / 删除）。
enum _EditorAction { pin, move, duplicate, delete }

/// 笔记编辑器：编辑 / 预览双模式，新建与编辑共用。
///
/// 两种使用方式：
/// - **标签页**（默认）：由工作区外壳以 `tabId` + [WorkspaceTabBinding] 嵌入，
///   标题、未保存标记与摘要同步到标签条，关闭前的未保存确认由工作区统一处理；
/// - **独立路由**：不传 [WorkspaceTabBinding] 时保持旧行为，用 `Navigator.pop`
///   返回「内容是否有变更」。
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({
    super.key,
    this.noteId,
    this.notebookId,
    this.initialTitle,
    this.initialContent,
    this.tabId,
    this.binding,
  });

  /// 为空表示新建笔记。
  final String? noteId;

  /// 新建笔记归属的笔记本。
  final String? notebookId;

  final String? initialTitle;
  final String? initialContent;

  /// 所在标签页 id；独立路由时为 null。
  final String? tabId;

  /// 与工作区标签页的双向绑定；为 null 表示独立路由。
  final WorkspaceTabBinding? binding;

  bool get embedded => binding != null;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen>
    implements WorkspaceTabSession {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final FocusNode _contentFocus = FocusNode();

  String? _noteId;

  /// 笔记类型（human / ai），新建副本时保留。
  String _noteType = 'human';

  /// 当前归属笔记本（移动后会被改写；`widget.notebookId` 只用于首次构建）。
  String? _notebookId;
  String _baselineTitle = '';
  String _baselineContent = '';
  bool _dirty = false;
  bool _saving = false;

  /// 「置顶 / 移动 / 复制」这类菜单操作进行中：禁用菜单，但不影响 [_save]
  /// （它们需要先落盘，若复用 [_saving] 会让 [_save] 直接返回 false）。
  bool _actionBusy = false;
  bool _loadingRemote = false;
  EditorViewMode _viewMode = EditorViewMode.live;
  bool _changed = false;
  bool _allowPop = false;
  String? _loadError;
  DateTime? _lastSavedAt;

  @override
  void initState() {
    super.initState();
    _noteId = widget.noteId;
    _notebookId = widget.notebookId;
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _contentController = TextEditingController(text: widget.initialContent ?? '');
    _baselineTitle = _titleController.text;
    _baselineContent = _contentController.text;
    _titleController.addListener(_recomputeDirty);
    _contentController.addListener(_recomputeDirty);
    _contentController.addListener(_handleCursorMoved);
    _titleController.addListener(_publishTitle);
    // 标签页绑定会写 Riverpod 状态，不能在 initState（构建期）同步做，
    // 否则会命中「Tried to modify a provider while the widget tree was building」。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.binding?.onSessionChanged?.call(this);
      _publishTitle();
    });
    if (_noteId != null) {
      _loadRemoteNote();
    }
  }

  @override
  bool get isDirty => _dirty;

  /// 工作区关闭标签页前调用；保存失败时页面自行提示并返回 false。
  @override
  Future<bool> save() => _save();

  /// 关闭标签页 / 删除笔记时丢弃草稿（页面随后被销毁）。
  @override
  void discardChanges() {
    _titleController.text = _baselineTitle;
    _contentController.text = _baselineContent;
    _dirty = false;
  }

  /// 标签条标题：标题输入框优先，为空时用正文首行兜底。
  ///
  /// 两者都为空（新建草稿刚打开）时不改标题，保留「新建笔记」这样的初始文案。
  void _publishTitle() {
    final title = _titleController.text.trim();
    final fallback = _contentController.text
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (title.isEmpty && fallback.isEmpty) return;
    widget.binding?.onTitleChanged?.call(title.isEmpty ? fallback : title);
  }

  @override
  void dispose() {
    // 会话注销由工作区在 closeTab 时完成：dispose 阶段不能改 provider 状态。
    _titleController.dispose();
    _contentController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  void _recomputeDirty() {
    final dirty = _titleController.text != _baselineTitle ||
        _contentController.text != _baselineContent;
    if (dirty != _dirty) {
      setState(() => _dirty = dirty);
      widget.binding?.onDirtyChanged?.call(dirty);
    }
  }

  Future<void> _loadRemoteNote() async {
    setState(() {
      _loadingRemote = true;
      _loadError = null;
    });
    final repository = ref.read(repositoryProvider);
    final id = _noteId;
    if (repository == null || id == null) {
      setState(() => _loadingRemote = false);
      return;
    }
    try {
      final note = await repository.fetchNote(id);
      if (!mounted) return;
      _titleController.text = note.title;
      _contentController.text = note.content;
      _noteType = note.noteType.isEmpty ? 'human' : note.noteType;
      _baselineTitle = note.title;
      _baselineContent = note.content;
      _lastSavedAt = note.updated;
      setState(() {
        _loadingRemote = false;
        _dirty = false;
      });
      _publishTitle();
      widget.binding?.onDirtyChanged?.call(false);
      widget.binding?.onPreviewChanged?.call(Note.snippetOf(note.content));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingRemote = false;
        _loadError = describeError(error);
      });
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _save() async {
    if (_saving) return false;
    final repository = ref.read(repositoryProvider);
    if (repository == null) {
      _showSnack(S.notConfiguredMessage);
      return false;
    }
    setState(() => _saving = true);
    final title = _titleController.text.trim();
    final content = _contentController.text;
    try {
      final Note saved;
      if (_noteId == null) {
        saved = await repository.createNote(
          title: title.isEmpty ? null : title,
          content: content,
          noteType: 'human',
          notebookId: _notebookId,
        );
        _noteId = saved.id;
      } else {
        saved = await repository.updateNote(
          _noteId!,
          title: title,
          content: content,
        );
      }
      _baselineTitle = _titleController.text;
      _baselineContent = _contentController.text;
      _lastSavedAt = saved.updated ?? DateTime.now();
      _changed = true;
      if (widget.binding != null) {
        // 新建笔记首次保存：把草稿标签页绑定到真实笔记 id。
        widget.binding!.onNoteSaved?.call(saved.id);
        widget.binding!.onPreviewChanged?.call(Note.snippetOf(content));
        _publishTitle();
      }
      // 列表与容器信息都可能变化。
      ref.invalidate(allNotesProvider);
      ref.invalidate(notebooksProvider);
      if (_notebookId != null) {
        ref.invalidate(notesProvider(_notebookId));
      }
      if (!mounted) return true;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      widget.binding?.onDirtyChanged?.call(false);
      _showSnack(EditorStrings.savedToast);
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _saving = false);
      _showSnack('${EditorStrings.saveFailed}：${describeError(error)}');
      return false;
    }
  }

  Future<void> _delete() async {
    final id = _noteId;
    if (id == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: EditorStrings.deleteTitle,
      message: EditorStrings.deleteMessage,
      confirmLabel: EditorStrings.delete,
      destructive: true,
    );
    if (!confirmed) return;
    final repository = ref.read(repositoryProvider);
    if (repository == null) return;
    try {
      await repository.deleteNote(id);
      _changed = true;
      ref.invalidate(allNotesProvider);
      ref.invalidate(notebooksProvider);
      if (_notebookId != null) {
        ref.invalidate(notesProvider(_notebookId));
      }
      if (!mounted) return;
      _showSnack(EditorStrings.deletedToast);
      if (widget.embedded) {
        // 笔记已删除：标签页无需再确认，直接关闭。
        widget.binding!.onClosed?.call();
      } else {
        _pop(_changed);
      }
    } catch (error) {
      _showSnack(describeError(error));
    }
  }

  /// 把编辑中的内容包装成 [Note]，供共用操作（置顶 / 移动 / 复制）使用。
  Note? _currentNote() {
    final id = _noteId;
    if (id == null) return null;
    return Note(
      id: id,
      title: _titleController.text.trim(),
      content: _contentController.text,
      noteType: _noteType,
      created: null,
      updated: _lastSavedAt,
    );
  }

  late final NoteActions _noteActions = NoteActions(ref);

  bool get _pinned =>
      (ref.read(pinnedNotesProvider).valueOrNull ?? const <String>{}).contains(_noteId);

  Future<void> _togglePin() async {
    final note = _currentNote();
    if (note == null) return;
    final next = !_pinned;
    await _noteActions.setPinned(<String>[note.id], pinned: next);
    if (!mounted) return;
    _showSnack(next ? NotesStrings.pinToast : NotesStrings.unpinToast);
  }

  Future<void> _duplicate() async {
    final note = _currentNote();
    if (note == null) return;
    setState(() => _actionBusy = true);
    try {
      // 先把草稿落盘，副本才是用户刚看到的内容。
      if (_dirty && !await _save()) return;
      await _noteActions.duplicate(note, notebookId: _notebookId);
      if (!mounted) return;
      _showSnack(NotesStrings.duplicateToast);
    } catch (error) {
      if (!mounted) return;
      _showSnack('${NotesStrings.duplicateFailed}：${describeError(error)}');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _moveToNotebook() async {
    final note = _currentNote();
    if (note == null) return;
    final target = await showMoveToNotebookDialog(
      context,
      currentNotebookId: _notebookId,
    );
    if (target == null || !mounted) return;
    if (target.notebookId == _notebookId) {
      _showSnack(NotesStrings.moveSameNotebookHint);
      return;
    }
    setState(() => _actionBusy = true);
    try {
      // 未保存的修改必须先落盘：移动 = 复制服务端正文 + 删除原笔记。
      if (_dirty && !await _save()) return;
      final outcome = await _noteActions.move(
        note,
        targetNotebookId: target.notebookId,
      );
      if (!mounted) return;
      setState(() {
        _noteId = outcome.note.id;
        _notebookId = target.notebookId;
      });
      // 改绑标签页（NoteActions.move 已按旧 id 改绑，这里兜底同步标题）。
      widget.binding?.onTitleChanged?.call(outcome.note.displayTitle);
      _showSnack(NotesStrings.movedToToast(target.label));
    } catch (error) {
      if (!mounted) return;
      _showSnack('${NotesStrings.moveFailed}：${describeError(error)}');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<_LeaveAction> _confirmLeave() async {
    final result = await showDialog<_LeaveAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(EditorStrings.unsavedTitle),
        content: const Text(EditorStrings.unsavedMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(_LeaveAction.cancel),
            child: const Text(S.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(_LeaveAction.discard),
            child: const Text(EditorStrings.unsavedDiscard),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(dialogContext).pop(_LeaveAction.save),
            child: const Text(EditorStrings.unsavedSaveAndLeave),
          ),
        ],
      ),
    );
    return result ?? _LeaveAction.cancel;
  }

  /// 统一退出逻辑：处理未保存修改后带结果返回。
  ///
  /// 嵌入标签页时把关闭交给工作区：桌面标签条、快捷键、移动端标签总览
  /// 都走同一套未保存确认，行为保持一致。
  Future<void> _handleBack() async {
    if (_saving) return;
    if (widget.embedded) {
      widget.binding!.onRequestClose?.call();
      return;
    }
    if (_dirty) {
      final action = await _confirmLeave();
      if (action == _LeaveAction.cancel) return;
      if (action == _LeaveAction.save) {
        final saved = await _save();
        if (!saved) return;
      }
    }
    _pop(_changed);
  }

  void _pop(bool changed) {
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop(changed);
    });
  }

  // ---------------------------------------------------------------------------
  // 视图模式与预览态编辑
  // ---------------------------------------------------------------------------

  void _setViewMode(EditorViewMode mode) {
    if (mode == _viewMode) return;
    // 切换前先让输入框失焦，确保实时预览里的段落编辑已提交。
    FocusScope.of(context).unfocus();
    // 阅读视图的高亮由滚动位置驱动，切过去之前先按当前光标算一个初值。
    final heading = mode == EditorViewMode.reading ? _currentHeadingIndex : -1;
    setState(() {
      _viewMode = mode;
      if (heading >= 0) _activeHeading = heading;
    });
  }

  /// 勾选任务列表复选框：直接改写整篇正文里的 `[ ]` / `[x]`。
  ///
  /// 正文控制器变化不一定触发本页重建（脏标记可能已经是 true），
  /// 因此显式 `setState`，让预览立即反映勾选结果。
  void _toggleTask(int index) {
    final next = MarkdownTasks.toggle(_contentController.text, index);
    if (next == null || next == _contentController.text) return;
    final selection = _contentController.selection;
    setState(() {
      _contentController.value = TextEditingValue(
        text: next,
        selection: selection.isValid ? selection : TextSelection.collapsed(offset: 0),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // 大纲
  // ---------------------------------------------------------------------------

  /// 大纲在宽窗口里是否以右侧常驻侧栏展示（窄窗口改为底部弹出面板）。
  bool _outlineOpen = false;

  /// 大纲跳转请求：每次点击都是新实例，实时预览据此滚动到对应段落。
  OutlineJumpRequest? _outlineJump;

  /// 当前大纲高亮项：编辑时跟随光标 / 选区，阅读时跟随滚动位置。
  int _activeHeading = -1;

  /// 正文控制器内容变化后重新解析标题。
  ///
  /// 光标移动/逐字符输入都会走到这里，长笔记全量解析会很贵，因此按正文缓存：
  /// 只有正文变了才重新扫描标题。
  List<MarkdownHeading> get _headings {
    final text = _contentController.text;
    if (text == _headingsCacheText) return _headingsCache;
    _headingsCacheText = text;
    _headingsCache = parseMarkdownHeadings(text);
    return _headingsCache;
  }

  String _headingsCacheText = '';
  List<MarkdownHeading> _headingsCache = const <MarkdownHeading>[];

  /// 正文光标 / 滚动位置变化时更新大纲高亮。
  void _syncActiveHeading(int? offset) {
    final index = activeHeadingIndex(_headings, offset);
    if (index == _activeHeading || !mounted) return;
    setState(() => _activeHeading = index);
  }

  /// 源码模式 / 实时预览里移动光标时同步大纲高亮；阅读视图自己按滚动位置算。
  ///
  /// 大纲没展开时不做任何事：这个监听挂每次按键，没必要为不可见的面板重建页面。
  void _handleCursorMoved() {
    if (!_outlineOpen || _viewMode == EditorViewMode.reading) return;
    final selection = _contentController.selection;
    _syncActiveHeading(selection.isValid ? selection.extentOffset : null);
  }

  /// 点击大纲里的标题：滚动 / 定位到该标题。
  ///
  /// - 源码模式：把光标放到标题正文处并聚焦，再让输入框把它滚进视野；
  /// - 实时预览：交给 [LivePreviewEditor] 滚动到该段；
  /// - 阅读视图：按标题分节渲染，直接滚动到该节的 Key。
  void _jumpToHeading(MarkdownHeading heading) {
    switch (_viewMode) {
      case EditorViewMode.source:
        final offset = heading.textStart.clamp(
          0,
          _contentController.text.length,
        );
        _contentController.selection = TextSelection.collapsed(offset: offset);
        _contentFocus.requestFocus();
        // 输入框已经聚焦时，程序化改选区不会触发框架的「滚动到光标」，
        // 这里直接用 EditableTextState 的公开 API 定位（重新聚焦会闪键盘）。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _contentFocus.context
              ?.findAncestorStateOfType<EditableTextState>()
              ?.bringIntoView(TextPosition(offset: offset));
        });
      case EditorViewMode.live:
        setState(() {
          _outlineJump = OutlineJumpRequest(heading.offset);
          _activeHeading = _headings.indexOf(heading);
        });
      case EditorViewMode.reading:
        setState(() => _activeHeading = _headings.indexOf(heading));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final target = _sectionContextFor(heading.offset);
          if (target == null) return;
          Scrollable.ensureVisible(
            target,
            alignment: 0.02,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        });
    }
  }

  /// 阅读视图里每一节的 key：按该节起始偏移量索引，供大纲跳转定位。
  final Map<int, GlobalKey> _sectionKeys = <int, GlobalKey>{};

  /// 找到包含 [offset] 的那一节的 BuildContext。
  ///
  /// 正常情况下标题行自己就是节首（[MarkdownSourceMap] 会在标题处切块），
  /// 但标题紧贴上一段、没有空行时，它会被并进上一节；这里回退到那一节，
  /// 保证「点了总能跳过去」。
  BuildContext? _sectionContextFor(int offset) {
    final exact = _sectionKeys[offset]?.currentContext;
    if (exact != null) return exact;
    int? nearest;
    for (final start in _sectionKeys.keys) {
      if (start <= offset && (nearest == null || start > nearest)) {
        nearest = start;
      }
    }
    return nearest == null ? null : _sectionKeys[nearest]?.currentContext;
  }

  /// 大纲是否以右侧常驻侧栏展示。
  bool get _outlineIsSidebar => Responsive.useOutlineSidebar(context);

  /// 大纲按钮：宽窗口开合侧栏，窄窗口弹出底部面板（选中标题后关闭面板）。
  Future<void> _toggleOutline() async {
    final headings = _headings;
    final active = _currentHeadingIndex;
    if (_outlineIsSidebar) {
      setState(() => _outlineOpen = !_outlineOpen);
      return;
    }
    final picked = await showNotesOutlineSheet(
      context,
      headings: headings,
      activeIndex: active,
    );
    if (picked == null || !mounted) return;
    _jumpToHeading(picked);
  }

  /// 当前高亮项：编辑视图按光标所在行，阅读视图按滚动位置维护的 [_activeHeading]。
  int get _currentHeadingIndex {
    if (_viewMode == EditorViewMode.reading) return _activeHeading;
    final selection = _contentController.selection;
    if (!selection.isValid) return -1;
    return activeHeadingIndex(_headings, selection.extentOffset);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 订阅置顶集合：菜单里的「置顶 / 取消置顶」文案要跟着立即变化。
    ref.watch(pinnedNotesProvider);
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: CallbackShortcuts(
        // 桌面端习惯：Ctrl/Cmd + S 保存（回车仍由输入框自己处理）。
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        },
        child: Scaffold(
        appBar: AppBar(
          // 标签页里没有「返回」，用关闭标签页替代；独立路由保留返回按钮。
          leading: IconButton(
            tooltip: widget.embedded ? WorkspaceStrings.closeTab : S.back,
            icon: Icon(
              widget.embedded ? Icons.close_rounded : Icons.arrow_back_rounded,
            ),
            onPressed: _handleBack,
          ),
          title: Text(
            _noteId == null ? EditorStrings.newNote : EditorStrings.editTitle,
          ),
          actions: [
            PopupMenuButton<EditorViewMode>(
              tooltip: EditorStrings.switchMode,
              initialValue: _viewMode,
              onSelected: _setViewMode,
              icon: Icon(
                switch (_viewMode) {
                  EditorViewMode.live => Icons.edit_note_rounded,
                  EditorViewMode.source => Icons.code_rounded,
                  EditorViewMode.reading => Icons.visibility_outlined,
                },
              ),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: EditorViewMode.live,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_note_rounded),
                    title: Text(EditorStrings.modeLive),
                  ),
                ),
                PopupMenuItem(
                  value: EditorViewMode.source,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.code_rounded),
                    title: Text(EditorStrings.modeSource),
                  ),
                ),
                PopupMenuItem(
                  value: EditorViewMode.reading,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.visibility_outlined),
                    title: Text(EditorStrings.modeReading),
                  ),
                ),
              ],
            ),
            // 大纲入口：宽窗口直接开合右侧侧栏，窄窗口用底部弹出面板。
            IconButton(
              tooltip: _outlineOpen && _outlineIsSidebar
                  ? EditorStrings.outlineHide
                  : EditorStrings.outlineTooltip,
              isSelected: _outlineOpen && _outlineIsSidebar,
              onPressed: _toggleOutline,
              icon: const Icon(Icons.toc_rounded),
            ),
            Badge(
              isLabelVisible: _dirty,
              smallSize: 8,
              child: IconButton(
                tooltip: EditorStrings.saveShortcut,
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
              ),
            ),
            if (_noteId != null)
              PopupMenuButton<_EditorAction>(
                tooltip: S.more,
                enabled: !_actionBusy,
                onSelected: (action) {
                  switch (action) {
                    case _EditorAction.pin:
                      _togglePin();
                    case _EditorAction.move:
                      _moveToNotebook();
                    case _EditorAction.duplicate:
                      _duplicate();
                    case _EditorAction.delete:
                      _delete();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _EditorAction.pin,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                      ),
                      title: Text(_pinned ? NotesStrings.unpin : NotesStrings.pin),
                      subtitle: const Text(
                        NotesStrings.pinLocalOnlyHint,
                        style: TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _EditorAction.move,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.drive_file_move_outlined),
                      title: Text(NotesStrings.moveToNotebook),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _EditorAction.duplicate,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.content_copy_rounded),
                      title: Text(NotesStrings.duplicate),
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: _EditorAction.delete,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text(EditorStrings.delete),
                    ),
                  ),
                ],
              ),
            const SizedBox(width: 4),
          ],
        ),
        // 桌面/横屏宽窗口里给正文限宽并居中，避免超长行难以阅读；
        // 大纲侧栏打开时放宽上限，避免两栏一起被夹得过窄。
        body: ContentFrame(
          maxWidth: _outlineOpen && _outlineIsSidebar ? 1400 : 1100,
          child: _buildOutlineScaffold(scheme),
        ),
        ),
      ),
    );
  }

  /// 正文 + 大纲侧栏。
  ///
  /// 大纲是「按需打开」的：常驻会挤压正文，且大多数短笔记用不到。
  Widget _buildOutlineScaffold(ColorScheme scheme) {
    final sidebar = _outlineOpen && _outlineIsSidebar;
    if (!sidebar) return _buildBody(scheme);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildBody(scheme)),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 268,
          child: NotesOutlinePanel(
            headings: _headings,
            activeIndex: _currentHeadingIndex,
            padded: true,
            onClose: () => setState(() => _outlineOpen = false),
            onJump: _jumpToHeading,
          ),
        ),
      ],
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_loadError != null) {
      return AppErrorView(
        title: EditorStrings.loadErrorTitle,
        message: _loadError!,
        onRetry: _loadRemoteNote,
      );
    }
    if (_loadingRemote) {
      return const AppLoadingView(message: S.loading);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: TextField(
            controller: _titleController,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
            textInputAction: TextInputAction.next,
            maxLines: null,
            decoration: InputDecoration(
              hintText: EditorStrings.titleHint,
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
          child: Row(
            children: [
              if (_dirty) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  EditorStrings.unsavedBadge,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                      ),
                ),
              ] else
                Text(
                  _lastSavedAt == null
                      ? EditorStrings.neverSaved
                      : '${EditorStrings.savedAt} ${Formatters.dateTime(_lastSavedAt)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              const Spacer(),
              // 实时预览的就地编辑不会逐字符重建本页，用监听保证字数实时。
              ListenableBuilder(
                listenable: _contentController,
                builder: (context, _) => Text(
                  EditorStrings.charCount(_contentController.text.length),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (_viewMode) {
            EditorViewMode.live => _buildLivePreview(),
            EditorViewMode.source => _buildEditor(scheme),
            EditorViewMode.reading =>
              _splitPane ? _buildReadingSplit() : _buildPreview(),
          },
        ),
        if (_viewMode == EditorViewMode.source)
          MarkdownToolbar(controller: _contentController, focusNode: _contentFocus),
      ],
    );
  }

  Widget _buildEditor(ColorScheme scheme) {
    return TextField(
      controller: _contentController,
      focusNode: _contentFocus,
      maxLines: null,
      minLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      keyboardType: TextInputType.multiline,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 14.5,
        height: 1.65,
      ),
      decoration: InputDecoration(
        hintText: EditorStrings.contentHint,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      ),
    );
  }

  /// 进入源码模式并聚焦正文（空笔记的「开始书写」入口）。
  void _startWriting() {
    setState(() => _viewMode = EditorViewMode.source);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentFocus.requestFocus();
    });
  }

  /// 实时预览：渲染态 + 点按段落就地编辑。
  ///
  /// 正文为空（例如新建笔记）时没有可点按的段落，展示「开始书写」入口，
  /// 点击进入源码模式；不随内容自动切换，避免输入首字时界面跳变、光标丢失。
  Widget _buildLivePreview() {
    if (_contentController.text.trim().isEmpty) {
      return _EmptyDraftPrompt(onStart: _startWriting);
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              Icon(Icons.touch_app_rounded, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  EditorStrings.liveHint,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LivePreviewEditor(
            controller: _contentController,
            onToggleTask: _toggleTask,
            onBlockActivated: (block) => _syncActiveHeading(block.start),
            jump: _outlineJump,
          ),
        ),
      ],
    );
  }

  /// 宽屏下实时预览 / 阅读视图右侧并排一栏（桌面端左右对照更顺手）。
  bool get _splitPane => Responsive.useEditorSplit(context);

  /// 阅读视图 + 右侧「原始 Markdown」只读对照。
  Widget _buildReadingSplit() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 6, child: _buildPreview()),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 5,
          child: _buildPane(
            EditorStrings.paneSource,
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: SelectableText(
                _contentController.text,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13.5,
                  height: 1.65,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 分栏的一栏：顶部小标题 + 内容。
  Widget _buildPane(String title, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.6,
                ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildPreview() {
    final content = _contentController.text;
    if (content.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            EditorStrings.emptyPreview,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    // 阅读视图按标题分节：每节挂 Key 供大纲跳转，并在滚动时刷新大纲高亮。
    final sections = splitMarkdownSections(content);
    // 正文被编辑后偏移量会整体变化：清掉已经不存在的节的 Key，避免 Map 无限增长。
    final offsets = {for (final section in sections) section.start};
    _sectionKeys.removeWhere((offset, _) => !offsets.contains(offset));
    return NotificationListener<ScrollNotification>(
      onNotification: _handlePreviewScroll,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < sections.length; i++)
              Padding(
                // 分节后两个 MarkdownBody 之间没有块间距，补上与原渲染一致的 8。
                padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                child: KeyedSubtree(
                  key: _sectionKeys.putIfAbsent(
                    sections[i].start,
                    () => GlobalKey(debugLabel: 'section-${sections[i].start}'),
                  ),
                  child: MarkdownView(
                    content: sections[i].markdown,
                    taskStartIndex: sections[i].taskOffset,
                    onToggleTask: _toggleTask,
                    selectable: true,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 阅读视图滚动时按「滚过视口顶部的最后一个标题」更新大纲高亮。
  bool _handlePreviewScroll(ScrollNotification notification) {
    if (_viewMode != EditorViewMode.reading || notification.depth != 0) {
      return false;
    }
    final headings = _headings;
    if (headings.isEmpty) return false;
    // 视口顶边：标题滚到它上方之后，下一个标题才算「当前所在位置」。
    final viewport = notification.context?.findRenderObject();
    final viewportTop = viewport is RenderBox && viewport.hasSize
        ? viewport.localToGlobal(Offset.zero).dy
        : 0.0;
    var current = -1;
    for (var i = 0; i < headings.length; i++) {
      final target = _sectionKeys[headings[i].offset]?.currentContext;
      final box = target?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      // 允许 16 的余量：标题刚好压在视口顶边时仍算当前标题。
      if (top <= viewportTop + 16) {
        current = i;
      } else {
        break;
      }
    }
    if (current != _activeHeading) {
      setState(() => _activeHeading = current);
    }
    return false;
  }
}

/// 空笔记的实时预览占位：引导用户进入源码模式开始书写。
class _EmptyDraftPrompt extends StatelessWidget {
  const _EmptyDraftPrompt({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note_rounded, size: 44, color: scheme.primary),
            const SizedBox(height: 14),
            Text(
              EditorStrings.emptyPreview,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.edit_rounded),
              label: const Text(EditorStrings.startWriting),
            ),
          ],
        ),
      ),
    );
  }
}
