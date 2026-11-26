import '../common/app_platform.dart';

/// 可交互表格的界面文案（单元格编辑、新增行列、右键菜单、选区操作）。
class MarkdownTableStrings {
  const MarkdownTableStrings._();

  // 悬停提示（气泡）与工具条按钮
  static const String addColumnRight = '在右侧新增列';
  static const String addRowBelow = '在下方新增行';
  static const String selectColumn = '拖动选取整列';

  // 右键菜单：剪贴板
  static const String menuCut = '剪切';
  static const String menuCopy = '复制';
  static const String menuPaste = '粘贴';
  static const String menuFormat = '文本格式';
  static const String menuAlign = '对齐';
  static const String menuClearCells = '清空选中的单元格';
  static const String menuDeleteCells = '删除选中的单元格';

  // 文本格式（Markdown 标记）
  static const String formatBold = '加粗';
  static const String formatItalic = '斜体';
  static const String formatStrike = '删除线';
  static const String formatCode = '行内代码';
  static const String formatClear = '清除格式';

  // 对齐
  static const String alignLeft = '左对齐';
  static const String alignCenter = '居中对齐';
  static const String alignRight = '右对齐';

  // 行列操作
  static const String insertRowAbove = '在上方插入行';
  static const String insertRowBelow = '在下方插入行';
  static const String insertColumnLeft = '在左侧插入列';
  static const String insertColumnRight = '在右侧插入列';
  static const String deleteRows = '删除选中的行';
  static const String deleteColumns = '删除选中的列';
  static const String deleteTable = '删除整个表格';

  // 快捷键提示
  static String get copyShortcut => '复制（${AppPlatform.shortcutKeyLabel}+C）';
  static String get pasteShortcut => '粘贴（${AppPlatform.shortcutKeyLabel}+V）';

  /// 单元格数量提示：`已选中 2 行 × 3 列`。
  static String selectionSummary(int rows, int columns) =>
      '已选中 $rows 行 × $columns 列';

  /// 单元格外的新增列按钮（只在桌面端悬停时出现）。
  static const String hoverHint = '悬停到表格边缘可新增行 / 列';
}
