import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pie_note/ui/common/app_logo.dart';

void main() {
  testWidgets('AppLogo 使用打包资源，尺寸与圆角随 size 变化', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: AppLogo(size: 76)))),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, AppLogo.assetPath);
    expect(image.width, 76);
    expect(image.height, 76);

    // 资源确实打进了 bundle（尺寸大于 1KB 的 PNG）。
    final context = tester.element(find.byType(Image));
    final data = await DefaultAssetBundle.of(context).load(AppLogo.assetPath);
    expect(data.lengthInBytes, greaterThan(1000));

    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    final radius = (clip.borderRadius as BorderRadius).topLeft.x;
    expect(radius, closeTo(76 * 0.225, 0.01));
  });

  testWidgets('传了语义标签时生成图片语义节点', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppLogo(size: 40, semanticLabel: 'PieNote')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('PieNote'), findsOneWidget);
  });
}
