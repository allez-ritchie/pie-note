import 'package:flutter/material.dart';

import 'editor_strings.dart';
import 'markdown_blocks.dart';
import 'markdown_outline.dart';
import 'markdown_toolbar.dart';
import 'markdown_view.dart';

/// 实时预览（Live Preview）编辑器。
///
/// 灵感来自 Obsidian：正文始终以渲染态呈现，**点按某个段落**时只把该段
/// 就地替换成 Markdown 源码供编辑，其余段落保持渲染。源码不使用卡片/边框
/// 包装、也没有「完成」按钮：点击别处（输入框失焦）即自动收起，回到渲染态。
/// 任务列表的复选框在渲染态可直接勾选。
///
/// 数据流：本组件不持有整篇正文，而是直接读写传入的 [controller]；
/// 编辑某段时把该段源码写回整篇正文对应的偏移区间，因此保存、字数统计、
/// 未保存拦截等既有逻辑全部复用。
class LivePreviewEditor extends StatefulWidget {
  const LivePreviewEditor({
    super.key,
    required this.controller,
    this.onToggleTask,
    this.onBlockActivated,
    this.jump,
  });

  /// 整篇笔记正文的控制器（与源码模式共用）。
  final TextEditingController controller;

  /// 切换任务复选框；参数为全篇任务项序号。
  final ValueChanged<int>? onToggleTask;

  /// 某一段被展开为源码时回调（含其源码起始偏移），供大纲高亮跟随。
  final ValueChanged<MarkdownBlock>? onBlockActivated;

  /// 大纲跳转请求：滚动到该偏移量所在段落。
  final OutlineJumpRequest? jump;

  @override
  State<LivePreviewEditor> createState() => _LivePreviewEditorState();
}

class _LivePreviewEditorState extends State<LivePreviewEditor> {
  static const double _horizontalPadding = 20;

  final TextEditingController _blockController = TextEditingController();
  final FocusNode _blockFocus = FocusNode();

  /// 每个渲染块的 key，用于大纲跳转时定位滚动目标。
  final Map<int, GlobalKey> _blockKeys = <int, GlobalKey>{};

  /// 正在编辑的段的起始偏移；为空表示全部处于渲染态。
  int? _activeStart;
  String _lastCommittedText = '';

  GlobalKey _keyForBlock(int start) =>
      _blockKeys.putIfAbsent(start, () => GlobalKey(debugLabel: 'block-$start'));

  @override
  void initState() {
    super.initState();
    _blockController.addListener(_commitBlockEdit);
    _blockFocus.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant LivePreviewEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final request = widget.jump;
    if (request == null || request == oldWidget.jump) return;
    // 这里不能写回正在编辑的段落：didUpdateWidget 处于 build 阶段，控制器写入会
    // 触发上层的标题/脏标记监听（可能改 provider）。逐字符监听已经把段落实时写回，
    // 因此直接滚动即可。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final blocks = splitMarkdownBlocks(widget.controller.text);
      if (blocks.isEmpty) return;
      final target = blocks
          .where((block) => block.start <= request.offset)
          .lastOrNull ??
          blocks.first;
      final context = _keyForBlock(target.start).currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.02,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
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

  void _activate(int index, MarkdownBlock tapped) {
    if (_activeStart == tapped.start) return;
    // 先收起上一段（写入整篇正文），再解析最新分块定位要展开的段落：
    // 上一段编辑过之后，它后面各块的偏移量都会变化，不能直接沿用点击时的偏移。
    _commitBlockEdit();
    final blocks = splitMarkdownBlocks(widget.controller.text);
    if (blocks.isEmpty) return;
    final block = _locateBlock(blocks, index, tapped);
    setState(() {
      _activeStart = block.start;
      _lastCommittedText = block.text;
    });
    widget.onBlockActivated?.call(block);
    _blockController.value = TextEditingValue(
      text: block.text,
      selection: TextSelection.collapsed(offset: block.text.length),
    );
    _blockFocus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _keyForBlock(block.start).currentContext;
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

  /// 在最新分块里找回被点击的段落。
  ///
  /// 依次尝试：起始偏移 + 文本都没变 → 文本唯一匹配（前面段落长度变化只会让
  /// 偏移整体平移）→ 同一序号 → 最近的一块。渲染态的块文本不会因为别处输入而
  /// 改变，所以正常路径总能精确命中。
  MarkdownBlock _locateBlock(
    List<MarkdownBlock> blocks,
    int index,
    MarkdownBlock tapped,
  ) {
    for (final block in blocks) {
      if (block.start == tapped.start && block.text == tapped.text) {
        return block;
      }
    }
    final sameText = blocks.where((block) => block.text == tapped.text).toList();
    if (sameText.length == 1) return sameText.first;
    if (index >= 0 && index < blocks.length) return blocks[index];
    return blocks.last;
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
    // 正文被改写后偏移量会整体变化，清掉已经不存在的块的 Key，避免 Map 无限增长。
    final starts = {for (final block in blocks) block.start};
    _blockKeys.removeWhere((start, _) => !starts.contains(start));
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
                  for (var index = 0; index < blocks.length; index++)
                    if (active != null &&
                        blocks[index].start <= active &&
                        active < blocks[index].end)
                      _buildInlineEditor(blocks[index])
                    else
                      _buildRenderedBlock(index, blocks[index]),
                ],
              ),
            ),
          ),
        ),
        if (active != null)
          // 工具条也算「输入框的一部分」：点按它不应收起源码编辑。
          TextFieldTapRegion(
            child: MarkdownToolbar(
              controller: _blockController,
              focusNode: _blockFocus,
            ),
          ),
      ],
    );
  }

  Widget _buildRenderedBlock(int index, MarkdownBlock block) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: _keyForBlock(block.start),
      onTap: () => _activate(index, block),
      borderRadius: BorderRadius.circular(8),
      hoverColor: scheme.primary.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: MarkdownView(
          content: block.text,
          taskStartIndex: block.taskOffset,
          onTapText: () => _activate(index, block),
          onToggleTask: _toggleTask,
        ),
      ),
    );
  }

  /// 就地展开的源码输入框。
  ///
  /// 与渲染块共用同一位置、没有边框/底色/标题栏，也没有「完成」按钮：
  /// 界面只会看到这一段的 Markdown 源码，失焦（点按别处）即自动收起。
  Widget _buildInlineEditor(MarkdownBlock block) {
    return TextField(
      key: _keyForBlock(block.start),
      controller: _blockController,
      focusNode: _blockFocus,
      maxLines: null,
      minLines: 1,
      autofocus: true,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      // 默认实现只在桌面端「点按外部」时失焦，移动端触摸不会。这里统一收起，
      // 保证任何平台上点别处都能自然退出源码态；工具条包在
      // [TextFieldTapRegion] 里，点它不算「外部」。
      onTapOutside: (_) => _blockFocus.unfocus(),
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 14.5,
        height: 1.6,
      ),
      decoration: const InputDecoration(
        hintText: EditorStrings.contentHint,
        filled: false,
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: 2),
      ),
    );
  }
}
