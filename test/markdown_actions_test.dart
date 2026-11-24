import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pie_note/ui/notes/markdown_actions.dart';

TextEditingController _controller(String text, [TextSelection? selection]) {
  final controller = TextEditingController(text: text);
  if (selection != null) controller.selection = selection;
  return controller;
}

void main() {
  group('toggleLinePrefix 单行（既有行为）', () {
    test('光标所在行没有前缀时添加，有前缀时移除', () {
      final controller = _controller(
        '正文一行\n第二行',
        const TextSelection.collapsed(offset: 7), // 第二行末尾
      );
      MarkdownActions.toggleLinePrefix(controller, '## ');
      expect(controller.text, '正文一行\n## 第二行');
      expect(controller.selection.isCollapsed, isTrue);
      expect(controller.selection.baseOffset, 10);

      MarkdownActions.toggleLinePrefix(controller, '## ');
      expect(controller.text, '正文一行\n第二行');
      expect(controller.selection.baseOffset, 7);
    });
  });

  group('toggleLinePrefix 多行选区', () {
    test('选中多行时每一行都加前缀，且保留整段选区', () {
      final controller = _controller(
        '第一行\n第二行\n第三行',
        const TextSelection(baseOffset: 0, extentOffset: 7),
      );
      MarkdownActions.toggleLinePrefix(controller, '# ');
      expect(controller.text, '# 第一行\n# 第二行\n第三行');
      // 选区仍然覆盖被改写的两行（'# 第一行\n# 第二行'），方便继续操作。
      expect(controller.selection.start, 0);
      expect(controller.selection.end, 11);
    });

    test('选中多行且全部已有前缀时整体移除', () {
      final controller = _controller(
        '- 甲\n- 乙\n丙',
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      MarkdownActions.toggleLinePrefix(controller, '- ');
      expect(controller.text, '甲\n乙\n丙');
      expect(controller.selection.start, 0);
      expect(controller.selection.end, 3);
    });

    test('部分行已有前缀时只补齐缺的，不做「先删再加」', () {
      final controller = _controller(
        '- 甲\n乙\n- 丙',
        const TextSelection(baseOffset: 0, extentOffset: 8),
      );
      MarkdownActions.toggleLinePrefix(controller, '- ');
      expect(controller.text, '- 甲\n- 乙\n- 丙');
    });

    test('反向选区（从下往上选）同样生效', () {
      final controller = _controller(
        'AA\nBB',
        const TextSelection(baseOffset: 5, extentOffset: 0),
      );
      MarkdownActions.toggleLinePrefix(controller, '# ');
      expect(controller.text, '# AA\n# BB');
      // 方向保持：仍然是从下往上选。
      expect(controller.selection.baseOffset, greaterThan(controller.selection.extentOffset));
    });

    test('选区恰好结束在下一行行首时不含该行', () {
      final controller = _controller(
        '甲\n乙\n丙',
        // 覆盖「甲」和它后面的换行，但没有选中「乙」
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
      MarkdownActions.toggleLinePrefix(controller, '- ');
      expect(controller.text, '- 甲\n乙\n丙');
    });

    test('选中多行后连续点两个工具按钮，选区不缩水', () {
      final controller = _controller(
        '甲\n乙',
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
      MarkdownActions.toggleLinePrefix(controller, '- ');
      expect(controller.text, '- 甲\n- 乙');
      // 第二次点同一个按钮：整个选区仍然是两行，因此应整体移除。
      MarkdownActions.toggleLinePrefix(controller, '- ');
      expect(controller.text, '甲\n乙');
    });

    test('空行不塞前缀，避免产生空洞列表项', () {
      final controller = _controller(
        '甲\n\n乙',
        const TextSelection(baseOffset: 0, extentOffset: 4),
      );
      MarkdownActions.toggleLinePrefix(controller, '- ');
      expect(controller.text, '- 甲\n\n- 乙');
    });
  });
}
