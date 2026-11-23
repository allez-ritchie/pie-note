import '../common/app_platform.dart';

/// 设置页文案。
///
/// 约定：页面里禁止硬编码用户可见文案，统一收敛到这里；
/// 「确定 / 取消 / 重试 / App 版本」等通用词汇复用 `lib/ui/common/strings.dart` 的 `S`。
class SettingsStrings {
  const SettingsStrings._();

  static const String title = '设置';

  // ---------------------------------------------------------------------------
  // 后端连接
  // ---------------------------------------------------------------------------
  static const String sectionBackend = '后端连接';
  static const String baseUrlLabel = '后端地址';
  static const String notConfigured = '未配置';
  static const String passwordLabel = '访问密码';
  static const String passwordSaved = '已保存';
  static const String passwordMissing = '未设置';
  static const String passwordNote = '密码仅保存在本机安全存储中，页面不显示明文';
  static const String serverVersionLabel = '服务端版本';
  static const String unknownVersion = '未知';
  static const String testConnection = '测试连接';
  static const String testing = '正在测试…';
  static const String changeBackend = '修改后端';
  static const String configureBackend = '配置后端';
  static const String notConfiguredHint = '尚未配置后端地址，请先点击「配置后端」完成配置。';
  static const String testSuccess = '连接成功';
  static const String testAuthDisabledSuffix = '该后端未启用密码鉴权';

  /// 连接成功且带服务端版本号的内联提示。
  static String testSuccessWithVersion(String version) => '连接成功 · 版本 $version';

  // ---------------------------------------------------------------------------
  // 外观
  // ---------------------------------------------------------------------------
  static const String sectionAppearance = '外观';
  static const String appearanceSubtitle = '切换后立即生效，并保存在本机。';
  static const String themeSystem = '跟随系统';
  static const String themeLight = '浅色';
  static const String themeDark = '深色';
  static const String themeSaveFailed = '主题保存失败';

  // ---------------------------------------------------------------------------
  // 关于
  // ---------------------------------------------------------------------------
  static const String sectionAbout = '关于';
  static const String aboutAppName = '应用';
  static const String aboutVersion = '版本';
  static const String aboutBackend = '后端';
  static const String backendDescription =
      'PieNote 是自建 Open Notebook 的 Markdown 客户端（手机 / 桌面），笔记数据保存在后端。';
  static const String aboutApi = '当前 API 地址';
  static const String imageNotice = 'Markdown 图片链接（![](...)）暂不渲染，会按普通文本显示。';

  // ---------------------------------------------------------------------------
  // 网络说明
  // ---------------------------------------------------------------------------
  static const String sectionNetwork = '网络说明';
  static const String networkTitle = '局域网 HTTP 明文已放行';
  static String get networkBody1 => AppPlatform.isDesktop
      ? '为连接局域网内自建的 Open Notebook，桌面端直接使用系统网络栈发起 HTTP 明文请求（桌面端没有 Android 的 network_security_config 限制）。'
      : '为连接局域网内自建的 Open Notebook，App 通过 network_security_config 显式放行 HTTP 明文请求。';
  static const String networkBody2 =
      '明文传输不加密，请仅在可信局域网内使用，不要在公共 Wi-Fi 下输入访问密码。';
  static const String networkBody3 = '如果后端已启用 HTTPS，请把后端地址改为以 https:// 开头。';

  // ---------------------------------------------------------------------------
  // 危险操作
  // ---------------------------------------------------------------------------
  static const String sectionDanger = '危险操作';
  static const String clearSubtitle = '移除本机保存的后端地址与访问密码，App 会回到配置页；后端笔记数据不受影响。';
  static const String clearButton = '清除后端配置';
  static const String clearDialogTitle = '确认清除后端配置？';
  static const String clearDialogMessage =
      '将删除本机保存的后端地址与访问密码，之后需要重新配置才能使用；后端笔记数据不会被删除。';
  static const String clearConfirm = '清除';
  static const String clearSuccess = '后端配置已清除';
  static const String clearFailed = '清除配置失败';
}
