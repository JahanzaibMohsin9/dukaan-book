import 'package:dukaan_book/app/bootstrap/dukaan_book_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unauthenticated app opens to auth screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: DukaanBookApp()));
    await tester.pumpAndSettle();

    expect(find.text('Dukaan Book'), findsWidgets);
    expect(find.text('Open your ledger'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
