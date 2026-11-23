import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/api_models.dart';
import '../../state/providers.dart';
import '../common/strings.dart';
import '../common/widgets.dart';
import 'sources_strings.dart';

/// 添加来源对话框的提交结果。
enum AddSourceOutcome {
  /// 已提交（后台可能仍在处理）。
  submitted,

  /// 用户取消 / 关闭。
  cancelled,
}

/// 打开「添加来源」对话框。
///
/// [defaultNotebookId] 是当前浏览的笔记本，会被默认勾选；`null` 表示「全部
/// 来源」入口，此时不默认勾选任何笔记本（用户可自行选择）。
Future<AddSourceOutcome?> showAddSourceDialog(
  BuildContext context, {
  String? defaultNotebookId,
}) {
  return showDialog<AddSourceOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AddSourceDialog(defaultNotebookId: defaultNotebookId),
  );
}

/// 「添加来源」表单：链接 / 文本 / 文件三种输入，提交给后端异步处理。
///
/// 提交后对话框切换到进度态，轮询 `GET /api/sources/{id}/status` 直到
/// 处理完成或失败；用户也可以直接关闭对话框，让后端在后台继续。
class AddSourceDialog extends ConsumerStatefulWidget {
  const AddSourceDialog({super.key, this.defaultNotebookId});

  final String? defaultNotebookId;

  @override
  ConsumerState<AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends ConsumerState<AddSourceDialog> {
  SourceInputKind _kind = SourceInputKind.link;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  /// 选中的本地文件（上传类型）。
  XFile? _file;

  /// 已选文件的字节数（`XFile.length()` 是异步的，选文件时取一次缓存下来）。
  int? _fileSize;

  /// 选中的笔记本 id（默认勾选当前笔记本）。
  final Set<String> _notebookIds = <String>{};

  bool _embed = false;
  bool _submitting = false;
  String? _formError;

  /// 提交后的进度：已提交数 / 总数与当前批次提示。
  int _submitted = 0;
  int _total = 0;
  String? _progressHint;
  bool _processing = false;
  String? _processingError;

  Timer? _pollTimer;
  int _pollAttempts = 0;

  /// 轮询上限（3 秒 × 100 ≈ 5 分钟），避免后端卡住时无限轮询。
  static const int _maxPollAttempts = 100;
  static const Duration _pollInterval = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    final initial = widget.defaultNotebookId;
    if (initial != null) _notebookIds.add(initial);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _titleController.dispose();
    _urlController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 表单
  // ---------------------------------------------------------------------------

  /// 校验并返回待提交的请求列表；校验失败时设置 [_formError] 并返回空。
  List<CreateSourceRequest> _buildRequests() {
    _formError = null;
    final title = _titleController.text.trim();
    final notebookIds = _notebookIds.toList(growable: false);

    switch (_kind) {
      case SourceInputKind.link:
        final urls = _urlController.text
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList(growable: false);
        if (urls.isEmpty) {
          _formError = SourcesStrings.addUrlRequired;
          return const [];
        }
        for (final url in urls) {
          final uri = Uri.tryParse(url);
          if (uri == null ||
              !(uri.scheme == 'http' || uri.scheme == 'https') ||
              uri.host.isEmpty) {
            _formError = SourcesStrings.addUrlInvalid;
            return const [];
          }
        }
        return [
          for (final url in urls)
            CreateSourceRequest(
              kind: SourceInputKind.link,
              url: url,
              title: title.isEmpty ? null : title,
              notebookIds: notebookIds,
              embed: _embed,
            ),
        ];

      case SourceInputKind.text:
        final content = _contentController.text.trim();
        if (content.isEmpty) {
          _formError = SourcesStrings.addContentRequired;
          return const [];
        }
        if (title.isEmpty) {
          _formError = SourcesStrings.addTitleRequired;
          return const [];
        }
        return [
          CreateSourceRequest(
            kind: SourceInputKind.text,
            content: content,
            title: title,
            notebookIds: notebookIds,
            embed: _embed,
          ),
        ];

      case SourceInputKind.upload:
        final file = _file;
        if (file == null) {
          _formError = SourcesStrings.addFileRequired;
          return const [];
        }
        return [
          CreateSourceRequest(
            kind: SourceInputKind.upload,
            filePath: file.path,
            fileName: file.name,
            title: title.isEmpty ? null : title,
            notebookIds: notebookIds,
            embed: _embed,
          ),
        ];
    }
  }

  Future<void> _pickFile() async {
    try {
      final file = await openFile();
      if (!mounted || file == null) return;
      int? size;
      try {
        size = await file.length();
      } catch (_) {
        // 拿不到大小只影响展示，不影响上传。
      }
      if (!mounted) return;
      setState(() {
        _file = file;
        _fileSize = size;
        _formError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _formError = SourcesStrings.pickFileFailed);
    }
  }

  // ---------------------------------------------------------------------------
  // 提交与轮询
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    if (_submitting) return;
    final requests = _buildRequests();
    if (requests.isEmpty) {
      setState(() {});
      return;
    }
    final repository = ref.read(sourceRepositoryProvider);
    if (repository == null) {
      setState(() => _formError = S.notConfiguredMessage);
      return;
    }

    setState(() {
      _submitting = true;
      _formError = null;
      _submitted = 0;
      _total = requests.length;
      _processing = true;
      _processingError = null;
      _progressHint = SourcesStrings.addSubmitting;
    });

    final createdIds = <String>[];
    Object? firstError;
    for (final request in requests) {
      try {
        final source = await repository.createSource(request);
        createdIds.add(source.id);
        if (mounted) {
          setState(() {
            _submitted += 1;
            _progressHint = SourcesStrings.addProcessing;
          });
        }
      } catch (error) {
        firstError ??= error;
      }
    }

    if (!mounted) return;
    // 列表与笔记本计数都可能变化。
    ref.invalidate(sourcesProvider(widget.defaultNotebookId));
    ref.invalidate(notebooksProvider);

    if (createdIds.isEmpty) {
      setState(() {
        _submitting = false;
        _processing = false;
        _processingError = describeError(firstError ?? Object());
      });
      return;
    }
    setState(() {
      _submitting = false;
      _progressHint = SourcesStrings.addProcessing;
    });
    _startPolling(createdIds);
  }

  void _startPolling(List<String> sourceIds) {
    _pollTimer?.cancel();
    _pollAttempts = 0;
    _pollTimer = Timer.periodic(_pollInterval, (timer) async {
      _pollAttempts += 1;
      final repository = ref.read(sourceRepositoryProvider);
      if (repository == null || _pollAttempts > _maxPollAttempts) {
        timer.cancel();
        if (mounted) setState(() => _processing = false);
        return;
      }
      var pending = false;
      String? failure;
      for (final id in sourceIds) {
        try {
          final status = await repository.fetchStatus(id);
          if (status.status == SourceStatus.failed) {
            failure ??= status.message;
          } else if (status.status == SourceStatus.newSource ||
              status.status == SourceStatus.queued ||
              status.status == SourceStatus.running ||
              status.status == SourceStatus.unknown) {
            pending = true;
          }
        } on ApiException {
          // 状态接口偶发失败不终止轮询，下一轮再试。
          pending = true;
        }
      }
      if (!mounted) return;
      if (pending) {
        setState(() {
          _processing = true;
          _progressHint = SourcesStrings.addProcessing;
        });
        return;
      }
      timer.cancel();
      setState(() {
        _processing = false;
        _progressHint = SourcesStrings.addDone;
        _processingError = failure;
      });
      ref.invalidate(sourcesProvider(widget.defaultNotebookId));
    });
  }

  void _close() {
    _pollTimer?.cancel();
    Navigator.of(context).pop(
      _submitted > 0 ? AddSourceOutcome.submitted : AddSourceOutcome.cancelled,
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notebooksAsync = ref.watch(notebooksProvider);
    final notebooks = notebooksAsync.valueOrNull ?? const <Notebook>[];
    final submitted = _submitted > 0;

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text(SourcesStrings.addTitle)),
          if (submitted)
            Icon(Icons.cloud_done_rounded, color: scheme.primary, size: 22),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: submitted
              ? _buildProgress(theme)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      SourcesStrings.addSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<SourceInputKind>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: SourceInputKind.link,
                          icon: Icon(Icons.link_rounded, size: 18),
                          label: Text(SourcesStrings.typeLink),
                        ),
                        ButtonSegment(
                          value: SourceInputKind.text,
                          icon: Icon(Icons.subject_rounded, size: 18),
                          label: Text(SourcesStrings.typeText),
                        ),
                        ButtonSegment(
                          value: SourceInputKind.upload,
                          icon: Icon(Icons.upload_file_rounded, size: 18),
                          label: Text(SourcesStrings.typeUpload),
                        ),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (selection) => setState(() {
                        _kind = selection.first;
                        _formError = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    if (_kind == SourceInputKind.upload) ...[
                      _FilePickerField(
                        file: _file,
                        fileSize: _fileSize,
                        onPick: _pickFile,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _buildTitleField(),
                    const SizedBox(height: 12),
                    if (_kind == SourceInputKind.link) _buildUrlField(),
                    if (_kind == SourceInputKind.text) _buildContentField(),
                    const SizedBox(height: 16),
                    Text(
                      SourcesStrings.addNotebooksLabel,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    if (notebooks.isEmpty)
                      Text(
                        SourcesStrings.addNotebooksEmpty,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final notebook in notebooks)
                            FilterChip(
                              label: Text(
                                notebook.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              selected: _notebookIds.contains(notebook.id),
                              onSelected: (selected) => setState(() {
                                if (selected) {
                                  _notebookIds.add(notebook.id);
                                } else {
                                  _notebookIds.remove(notebook.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _embed,
                      onChanged: (value) => setState(() => _embed = value),
                      title: const Text(SourcesStrings.addEmbedLabel),
                      subtitle: Text(
                        SourcesStrings.addEmbedHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (_formError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _formError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
      actions: submitted
          ? [
              TextButton(
                onPressed: _close,
                child: const Text(SourcesStrings.addClose),
              ),
            ]
          : [
              TextButton(
                onPressed: _submitting ? null : _close,
                child: const Text(S.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _total > 1
                                ? SourcesStrings.submittedCount(_submitted, _total)
                                : SourcesStrings.addSubmitting,
                          ),
                        ],
                      )
                    : const Text(SourcesStrings.addSubmit),
              ),
            ],
    );
  }

  Widget _buildTitleField() {
    return TextField(
      controller: _titleController,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        isDense: true,
        labelText: SourcesStrings.addTitleLabel,
        hintText: SourcesStrings.addTitleHint,
        helperText: _kind == SourceInputKind.text
            ? '文本来源需要标题（也会作为列表里的展示名）'
            : null,
      ),
    );
  }

  Widget _buildUrlField() {
    return TextField(
      controller: _urlController,
      minLines: 2,
      maxLines: 4,
      keyboardType: TextInputType.url,
      decoration: const InputDecoration(
        isDense: true,
        labelText: SourcesStrings.addUrlLabel,
        hintText: SourcesStrings.addUrlHint,
        alignLabelWithHint: true,
      ),
    );
  }

  Widget _buildContentField() {
    return TextField(
      controller: _contentController,
      minLines: 5,
      maxLines: 10,
      keyboardType: TextInputType.multiline,
      decoration: const InputDecoration(
        isDense: true,
        labelText: SourcesStrings.addContentLabel,
        hintText: SourcesStrings.addContentHint,
        alignLabelWithHint: true,
      ),
    );
  }

  Widget _buildProgress(ThemeData theme) {
    final scheme = theme.colorScheme;
    final done = !_processing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (_processing)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            else
              Icon(
                _processingError == null
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                color: _processingError == null ? scheme.primary : scheme.error,
                size: 22,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _progressHint ?? SourcesStrings.addProcessing,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        if (_total > 1) ...[
          const SizedBox(height: 10),
          Text(
            SourcesStrings.submittedCount(_submitted, _total),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_processing) ...[
          const SizedBox(height: 10),
          Text(
            SourcesStrings.addProcessingHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _close,
            icon: const Icon(Icons.schedule_rounded, size: 18),
            label: const Text(SourcesStrings.addBackground),
          ),
        ],
        if (done && _processingError != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              SourcesStrings.processingFailed(_processingError!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
                height: 1.45,
              ),
            ),
          ),
        ],
        if (done && _processingError == null) ...[
          const SizedBox(height: 12),
          Text(
            SourcesStrings.addDone,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// 文件选择字段：未选时显示「选择文件」，选好后显示文件名 + 大小 + 更换按钮。
class _FilePickerField extends StatelessWidget {
  const _FilePickerField({
    required this.file,
    required this.fileSize,
    required this.onPick,
  });

  final XFile? file;
  final int? fileSize;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = file;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            current == null ? Icons.attach_file_rounded : Icons.description_rounded,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current?.name ?? SourcesStrings.addFileLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (current != null && fileSize != null)
                  Text(
                    SourcesStrings.addFileSize(_formatSize(fileSize!)),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onPick,
            child: Text(
              current == null
                  ? SourcesStrings.addFileChoose
                  : SourcesStrings.addFileChange,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}
