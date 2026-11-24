import 'package:flutter/foundation.dart';

import 'api_models.dart';

/// 笔记「重命名」的结果。
@immutable
class RenameOutcome {
  const RenameOutcome({required this.note, required this.headingUpdated});

  final Note note;

  /// 正文首行的 `# 标题` 是否被同步改写。
  final bool headingUpdated;
}

/// 把一条笔记移动到目标笔记本。
@immutable
class MoveOutcome {
  const MoveOutcome({required this.note, required this.sourceNoteId});

  /// 移动后生成的新笔记（**id 与旧笔记不同**）。
  final Note note;

  /// 被删除的原笔记 id。
  final String sourceNoteId;
}
