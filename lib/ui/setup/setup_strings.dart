import '../common/app_platform.dart';

/// 后端配置页文案。
class SetupStrings {
  const SetupStrings._();

  static const String title = '配置后端';
  static const String editTitle = '后端设置';
  static const String sectionBackend = 'Open Notebook 后端';
  static const String baseUrlLabel = '后端地址';
  static const String baseUrlHint = 'http://192.168.31.24:5055';
  static const String baseUrlHelper = '填写局域网内 Open Notebook 的地址，可带端口';
  static const String baseUrlEmpty = '请输入后端地址';
  static const String passwordLabel = '访问密码';
  static const String passwordHint = 'Open Notebook 的访问密码';
  /// 密码保存位置随平台变化（Android Keystore / 系统密钥环 / 凭据管理器）。
  static String get passwordHelper =>
      '密码仅保存在本机安全存储（${AppPlatform.secretStorageName}）中';
  static const String testConnection = '测试连接';
  static const String testing = '正在测试…';
  static const String saveAndEnter = '保存并进入';
  static const String saving = '正在连接…';
  static const String save = '保存';
  static const String testSuccess = '连接成功';
  static const String testSuccessWithVersion = '连接成功 · Open Notebook';
  static const String serverVersion = '版本';
  static const String authDisabledHint = '该后端未启用密码鉴权，密码可留空';
  static String get networkHint =>
      '提示：${AppPlatform.deviceNoun}需与后端处于同一局域网；若后端使用 HTTP 明文，允许在「设置」中查看说明。';
  static const String editHint = '修改后会立即使用新配置，无需重启 App。';
  static const String saved = '配置已保存';
}
