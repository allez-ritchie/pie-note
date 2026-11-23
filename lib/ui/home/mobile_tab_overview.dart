import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/workspace.dart';
import 'workspace_strings.dart';

/// 移动端「多标签总览」页。
///
/// 视觉参考 Obsidian 移动端：2 列卡片网格，卡片顶部是标题 + 关闭按钮，
/// 下面是页面预览（笔记显示正文摘要，其它页面显示图标与说明），
/// 当前激活的卡片用主色描边；底部「新建笔记」与右上角「完成」。
/// 点击卡片切换并返回，关闭按钮直接关掉对应标签页。
class MobileTabOverview extends ConsumerWidget {
  const MobileTabOverview({
    super.key,
    required this.onActivate,
    required this.onClose,
    required this.onNewNote,
  });

  final ValueChanged<String> onActivate;
  final ValueChanged<String> onClose;
  final VoidCallback onNewNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(WorkspaceStrings.tabCount(state.tabs.length)),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(WorkspaceStrings.overviewDone),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: onNewNote,
        icon: const Icon(Icons.add_rounded),
        label: const Text(WorkspaceStrings.overviewNewNote),
      ),
      body:
          state.tabs.isEmpty
              ? Center(
                child: Text(
                  WorkspaceStrings.overviewEmpty,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
              : GridView.builder(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.72,
                ),
                itemCount: state.tabs.length,
                itemBuilder: (context, index) {
                  final tab = state.tabs[index];
                  return _TabCard(
                    key: ValueKey('tab-card-${tab.id}'),
                    tab: tab,
                    active: tab.id == state.activeId,
                    onTap: () => onActivate(tab.id),
                    onClose: () => onClose(tab.id),
                  );
                },
              ),
    );
  }
}

class _TabCard extends StatelessWidget {
  const _TabCard({
    super.key,
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final WorkspaceTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color:
              active
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.6),
          width: active ? 1.8 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
              child: Row(
                children: [
                  Icon(
                    _iconFor(tab),
                    size: 16,
                    color: active ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: WorkspaceStrings.overviewClose,
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (tab.dirty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              WorkspaceStrings.overviewDirty,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: scheme.primary),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child:
                          tab.preview.isNotEmpty
                              ? Text(
                                tab.preview,
                                maxLines: 8,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.5,
                                ),
                              )
                              : _Placeholder(tab: tab),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(WorkspaceTab tab) {
    return switch (tab.kind) {
      WorkspaceTabKind.notebooks => Icons.folder_rounded,
      WorkspaceTabKind.search => Icons.search_rounded,
      WorkspaceTabKind.settings => Icons.settings_rounded,
      WorkspaceTabKind.notes => Icons.article_outlined,
      WorkspaceTabKind.note => Icons.description_outlined,
    };
  }
}

/// 没有正文摘要的页面（笔记本 / 搜索 / 设置 / 新建草稿）显示图标与说明。
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.tab});

  final WorkspaceTab tab;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Icon(
        _TabCard._iconFor(tab),
        size: 40,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
      ),
    );
  }
}
