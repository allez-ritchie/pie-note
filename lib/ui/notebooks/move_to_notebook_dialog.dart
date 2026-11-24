import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_models.dart';
import '../../state/providers.dart';
import '../common/strings.dart';
import '../common/widgets.dart';
import 'notes_strings.dart';

/// 「移至笔记本」对话框的返回值。
///
/// - `notebookId == null` 表示移到「全部笔记」（不属于任何笔记本）；
/// - [notebookName] 只用于提示文案，`null` 时用 [NotesStrings.moveToAllNotes]。
@immutable
class MoveTarget {
  const MoveTarget({this.notebookId, this.notebookName});

  final String? notebookId;
  final String? notebookName;

  String get label => notebookName ?? NotesStrings.moveToAllNotes;

  bool get isAllNotes => notebookId == null;
}

/// 打开「移至笔记本」选择框。
///
/// [currentNotebookId] 用于标记当前所在笔记本；[excludeNotebookId] 用于
/// 批量移动时剔除「已经在目标里」的歧义场景。用户取消时返回 null。
Future<MoveTarget?> showMoveToNotebookDialog(
  BuildContext context, {
  String? currentNotebookId,
  String? title,
  String? message,
  String confirmLabel = NotesStrings.moveConfirm,
}) {
  return showDialog<MoveTarget>(
    context: context,
    builder: (_) => _MoveToNotebookDialog(
      currentNotebookId: currentNotebookId,
      title: title ?? NotesStrings.moveDialogTitle,
      message: message ?? NotesStrings.moveDialogMessage,
      confirmLabel: confirmLabel,
    ),
  );
}

class _MoveToNotebookDialog extends ConsumerStatefulWidget {
  const _MoveToNotebookDialog({
    required this.currentNotebookId,
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  final String? currentNotebookId;
  final String title;
  final String message;
  final String confirmLabel;

  @override
  ConsumerState<_MoveToNotebookDialog> createState() =>
      _MoveToNotebookDialogState();
}

class _MoveToNotebookDialogState extends ConsumerState<_MoveToNotebookDialog> {
  /// `null` 表示「全部笔记」；当前所在笔记本的选项会标记为「已在该笔记本中」。
  String? _selectedId;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final notebooksAsync = ref.watch(notebooksProvider);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: notebooksAsync.when(
          loading: () => const SizedBox(
            height: 120,
            child: AppLoadingView(message: S.loading, compact: true),
          ),
          error: (error, _) => AppErrorView(
            message: describeError(error),
            compact: true,
            onRetry: () => ref.invalidate(notebooksProvider),
          ),
          data: (notebooks) {
            final active = notebooks
                .where((notebook) => !notebook.archived)
                .toList(growable: false);
            _initialized = true;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  NotesStrings.moveNote,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: RadioGroup<String?>(
                      groupValue: _selectedId,
                      onChanged: (value) => setState(() => _selectedId = value),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const RadioListTile<String?>(
                            value: null,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(NotesStrings.moveToAllNotes),
                          ),
                          if (active.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Column(
                                children: [
                                  Text(
                                    NotesStrings.moveEmptyTitle,
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    NotesStrings.moveEmptyMessage,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            )
                          else
                            ...active.map(
                              (notebook) => _NotebookOption(
                                notebook: notebook,
                                selected: _selectedId == notebook.id,
                                isCurrent: widget.currentNotebookId == notebook.id,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(S.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _initialized
              ? () {
                  if (_selectedId == null) {
                    Navigator.of(context).pop(const MoveTarget());
                    return;
                  }
                  final notebooks = ref.read(notebooksProvider).valueOrNull;
                  final matched = notebooks?.firstWhere(
                    (notebook) => notebook.id == _selectedId,
                    orElse: () => _fallbackNotebook(_selectedId!),
                  );
                  Navigator.of(context).pop(
                    MoveTarget(
                      notebookId: _selectedId,
                      notebookName: matched?.name,
                    ),
                  );
                }
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }

  /// `notebooksProvider` 数据突然变化时的兜底（正常情况下不会走到）。
  static Notebook _fallbackNotebook(String id) => Notebook(
        id: id,
        name: id,
        description: '',
        archived: false,
        created: null,
        updated: null,
        noteCount: 0,
        sourceCount: 0,
      );
}

class _NotebookOption extends StatelessWidget {
  const _NotebookOption({
    required this.notebook,
    required this.selected,
    required this.isCurrent,
  });

  final Notebook notebook;
  final bool selected;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 泛型必须与 RadioGroup<String?> 一致，否则 RadioGroup.maybeOf 找不到
    // 分组，点击不会改变选中项（组里有一个 null 值代表「全部笔记」）。
    return RadioListTile<String?>(
      value: notebook.id,
      dense: true,
      contentPadding: EdgeInsets.zero,
      selected: selected,
      title: Text(notebook.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: isCurrent
          ? Text(
              NotesStrings.moveSameNotebookHint,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            )
          : null,
      secondary: Text(
        '${notebook.noteCount} ${S.noteUnit}',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
