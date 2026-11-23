import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pie_note/ui/home/mobile_floating_bar.dart';

/// 悬浮工具栏的滚动显隐：
/// - 上划（scrollDelta > 0）隐藏；
/// - 下划（scrollDelta < 0）显示；
/// - 滚动停止 / 点按打断不会重新显示（Obsidian 移动端的手感）。
void main() {
  late FloatingBarController controller;

  setUp(() => controller = FloatingBarController());
  // 最后一个用例自己 dispose，这里允许重复调用。
  tearDown(() {
    try {
      controller.dispose();
    } on FlutterError {
      // 已释放。
    }
  });

  test('默认可见，上划隐藏、下划显示', () {
    expect(controller.visible, isTrue);

    controller.handleScroll(_update(12));
    expect(controller.visible, isFalse);

    controller.handleScroll(_update(-6));
    expect(controller.visible, isTrue);
  });

  test('上划过程中停下来（滚动结束事件）不会重新显示', () {
    controller.handleScroll(_update(30));
    expect(controller.visible, isFalse);

    // 惯性滚动结束，以及点按屏幕让滚动停下的场景：只发结束事件。
    controller.handleScroll(_scrollEnd());
    controller.handleScroll(_scrollEnd());

    expect(controller.visible, isFalse, reason: '点按停止滚动不应让工具栏回显');
  });

  test('同方向继续滚动只维持当前状态，不来回抖动', () {
    controller.handleScroll(_update(20));
    expect(controller.visible, isFalse);

    for (var i = 0; i < 5; i++) {
      controller.handleScroll(_update(8));
      expect(controller.visible, isFalse);
    }

    controller.handleScroll(_update(-5));
    expect(controller.visible, isTrue);

    for (var i = 0; i < 5; i++) {
      controller.handleScroll(_update(-3));
      expect(controller.visible, isTrue);
    }
  });

  test('滚动量为 0 的更新不影响显隐', () {
    controller.handleScroll(_update(10));
    expect(controller.visible, isFalse);

    controller.handleScroll(_update(0));
    expect(controller.visible, isFalse);
  });

  test('显式 show / hide / toggle 覆盖滚动状态', () {
    controller.handleScroll(_update(10));
    controller.show();
    expect(controller.visible, isTrue);

    controller.toggle();
    expect(controller.visible, isFalse);

    controller.toggle();
    expect(controller.visible, isTrue);
  });

  test('dispose 之后的滚动通知不会抛异常', () {
    controller.dispose();
    expect(() => controller.handleScroll(_update(10)), returnsNormally);
  });
}

/// 构造一个「滚动方向为向下（手指上划）」的更新通知。
///
/// [delta] 为正即内容朝末尾推进。
ScrollUpdateNotification _update(double delta) {
  final metrics = FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: 1000,
    pixels: 100,
    viewportDimension: 600,
    axisDirection: AxisDirection.down,
    devicePixelRatio: 1,
  );
  return ScrollUpdateNotification(
    metrics: metrics,
    context: _FakeContext(),
    scrollDelta: delta,
  );
}

ScrollEndNotification _scrollEnd() {
  final metrics = FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: 1000,
    pixels: 100,
    viewportDimension: 600,
    axisDirection: AxisDirection.down,
    devicePixelRatio: 1,
  );
  return ScrollEndNotification(metrics: metrics, context: _FakeContext());
}

/// 通知需要 BuildContext，这里只求非空、不参与逻辑。
class _FakeContext extends Fake implements BuildContext {}
