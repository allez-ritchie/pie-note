/// 搜索页专用文案。
///
/// 页面里禁止硬编码中文，统一从这里取；通用词汇（重试 / 取消等）复用
/// `lib/ui/common/strings.dart` 里的 `S`。
/// 评审时由负责人决定是否并入 `lib/ui/common/strings.dart`。
class SearchStrings {
  const SearchStrings._();

  // 搜索框
  static const String title = '搜索';
  static const String searchHint = '搜索标题或正文';
  static const String clearInput = '清除';

  // 范围选择
  static const String scopeAll = '全部笔记本';
  static const String scopeLoading = '加载笔记本…';
  static const String scopeUnavailable = '笔记本列表不可用，已按「全部」范围搜索';

  // 搜索类型
  static const String typeText = '文本';
  static const String typeVector = '语义';
  static const String vectorHint = '需后端已配置 embedding 模型，可能较慢';

  // 结果状态
  static const String searching = '正在搜索…';
  static const String guideTitle = '搜索你的笔记';
  static const String guideMessage = '输入关键词搜索笔记的标题与正文，也可以先限定笔记本范围与搜索类型。';
  static const String emptyTitle = '没有找到相关笔记';
  static const String emptyMessage = '换个关键词，或调整范围与搜索类型后再试。';
  static const String authErrorTitle = '鉴权失败';
  static const String unauthorizedHint = '请到「设置」页检查访问密码是否正确。';

  // 结果条目
  static const String unnamedNote = '未命名笔记';

  /// 相关度展示：保留 1 位小数，弱化展示用。
  static String relevance(double value) => '相关度 ${value.toStringAsFixed(1)}';
}
