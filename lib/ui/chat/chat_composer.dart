import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat_strings.dart';

/// 对话输入区：多行输入 + 发送按钮（`Ctrl/Cmd + Enter` 发送）。
///
/// 输入框文本由页面持有（[controller]），生成过程中禁用输入与发送，
/// 但**不清空**已输入内容；发送成功后才由页面清空。
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.sending,
    this.focusNode,
    this.enabled = true,
    this.bottomInset = 0,
    this.hintText = ChatStrings.inputHint,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

  /// 正在等待 AI 回答。
  final bool sending;

  final FocusNode? focusNode;
  final bool enabled;

  /// 底部额外留白（工作区胶囊工具栏）。
  final double bottomInset;

  final String hintText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canSend = enabled && !sending;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomInset),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    // Ctrl/Cmd + Enter 发送；Enter 仍是换行。
                    const SingleActivator(LogicalKeyboardKey.enter, control: true):
                        _sendIfPossible,
                    const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                        _sendIfPossible,
                  },
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled,
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: hintText,
                      isDense: true,
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      helperText: ChatStrings.inputHelper,
                      helperStyle: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: IconButton.filled(
                  tooltip:
                      sending ? ChatStrings.sending : ChatStrings.sendShortcut,
                  onPressed: canSend ? _sendIfPossible : null,
                  icon: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                ),
              ),
            ],
          ),
          if (sending)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.hourglass_top_rounded,
                    size: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ChatStrings.generating,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _sendIfPossible() {
    if (!enabled || sending) return;
    if (controller.text.trim().isEmpty) return;
    onSend();
  }
}
