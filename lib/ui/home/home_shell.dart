import 'package:flutter/material.dart';

import 'workspace_shell.dart';

/// 主界面入口。
///
/// 具体布局由 [WorkspaceShell] 实现：桌面 / 宽窗口是「侧边导航 + 顶部标签条」，
/// 手机 / 窄窗口是「页面铺满 + 底部悬浮胶囊工具栏」，两者共用同一套标签页状态。
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) => const WorkspaceShell();
}
