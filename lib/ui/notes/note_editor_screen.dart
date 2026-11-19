import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/strings.dart';
import '../common/widgets.dart';
import 'editor_strings.dart';
import 'markdown_view.dart';

enum _LeaveAction { save, discard, cancel }

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
  bool _preview = false;
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
  // Markdown 工具条编辑操作
  // ---------------------------------------------------------------------------

  void _insertInline(String prefix, String suffix, {String placeholder = ''}) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final selected = text.substring(start, end);
    final body = selected.isEmpty ? placeholder : selected;
    final newText = text.replaceRange(start, end, '$prefix$body$suffix');
    final int cursor;
    int selectionStart = -1;
    int selectionEnd = -1;
    if (selected.isEmpty && placeholder.isNotEmpty) {
      selectionStart = start + prefix.length;
      selectionEnd = selectionStart + placeholder.length;
      cursor = selectionEnd;
    } else {
      cursor = start + prefix.length + body.length + suffix.length;
    }
    _contentController.value = TextEditingValue(
      text: newText,
      selection: selectionStart >= 0
          ? TextSelection(baseOffset: selectionStart, extentOffset: selectionEnd)
          : TextSelection.collapsed(offset: cursor),
    );
    _contentFocus.requestFocus();
  }

  void _toggleLinePrefix(String prefix) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final cursor = selection.isValid ? selection.start : text.length;
    final previousBreak = text.lastIndexOf('\n', cursor == 0 ? 0 : cursor - 1);
    final lineStart = previousBreak == -1 ? 0 : previousBreak + 1;
    final nextBreak = text.indexOf('\n', cursor);
    final lineEnd = nextBreak == -1 ? text.length : nextBreak;
    final line = text.substring(lineStart, lineEnd);
    final newLine = line.startsWith(prefix)
        ? line.substring(prefix.length)
        : '$prefix$line';
    final newText = text.replaceRange(lineStart, lineEnd, newLine);
    final offset = (cursor + (newLine.length - line.length)).clamp(0, newText.length);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: offset),
    );
    _contentFocus.requestFocus();
  }

  void _insertCodeBlock() {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final selected = text.substring(start, end);
    final needsLeadingBreak = start > 0 && text[start - 1] != '\n';
    final insertion = '${needsLeadingBreak ? '\n' : ''}```\n$selected\n```\n';
    final newText = text.replaceRange(start, end, insertion);
    final offset = start + insertion.length;
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: offset.clamp(0, newText.length)),
    );
    _contentFocus.requestFocus();
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
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: S.back,
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _handleBack,
          ),
          title: Text(_noteId == null ? EditorStrings.newNote : '编辑笔记'),
          actions: [
            IconButton(
              tooltip: _preview ? EditorStrings.edit : EditorStrings.preview,
              onPressed: () => setState(() => _preview = !_preview),
              icon: Icon(
                _preview
                    ? Icons.edit_outlined
                    : Icons.visibility_outlined,
              ),
            ),
            Badge(
              isLabelVisible: _dirty,
              smallSize: 8,
              child: IconButton(
                tooltip: EditorStrings.save,
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
        body: _buildBody(scheme),
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
                  '未保存',
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
              Text(
                '${_contentController.text.length} 字',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _preview ? _buildPreview() : _buildEditor(scheme),
        ),
        if (!_preview) _MarkdownToolbar(state: this),
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
      child: MarkdownView(content: content),
    );
  }
}

/// 编辑模式下的 Markdown 快捷工具条。
class _MarkdownToolbar extends StatelessWidget {
  const _MarkdownToolbar({required this.state});

  final _NoteEditorScreenState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            children: [
              _ToolTextButton(
                label: 'H1',
                tooltip: EditorStrings.toolH1,
                onTap: () => state._toggleLinePrefix('# '),
              ),
              _ToolTextButton(
                label: 'H2',
                tooltip: EditorStrings.toolH2,
                onTap: () => state._toggleLinePrefix('## '),
              ),
              _ToolIconButton(
                icon: Icons.format_bold_rounded,
                tooltip: EditorStrings.toolBold,
                onTap: () => state._insertInline('**', '**', placeholder: '加粗文本'),
              ),
              _ToolIconButton(
                icon: Icons.format_italic_rounded,
                tooltip: EditorStrings.toolItalic,
                onTap: () => state._insertInline('*', '*', placeholder: '斜体文本'),
              ),
              _ToolIconButton(
                icon: Icons.format_strikethrough_rounded,
                tooltip: EditorStrings.toolStrike,
                onTap: () => state._insertInline('~~', '~~', placeholder: '删除文本'),
              ),
              _ToolIconButton(
                icon: Icons.code_rounded,
                tooltip: EditorStrings.toolCode,
                onTap: () => state._insertInline('`', '`', placeholder: 'code'),
              ),
              _ToolIconButton(
                icon: Icons.data_object_rounded,
                tooltip: EditorStrings.toolCodeBlock,
                onTap: state._insertCodeBlock,
              ),
              _ToolIconButton(
                icon: Icons.format_list_bulleted_rounded,
                tooltip: EditorStrings.toolBullet,
                onTap: () => state._toggleLinePrefix('- '),
              ),
              _ToolIconButton(
                icon: Icons.format_list_numbered_rounded,
                tooltip: EditorStrings.toolNumbered,
                onTap: () => state._toggleLinePrefix('1. '),
              ),
              _ToolIconButton(
                icon: Icons.format_quote_rounded,
                tooltip: EditorStrings.toolQuote,
                onTap: () => state._toggleLinePrefix('> '),
              ),
              _ToolIconButton(
                icon: Icons.check_box_outlined,
                tooltip: EditorStrings.toolCheckbox,
                onTap: () => state._toggleLinePrefix('- [ ] '),
              ),
              _ToolIconButton(
                icon: Icons.link_rounded,
                tooltip: EditorStrings.toolLink,
                onTap: () => state._insertInline('[', '](https://)', placeholder: '链接文本'),
              ),
              _ToolTextButton(
                label: '[[ ]]',
                tooltip: EditorStrings.toolWiki,
                onTap: () => state._insertInline('[[', ']]', placeholder: '笔记标题'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolIconButton extends StatelessWidget {
  const _ToolIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      iconSize: 21,
      icon: Icon(icon),
    );
  }
}

class _ToolTextButton extends StatelessWidget {
  const _ToolTextButton({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 44,
          height: 52,
          alignment: Alignment.center,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ),
    );
  }
}
