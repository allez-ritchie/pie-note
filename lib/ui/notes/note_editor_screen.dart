import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/layout.dart';
import '../common/strings.dart';
import '../common/widgets.dart';
import 'editor_strings.dart';
import 'live_preview_editor.dart';
import 'markdown_blocks.dart';
import 'markdown_tasks.dart';
import 'markdown_toolbar.dart';
import 'markdown_view.dart';

enum _LeaveAction { save, discard, cancel }

/// 编辑器视图模式，对应 Obsidian「视图 + 模式」的简化：
/// - [live] 实时预览：渲染态直接编辑，点按段落就地展开该段源码（Live Preview）；
/// - [source] 源码模式：整篇 Markdown 纯文本编辑；
/// - [reading] 阅读视图：只渲染不可编辑，任务复选框仍可勾选。
enum EditorViewMode { live, source, reading }

/// 笔记编辑器：编辑 / 预览双模式，新建与编辑共用。
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({
    super.key,
    this.noteId,
    this.notebookId,
    this.initialTitle,
    this.initialContent,
  });

  /// 为空表示新建笔记。
  final String? noteId;

  /// 新建笔记归属的笔记本。
  final String? notebookId;

  final String? initialTitle;
  final String? initialContent;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final FocusNode _contentFocus = FocusNode();

  String? _noteId;
  String _baselineTitle = '';
  String _baselineContent = '';
  bool _dirty = false;
  bool _saving = false;
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
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _contentController = TextEditingController(text: widget.initialContent ?? '');
    _baselineTitle = _titleController.text;
    _baselineContent = _contentController.text;
    _titleController.addListener(_recomputeDirty);
    _contentController.addListener(_recomputeDirty);
    if (_noteId != null) {
      _loadRemoteNote();
    }
  }

  @override
  void dispose() {
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
      _baselineTitle = note.title;
      _baselineContent = note.content;
      _lastSavedAt = note.updated;
      setState(() {
        _loadingRemote = false;
        _dirty = false;
      });
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
          notebookId: widget.notebookId,
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
      // 列表与容器信息都可能变化。
      ref.invalidate(allNotesProvider);
      ref.invalidate(notebooksProvider);
      if (widget.notebookId != null) {
        ref.invalidate(notesProvider(widget.notebookId));
      }
      if (!mounted) return true;
      setState(() {
        _saving = false;
        _dirty = false;
      });
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
      if (widget.notebookId != null) {
        ref.invalidate(notesProvider(widget.notebookId));
      }
      if (!mounted) return;
      _showSnack(EditorStrings.deletedToast);
      _pop(_changed);
    } catch (error) {
      _showSnack(describeError(error));
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
  Future<void> _handleBack() async {
    if (_saving) return;
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
    setState(() => _viewMode = mode);
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

  /// 实时预览里的「切到源码」：切到源码模式并选中该段。
  void _editBlockAsSource(MarkdownBlock block) {
    setState(() => _viewMode = EditorViewMode.source);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _contentController.selection = TextSelection(
        baseOffset: block.start,
        extentOffset: block.end,
      );
      _contentFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
          leading: IconButton(
            tooltip: S.back,
            icon: const Icon(Icons.arrow_back_rounded),
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
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (value) {
                  if (value == 'delete') _delete();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete',
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
        // 桌面/横屏宽窗口里给正文限宽并居中，避免超长行难以阅读。
        body: ContentFrame(maxWidth: 1100, child: _buildBody(scheme)),
        ),
      ),
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
            onEditAsSource: _editBlockAsSource,
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: MarkdownView(
        content: content,
        onToggleTask: _toggleTask,
        selectable: true,
      ),
    );
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
