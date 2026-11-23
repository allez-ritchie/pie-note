import '../common/app_platform.dart';

/// 「与笔记本对话」专用文案。
///
/// 页面与控制器里禁止硬编码中文，统一从这里取；通用词汇（确定 / 取消 / 重试等）
/// 复用 `lib/ui/common/strings.dart` 里的 `S`。
/// 评审时由负责人决定是否并入 `lib/ui/common/strings.dart`。
class ChatStrings {
  const ChatStrings._();

  // 页面骨架
  static const String title = '对话';
  static const String loadFailed = '对话加载失败';
  static const String noSessionTitle = '还没有对话';
  static const String noSessionMessage = '发送第一条消息即可自动创建会话；也可以先建一个空会话再提问。';
  static const String startChat = '开始对话';
  static const String sessionLoading = '正在加载会话…';

  // 输入框
  static const String inputHint = '向这个笔记本提问…';
  static const String send = '发送';
  static const String sending = 'AI 正在回答…';

  /// 发送按钮提示（快捷键随平台显示 Ctrl 或 ⌘）。
  static String get sendShortcut => '发送（${AppPlatform.shortcutKeyLabel}+Enter）';
  static String get inputHelper => '${AppPlatform.shortcutKeyLabel}+Enter 发送，Enter 换行';

  // 消息
  static const String roleHuman = '你';
  static const String roleAi = 'AI';
  static const String copy = '复制';
  static const String copied = '已复制到剪贴板';
  static const String copyFailed = '复制失败';
  static const String saveAsNote = '保存为笔记';
  static const String savedAsNote = '已保存为 AI 笔记';
  static const String saveAsNoteFailed = '保存为笔记失败';
  static const String generating = 'AI 正在回答…';
  static const String emptyAnswer = '（这条回答内容为空）';
  static const String generatingHint = '模型生成可能耗时几十秒，请稍候';

  // 发送失败：内联错误（可重试，消息与输入都不丢）
  static const String sendFailedTitle = '生成失败';
  static const String sendFailedRetry = '重试';
  static const String dismissError = '关闭提示';

  // 会话
  static const String sessions = '会话';
  static const String sessionPanelTitle = '会话列表';
  static const String newSession = '新建会话';
  static const String newSessionTitle = '新建会话';
  static const String newSessionHint = '可留空，默认用首条消息生成标题';
  static const String renameSession = '重命名会话';
  static const String deleteSession = '删除会话';
  static const String deleteSessionTitle = '删除会话';
  static const String deleteSessionMessage = '删除后该会话的全部消息都会消失，且不可恢复。';
  static const String sessionDeleted = '会话已删除';
  static const String sessionCreated = '已新建会话';
  static const String emptySessions = '还没有会话';
  static const String selectSession = '切换会话';
  static const String noSessionsInPanel = '暂无会话，发送消息时会自动创建。';

  /// 状态徽标：`3 条消息`。
  static String messageCount(int count) => '$count 条消息';

  /// 创建会话的默认标题（首条消息摘要）。
  static String autoTitle(String summary) => summary;

  // 上下文
  static const String context = '上下文';
  static const String contextPanelTitle = '对话上下文';
  static const String sourcesSection = '来源';
  static const String notesSection = '笔记';
  static const String modeOff = '不进';
  static const String modeInsights = '仅洞见';
  static const String modeFull = '全文';
  static const String modeOffTooltip = '不放进本轮对话上下文';
  static const String modeInsightsTooltip = '只放这个来源的「洞见」摘要（需已生成洞见）';
  static const String modeFullTooltip = '放完整正文';
  static const String previewContext = '预览上下文';
  static const String previewingContext = '正在构建上下文…';
  static const String noSources = '这个笔记本还没有来源';
  static const String noNotes = '这个笔记本还没有笔记';
  static const String contextFailed = '上下文构建失败';
  static const String contextEmpty = '当前不会向模型注入任何上下文';
  static const String contextHelp = '只有勾选的来源与笔记会作为上下文发给模型；勾选变化后 token 数需重新预览。';
  static const String sourceUnavailable = '处理中或处理失败的来源不能进上下文';

  /// 洞见数徽标：`3 条洞见`。
  static String insightsBadge(int count) => '$count 条洞见';

  /// 已选统计：`2 个来源全文 / 1 个来源仅洞见 / 3 条笔记`。
  static String contextSummary(int fullSources, int insightSources, int notes) {
    final parts = <String>[];
    if (fullSources > 0) parts.add('$fullSources 个来源全文');
    if (insightSources > 0) parts.add('$insightSources 个来源仅洞见');
    if (notes > 0) parts.add('$notes 条笔记');
    if (parts.isEmpty) return contextEmpty;
    return parts.join(' / ');
  }

  /// 上下文规模：`约 1234 tokens / 5678 字符`。
  static String contextAmount(int tokens, int chars) =>
      '约 $tokens tokens / $chars 字符';

  // 模型
  static const String model = '模型';
  static const String modelPanelTitle = '选择模型';
  static const String defaultModel = '后端默认';
  static const String defaultModelHint = '跟随后端默认对话模型';
  static const String modelChanged = '模型已切换';
  static const String modelChangeFailed = '模型切换失败';
  static const String noModels = '后端未注册可用模型';

  // 面板
  static const String openSessions = '打开会话列表';
  static const String openContext = '打开上下文设置';
  static const String openModel = '打开模型选择';
  static const String closePanel = '收起';
  static const String refresh = '刷新会话';
  static const String notConfigured = '尚未配置后端，无法加载对话';
}
