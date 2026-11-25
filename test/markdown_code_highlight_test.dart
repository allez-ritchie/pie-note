import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pie_note/ui/notes/markdown_code_block.dart';
import 'package:pie_note/ui/notes/markdown_code_highlight.dart';
import 'package:pie_note/ui/theme/app_theme.dart';

void main() {
  group('语言识别', () {
    test('info string 归一化：忽略大小写与首尾空白', () {
      expect(normalizeLanguage('Python'), 'python');
      expect(normalizeLanguage('  PYTHON  '), 'python');
      expect(normalizeLanguage(''), isEmpty);
      expect(normalizeLanguage('   '), isEmpty);
    });

    test('常用语言别名（js / sh / yml / c++）都能解析', () {
      final highlighter = MarkdownCodeHighlighter.instance;
      for (final alias in ['js', 'ts', 'py', 'sh', 'yml', 'c++', 'c#', 'rs', 'kt']) {
        expect(
          highlighter.isKnownLanguage(alias),
          isTrue,
          reason: '别名 $alias 应该能解析到具体语言',
        );
      }
    });

    test('未收录的语言不抛异常，只是不高亮', () {
      expect(
        MarkdownCodeHighlighter.instance.isKnownLanguage('brainfuck-unknown'),
        isFalse,
      );
    });
  });

  group('分词结果', () {
    const base = TextStyle(fontFamily: 'monospace', fontSize: 13.5);

    /// 收集 span 里出现过的所有非空颜色（即真正被染色的 token）。
    Set<Color> colorsOf(List<TextSpan> spans) {
      final colors = <Color>{};
      for (final span in spans) {
        final color = span.style?.color;
        if (color != null && span.text != null && span.text!.trim().isNotEmpty) {
          colors.add(color);
        }
      }
      return colors;
    }

    test('Python 的关键字 / 字符串 / 注释颜色互不相同', () {
      const code = 'def f(x):\n    """doc"""\n    return x  # 注释\n';
      final spans = MarkdownCodeHighlighter.instance.spansFor(
        code,
        'python',
        baseStyle: base,
        brightness: Brightness.light,
      );
      expect(spans, isNotNull);
      // 拼回去必须与原文完全一致，不能吞字、不能改换行。
      expect(spans!.map((span) => span.text).join(), code);
      expect(colorsOf(spans).length, greaterThanOrEqualTo(3));
    });

    test('未知语言返回 null（调用方退回单色文本）', () {
      expect(
        MarkdownCodeHighlighter.instance.spansFor(
          'x = 1',
          'not-a-language',
          baseStyle: base,
          brightness: Brightness.light,
        ),
        isNull,
      );
    });

    test('没写语言返回 null（纯文本不该被猜语言）', () {
      expect(
        MarkdownCodeHighlighter.instance.spansFor(
          'x = 1',
          '',
          baseStyle: base,
          brightness: Brightness.light,
        ),
        isNull,
      );
    });

    test('超长代码块退回纯文本，避免分词卡住滚动', () {
      final long = 'x = 1\n' * (MarkdownCodeHighlighter.maxHighlightChars ~/ 6 + 10);
      expect(
        MarkdownCodeHighlighter.instance.spansFor(
          long,
          'python',
          baseStyle: base,
          brightness: Brightness.light,
        ),
        isNull,
      );
    });

    test('同样的代码第二次命中缓存，返回同一份 span 列表', () {
      const code = 'const a = 1; // x';
      final first = MarkdownCodeHighlighter.instance.spansFor(
        code,
        'js',
        baseStyle: base,
        brightness: Brightness.light,
      );
      final second = MarkdownCodeHighlighter.instance.spansFor(
        code,
        'js',
        baseStyle: base,
        brightness: Brightness.light,
      );
      expect(identical(first, second), isTrue);
    });

    test('深浅两套配色的同一段代码颜色不同', () {
      const code = 'def f(): pass  # 注释';
      final light = MarkdownCodeHighlighter.instance.spansFor(
        code,
        'python',
        baseStyle: base,
        brightness: Brightness.light,
      )!;
      final dark = MarkdownCodeHighlighter.instance.spansFor(
        code,
        'python',
        baseStyle: base,
        brightness: Brightness.dark,
      )!;
      expect(colorsOf(light), isNot(equals(colorsOf(dark))));
    });
  });

  group('WCAG AA 对比度', () {
    test('浅色主题每个 token 颜色在代码块底色上都 >= 4.5:1', () {
      final theme = AppTheme.light();
      final background = markdownCodeBlockBackground(theme);
      markdownCodeLightTheme.forEach((name, style) {
        final color = style.color;
        if (color == null) return;
        expect(
          markdownContrastRatio(color, background),
          greaterThanOrEqualTo(4.5),
          reason: '$name 的对比度不足',
        );
      });
    });

    test('深色主题每个 token 颜色在代码块底色上都 >= 4.5:1', () {
      final theme = AppTheme.dark();
      final background = markdownCodeBlockBackground(theme);
      markdownCodeDarkTheme.forEach((name, style) {
        final color = style.color;
        if (color == null) return;
        expect(
          markdownContrastRatio(color, background),
          greaterThanOrEqualTo(4.5),
          reason: '$name 的对比度不足',
        );
      });
    });
  });
}

/// WCAG 2.1 的相对亮度。
double _relativeLuminance(Color color) {
  double linear(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * linear(color.r) +
      0.7152 * linear(color.g) +
      0.0722 * linear(color.b);
}

/// 两色的对比度（1:1 ~ 21:1）；4.5 是 WCAG AA 对正文的最低要求。
double markdownContrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
