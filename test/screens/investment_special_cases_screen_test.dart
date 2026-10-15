import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/screens/investment_special_cases_screen.dart';
import 'package:simpletaxautoextraction/services/auth_service.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';
import 'package:simpletaxautoextraction/services/investment_event_service.dart';

void main() {
  for (final action in [
    'Record reviewed split / consolidation',
    'Create reviewed AUD conversion draft',
  ]) {
    testWidgets(
      '$action controllers survive dismissal animation and private forms close on sign-out',
      (tester) async {
        final db = FakeFirebaseFirestore();
        final auth = MockFirebaseAuth(
          mockUser: MockUser(uid: 'synthetic-owner'),
          signedIn: true,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: InvestmentSpecialCasesScreen(
              authService: AuthService(auth: auth),
              firestoreService: FirestoreService(db: db),
              eventService: InvestmentEventService(db: db),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).first,
          'private synthetic input',
        );
        await tester.tap(find.text('Cancel'));
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).first,
          'private synthetic input',
        );
        await auth.signOut();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('private synthetic input'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
