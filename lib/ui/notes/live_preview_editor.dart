import 'package:flutter/material.dart';

import 'editor_strings.dart';
import 'markdown_blocks.dart';
import 'markdown_toolbar.dart';
import 'markdown_view.dart';

/// 实时预览（Live Preview）编辑器。
///
/// 灵感来自 Obsidian：正文始终以渲染态呈现，**点按某个段落**时只把该段
/// 展开为 Markdown 源码供就地编辑，其余段落保持渲染；点空白处或「完成」
/// 收起源码，回到渲染态。任务列表的复选框在渲染态可直接勾选。
///
/// 数据流：本组件不持有整篇正文，而是直接读写传入的 [controller]；
/// 编辑某段时把该段源码写回整篇正文对应的偏移区间，因此保存、字数统计、
/// 未保存拦截等既有逻辑全部复用。
class LivePreviewEditor extends StatefulWidget {
  const LivePreviewEditor({
    super.key,
    required this.controller,
    this.onToggleTask,
    this.onEditAsSource,
  });

  /// 整篇笔记正文的控制器（与源码模式共用）。
  final TextEditingController controller;

  /// 切换任务复选框；参数为全篇任务项序号。
  final ValueChanged<int>? onToggleTask;

  /// 「切到源码」入口：把某段的源码范围交给上层，在源码模式里继续编辑。
  final ValueChanged<MarkdownBlock>? onEditAsSource;

  @override
  State<LivePreviewEditor> createState() => _LivePreviewEditorState();
}

class _LivePreviewEditorState extends State<LivePreviewEditor> {
  static const double _horizontalPadding = 20;

  final TextEditingController _blockController = TextEditingController();
  final FocusNode _blockFocus = FocusNode();
  final GlobalKey _activeKey = GlobalKey();

  /// 正在编辑的段的起始偏移；为空表示全部处于渲染态。
  int? _activeStart;
  String _lastCommittedText = '';

  @override
  void initState() {
    super.initState();
    _blockController.addListener(_commitBlockEdit);
    _blockFocus.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _blockController
      ..removeListener(_commitBlockEdit)
      ..dispose();
    _blockFocus
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_blockFocus.hasFocus && _activeStart != null) {
      _deactivate(scrollToTop: false);
    }
  }

  /// 外部（或本组件内置复选框）改动了整篇正文：放弃当前段编辑，重新解析。
  void _deactivate({bool scrollToTop = true}) {
    if (_activeStart == null) return;
    setState(() {
      _activeStart = null;
      _lastCommittedText = '';
    });
    if (scrollToTop) _blockFocus.unfocus();
  }

  void _activate(MarkdownBlock block) {
    if (_activeStart == block.start) return;
    // 先收起上一段（写入整篇正文），再展开新段落。
    _commitBlockEdit();
    setState(() {
      _activeStart = block.start;
      _lastCommittedText = block.text;
    });
    _blockController.value = TextEditingValue(
      text: block.text,
      selection: TextSelection.collapsed(offset: block.text.length),
    );
    _blockFocus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _activeKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 勾选任务复选框：先提交当前段落，再同步展开中的段落到勾选后的源码，
  /// 避免下一次按键用旧文本把勾选结果覆盖掉。
  void _toggleTask(int index) {
    _commitBlockEdit();
    final activeStart = _activeStart;
    final previousText = _blockController.text;
    widget.onToggleTask?.call(index);
    if (activeStart == null) return;
    final match =
        splitMarkdownBlocks(
          widget.controller.text,
        ).where((block) => block.start == activeStart).firstOrNull;
    if (match == null) {
      _deactivate(scrollToTop: false);
      return;
    }
    if (match.text == previousText) return;
    final selection = _blockController.selection;
    _lastCommittedText = match.text;
    _blockController.value = TextEditingValue(
      text: match.text,
      selection:
          selection.isValid && selection.end <= match.text.length
              ? selection
              : TextSelection.collapsed(offset: match.text.length),
    );
  }

  /// 把当前段落的源码写回整篇正文。
  void _commitBlockEdit() {
    final start = _activeStart;
    if (start == null) return;
    final document = widget.controller.text;
    final expectedEnd = start + _lastCommittedText.length;
    // 整篇正文被外部改动（例如勾选别处的复选框）导致偏移失效时，
    // 放弃本次段落编辑，避免覆盖别人的修改。
    if (expectedEnd > document.length ||
        document.substring(start, expectedEnd) != _lastCommittedText) {
      _deactivate(scrollToTop: false);
      return;
    }
    final text = _blockController.text;
    if (text == _lastCommittedText) return;
    final newDocument = document.replaceRange(start, expectedEnd, text);
    _lastCommittedText = text;
    widget.controller.value = TextEditingValue(
      text: newDocument,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocks = splitMarkdownBlocks(widget.controller.text);
    if (blocks.isEmpty) {
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
    final scheme = Theme.of(context).colorScheme;
    final active = _activeStart;
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            // 点按渲染态的空白处收起源码；具体段落由各自的手势优先处理。
            onTap: _blockFocus.unfocus,
            behavior: HitTestBehavior.translucent,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                _horizontalPadding,
                8,
                _horizontalPadding,
                32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final block in blocks)
                    if (active != null &&
                        block.start <= active &&
                        active < block.end)
                      _buildBlockEditor(block, scheme)
                    else
                      _buildRenderedBlock(block),
                ],
              ),
            ),
          ),
        ),
        if (active != null)
          MarkdownToolbar(controller: _blockController, focusNode: _blockFocus),
      ],
    );
  }

  Widget _buildRenderedBlock(MarkdownBlock block) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _activate(block),
      borderRadius: BorderRadius.circular(8),
      hoverColor: scheme.primary.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: MarkdownView(
          content: block.text,
          taskStartIndex: block.taskOffset,
          onTapText: () => _activate(block),
          onToggleTask: _toggleTask,
        ),
      ),
    );
  }

  Widget _buildBlockEditor(MarkdownBlock block, ColorScheme scheme) {
    return Container(
      key: _activeKey,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.edit_note_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  EditorStrings.liveEditingBlock,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: scheme.primary),
                ),
                const Spacer(),
                if (widget.onEditAsSource != null)
                  TextButton(
                    onPressed: () {
                      _commitBlockEdit();
                      widget.onEditAsSource!(block);
                    },
                    child: const Text(EditorStrings.liveSourceToggle),
                  ),
                TextButton(
                  onPressed: () => _blockFocus.unfocus(),
                  child: const Text(EditorStrings.liveDone),
                ),
              ],
            ),
          ),
          TextField(
            controller: _blockController,
            focusNode: _blockFocus,
            maxLines: null,
            minLines: 2,
            autofocus: true,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14.5,
              height: 1.6,
            ),
            decoration: InputDecoration(
              hintText: EditorStrings.contentHint,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            ),
          ),
        ],
      ),
    );
  }
}
