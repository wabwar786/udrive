import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udrive_mobile/core/widgets/brand.dart';

void main() {
  testWidgets('uDrive brand renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: UDriveWordmark()),
        ),
      ),
    );

    expect(find.byType(UDriveWordmark), findsOneWidget);
    expect(find.byType(UDriveMark), findsOneWidget);
  });
}
