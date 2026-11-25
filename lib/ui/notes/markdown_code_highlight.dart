import 'package:flutter/foundation.dart' show Brightness;
import 'package:flutter/painting.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/graphql.dart';
import 'package:re_highlight/languages/groovy.dart';
import 'package:re_highlight/languages/http.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/less.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/nginx.dart';
import 'package:re_highlight/languages/objectivec.dart';
import 'package:re_highlight/languages/perl.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/languages/powershell.dart';
import 'package:re_highlight/languages/protobuf.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/r.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scala.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/shell.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/vim.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

/// 围栏代码块的语法高亮。
///
/// 方案：词法分析交给 [re_highlight]（highlight.js v11.9 的 Dart 移植，规则由
/// highlight.js 官方 grammar 生成），把结果转换成 Flutter 的 [TextSpan]。
///
/// 没有直接用 `re_highlight` 自带的 `TextSpanRenderer`：它的输出是**嵌套**
/// TextSpan（每层 scope 套一层样式），3000 行 JavaScript 要 5.2 万层嵌套、
/// 渲染耗时 50 秒以上（实测 release 模式）。这里改用扁平渲染（每个 token 只有
/// 一层、样式在入栈时合并好），同样的输入耗时 4ms 量级。
///
/// 没有直接用 `flutter_highlight`：它基于 `highlight` 0.7.0，该包 grammar 停在
/// highlight.js 9.x（2021 年）、SDK 约束仍是 `<3.0.0`，不再维护。
class MarkdownCodeHighlighter {
  MarkdownCodeHighlighter._();

  /// 全局单例：grammar 首次使用时才编译并缓存，进程内只编译一次。
  static final MarkdownCodeHighlighter instance = MarkdownCodeHighlighter._();

  final Highlight _engine = Highlight()
    ..registerLanguages(_languages);

  /// 结果缓存：实时预览每次按键都会重建所有渲染块，代码块内容没变时不该
  /// 重新分词。键里带上底色（亮/暗），主题切换后要重新按新配色生成 span。
  final Map<_HighlightKey, List<TextSpan>> _cache =
      <_HighlightKey, List<TextSpan>>{};

  /// 超过这个长度就退回纯文本。
  ///
  /// 分词是**同步**跑在 UI 线程上的（没有用 isolate：结果要转成 TextSpan，跨
  /// isolate 只能传 token 列表再重建，收益抵不过复杂度）。实测 release 模式
  /// 一句一行 JavaScript：1 万字符约 70ms、2 万字符约 165ms、3 万字符约 300ms，
  /// 而笔记里的代码块通常只有几十行。这里把上限压到 8000 字符（约 200 行），
  /// 最坏情况约 60ms（arm 设备再慢一倍也多在一帧到两帧之间），不至于让打开
  /// 笔记明显卡顿；更长的代码块直接单色显示，正文与复制都不受影响。
  static const int maxHighlightChars = 8000;

  /// 已编译过的语言（[Highlight.registerLanguage] 内部会缓存编译结果，
  /// 这里只做「是不是已知语言」的判断，避免未知语言抛 AssertionError）。
  bool isKnownLanguage(String language) =>
      _engine.getLanguage(language) != null;

  /// 把代码切成带样式的 [TextSpan] 列表；[language] 不认识或代码过长时返回 null
  /// （调用方按纯等宽文本渲染）。
  ///
  /// 配色按 [brightness] 自动选择（见 [markdownCodeThemeFor]）。
  ///
  /// 返回扁平列表而不是嵌套 TextSpan：调用方套一个 [TextSpan] 当父节点即可，
  /// 这样 [Text.rich] 只做一次样式继承，不会出现深层嵌套导致的布局爆炸。
  List<TextSpan>? spansFor(
    String code,
    String language, {
    required TextStyle baseStyle,
    required Brightness brightness,
  }) {
    if (code.isEmpty) return const [];
    if (code.length > maxHighlightChars) return null;
    final normalized = normalizeLanguage(language);
    if (normalized.isEmpty || !isKnownLanguage(normalized)) return null;
    final dark = brightness == Brightness.dark;
    final theme = dark ? markdownCodeDarkTheme : markdownCodeLightTheme;
    final key = _HighlightKey(
      code: code,
      language: normalized,
      dark: dark,
      baseStyle: baseStyle,
    );
    final cached = _cache.remove(key);
    if (cached != null) {
      // 命中后放回队尾：最近用过的留在缓存里（简易 LRU）。
      _cache[key] = cached;
      return cached;
    }
    final result = _engine.highlight(code: code, language: normalized);
    final renderer = _FlatSpanRenderer(baseStyle, theme);
    result.render(renderer);
    _cache[key] = renderer.spans;
    if (_cache.length > 32) _cache.remove(_cache.keys.first);
    return renderer.spans;
  }
}

/// 缓存键：只有代码、语言、底色、基础样式都一致时才能复用 span。
class _HighlightKey {
  const _HighlightKey({
    required this.code,
    required this.language,
    required this.dark,
    required this.baseStyle,
  });

  final String code;
  final String language;
  final bool dark;
  final TextStyle baseStyle;

  @override
  bool operator ==(Object other) =>
      other is _HighlightKey &&
      other.code == code &&
      other.language == language &&
      other.dark == dark &&
      other.baseStyle == baseStyle;

  @override
  int get hashCode => Object.hash(code, language, dark, baseStyle);
}

/// 归一化 info string 里的语言名（`Python` → `python`、`language-js` → `js`）。
///
/// `js` / `sh` / `yml` / `c++` / `c#` 这些写法 highlight.js 自己注册了别名，
/// 这里只做大小写、空白与 `language-` 前缀的清理；返回空串表示没写语言。
String normalizeLanguage(String language) {
  var name = language.trim().toLowerCase();
  if (name.startsWith('language-')) name = name.substring(9).trim();
  return name;
}

/// 把 highlight.js 的 token 树转换成扁平 TextSpan 的渲染器。
///
/// 与 `re_highlight` 自带的 renderer 的差别：
/// - 不使用深层嵌套 TextSpan（嵌套会让排版开销按层数暴涨）；
/// - 样式在 [openNode] 时合并到父级，子 token 继承父级样式（与 highlight.js
///   的 CSS 层叠语义一致），无需逐层 merge；
/// - 父节点文本为空时不产生多余的空 TextSpan。
class _FlatSpanRenderer implements HighlightRenderer {
  _FlatSpanRenderer(this.baseStyle, this.theme) : _stack = [baseStyle];

  final TextStyle baseStyle;
  final Map<String, TextStyle> theme;
  final List<TextStyle> _stack;
  final List<TextSpan> spans = <TextSpan>[];

  @override
  void addText(String text) {
    if (text.isEmpty) return;
    spans.add(TextSpan(text: text, style: _stack.last));
  }

  @override
  void openNode(DataNode node) {
    final scope = node.scope;
    _stack.add(
      scope == null ? _stack.last : _stack.last.merge(theme[scope]),
    );
  }

  @override
  void closeNode(DataNode node) {
    if (_stack.length > 1) _stack.removeLast();
  }
}

/// 内置语言表：只注册常用语言。
///
/// `re_highlight` 的 `languages/all.dart` 带 197 种语言（含 `isbl` 这种单个
/// 380KB 的），全量注册会显著增大包体。这里收录写笔记时最常出现的语言，
/// 未命中的语言退回纯等宽文本（不报错、不丢正文）。
final Map<String, Mode> _languages = <String, Mode>{
  'bash': langBash,
  'c': langC,
  'cpp': langCpp,
  'csharp': langCsharp,
  'css': langCss,
  'dart': langDart,
  'diff': langDiff,
  'dockerfile': langDockerfile,
  'go': langGo,
  'graphql': langGraphql,
  'groovy': langGroovy,
  'http': langHttp,
  'ini': langIni,
  'java': langJava,
  'javascript': langJavascript,
  'json': langJson,
  'kotlin': langKotlin,
  'less': langLess,
  'lua': langLua,
  'makefile': langMakefile,
  'markdown': langMarkdown,
  'nginx': langNginx,
  'objectivec': langObjectivec,
  'perl': langPerl,
  'php': langPhp,
  'plaintext': langPlaintext,
  'powershell': langPowershell,
  'protobuf': langProtobuf,
  'python': langPython,
  'r': langR,
  'ruby': langRuby,
  'rust': langRust,
  'scala': langScala,
  'scss': langScss,
  'shell': langShell,
  'sql': langSql,
  'swift': langSwift,
  'typescript': langTypescript,
  'vim': langVim,
  'xml': langXml,
  'yaml': langYaml,
};

/// 高亮用配色（深浅两套，均按代码块底色做过 WCAG AA 对比度校验）。
///
/// 不直接使用 highlight.js 现成主题：那些主题的底色是纯 `#ffffff` / `#0d1117`，
/// 与本 App 的 Material 3 配色（`surfaceContainerHighest`）不符，直接套进来
/// 要么出现两块拼色，要么注释/内建符号对比度不足 3:1。
const Map<String, TextStyle> markdownCodeLightTheme = _lightTheme;
const Map<String, TextStyle> markdownCodeDarkTheme = _darkTheme;

/// 浅色主题：关键字紫、字符串绿、数字橙、注释灰、函数蓝、类型青、变量洋红。
const Map<String, TextStyle> _lightTheme = <String, TextStyle>{
  'keyword': TextStyle(color: Color(0xFF7C2FB0)),
  'string': TextStyle(color: Color(0xFF0F6B3F)),
  'number': TextStyle(color: Color(0xFFA04A00)),
  'comment': TextStyle(color: Color(0xFF5D5A64)),
  'function': TextStyle(color: Color(0xFF2B5FAD)),
  'title': TextStyle(color: Color(0xFF2B5FAD)),
  'type': TextStyle(color: Color(0xFF0F6B7A)),
  'variable': TextStyle(color: Color(0xFFA5305F)),
  'attr': TextStyle(color: Color(0xFF9A3A0F)),
  'meta': TextStyle(color: Color(0xFF5D5A64)),
  'literal': TextStyle(color: Color(0xFFA04A00)),
  'operator': TextStyle(color: Color(0xFF4A4750)),
  'symbol': TextStyle(color: Color(0xFF0F6B3F)),
  'bullet': TextStyle(color: Color(0xFF7C2FB0)),
  'emphasis': TextStyle(fontStyle: FontStyle.italic),
  'strong': TextStyle(fontWeight: FontWeight.w700),
  'section': TextStyle(fontWeight: FontWeight.w700),
  'deletion': TextStyle(color: Color(0xFFB31D28)),
  'addition': TextStyle(color: Color(0xFF0F6B3F)),
};

/// 深色主题：同一套语义角色，换成在深色底上对比度 ≥ 6:1 的亮色。
const Map<String, TextStyle> _darkTheme = <String, TextStyle>{
  'keyword': TextStyle(color: Color(0xFFD8A8FF)),
  'string': TextStyle(color: Color(0xFF86D99B)),
  'number': TextStyle(color: Color(0xFFFFB870)),
  'comment': TextStyle(color: Color(0xFFB9B4C0)),
  'function': TextStyle(color: Color(0xFF8FB8FF)),
  'title': TextStyle(color: Color(0xFF8FB8FF)),
  'type': TextStyle(color: Color(0xFF6FE3E1)),
  'variable': TextStyle(color: Color(0xFFFF9ECB)),
  'attr': TextStyle(color: Color(0xFFFFA07A)),
  'meta': TextStyle(color: Color(0xFFB9B4C0)),
  'literal': TextStyle(color: Color(0xFFFFB870)),
  'operator': TextStyle(color: Color(0xFFD5D0DC)),
  'symbol': TextStyle(color: Color(0xFF86D99B)),
  'bullet': TextStyle(color: Color(0xFFD8A8FF)),
  'emphasis': TextStyle(fontStyle: FontStyle.italic),
  'strong': TextStyle(fontWeight: FontWeight.w700),
  'section': TextStyle(fontWeight: FontWeight.w700),
  'deletion': TextStyle(color: Color(0xFFFF8F8F)),
  'addition': TextStyle(color: Color(0xFF86D99B)),
};

