import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pie_note/ui/notes/markdown_view.dart';


Widget _wrap(String content) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(body: MarkdownView(content: content)),
    ),
  );
}

void main() {
  test('标题上方留白按级别递减，且都明显大于正文行距', () {
    final spacing = [
      for (var level = 1; level <= 6; level++) markdownHeadingTopSpacing(level),
    ];
    for (var i = 1; i < spacing.length; i++) {
      expect(spacing[i], lessThanOrEqualTo(spacing[i - 1]));
    }
    expect(spacing.first, greaterThan(16));
    expect(spacing.last, greaterThanOrEqualTo(8));
  });

  test('只把第一行 ATX 标题识别为标题', () {
    expect(markdownLeadingHeadingLevel('# 标题\n正文'), 1);
    expect(markdownLeadingHeadingLevel('### 三级标题'), 3);
    expect(markdownLeadingHeadingLevel('正文\n# 标题'), isNull);
    expect(markdownLeadingHeadingLevel('#没有空格'), isNull);
    expect(markdownLeadingHeadingLevel('    # 缩进过多'), isNull);
  });

  testWidgets('渲染态标题文字比正文更靠下（上方留白生效）', (tester) async {
    await tester.pumpWidget(_wrap('# 标题'));
    await tester.pumpAndSettle();
    final headingTop = tester.getTopLeft(find.text('标题')).dy;

    await tester.pumpWidget(_wrap('正文'));
    await tester.pumpAndSettle();
    final paragraphTop = tester.getTopLeft(find.text('正文')).dy;

    expect(headingTop - paragraphTop, greaterThan(10));
  });
}
