import 'package:flutter/foundation.dart';

/// 运行平台判定与「随平台变化」的说明文案。
///
/// UI 里不要直接写「Android / 手机」这类平台限定说法：同一个界面在手机、
/// 平板与桌面端都会出现，文案按平台取自这里。
class AppPlatform {
  const AppPlatform._();

  /// 桌面端（Linux / Windows / macOS）。
  static bool get isDesktop {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  /// 密码保存在哪里 —— 跟随平台的安全存储后端。
  static String get secretStorageName {
    if (kIsWeb) return '浏览器安全存储';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android Keystore',
      TargetPlatform.iOS => 'iOS Keychain',
      TargetPlatform.macOS => 'macOS 钥匙串',
      TargetPlatform.windows => 'Windows 凭据管理器',
      TargetPlatform.linux => '系统密钥环（libsecret）',
      TargetPlatform.fuchsia => '本机安全存储',
    };
  }

  /// 快捷键提示里「Ctrl」在 macOS 上应为「Cmd」。
  static String get shortcutKeyLabel =>
      defaultTargetPlatform == TargetPlatform.macOS ? '⌘' : 'Ctrl';

  /// 网络说明里的「设备」称谓。
  static String get deviceNoun => isDesktop ? '电脑' : '手机';
}
