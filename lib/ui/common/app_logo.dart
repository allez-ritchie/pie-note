import 'package:flutter/material.dart';

/// 应用 Logo（与 `assets/branding/app_icon.svg` 同源）。
///
/// 图标本身已经带暖白圆角底板，直接按尺寸铺在页面里即可；
/// 桌面端窗口图标也是从同一份 PNG 读取（见 `linux/runner/my_application.cc`）。
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72, this.semanticLabel});

  static const String assetPath = 'assets/branding/app_icon.png';

  /// 图标边长（正方形）。
  final double size;

  /// 无障碍标签；为空时按纯装饰处理。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final logo = ClipRRect(
      // 与图标自身的圆角（22.5%）保持一致，避免缩放时出现白边。
      borderRadius: BorderRadius.circular(size * 0.225),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: logo);
    return Semantics(label: semanticLabel, image: true, child: logo);
  }
}
