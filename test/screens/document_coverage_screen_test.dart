import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/screens/document_coverage_screen.dart';
import 'package:simpletaxautoextraction/services/auth_service.dart';
import 'package:simpletaxautoextraction/services/document_coverage_service.dart';

void main() {
  testWidgets(
    'saving dialog retains controllers through its closing transition',
    (tester) async {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'owner'),
        signedIn: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentCoverageScreen(
            authService: AuthService(auth: auth),
            coverageService: DocumentCoverageService(db: db),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('document-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('document-account')),
        'Synthetic account',
      );
      await tester.enterText(find.byKey(const Key('document-ticker')), 'TEST');
      await tester.tap(find.byKey(const Key('document-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic account / TEST: fundAnnual'), findsOneWidget);
      expect(
        (await DocumentCoverageService(
          db: db,
        ).getCoverage('owner', 2024)).single.state,
        'missing',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sign-out dismisses an open inventory form and clears private fields',
    (tester) async {
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'owner'),
        signedIn: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentCoverageScreen(
            authService: AuthService(auth: auth),
            coverageService: DocumentCoverageService(
              db: FakeFirebaseFirestore(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('document-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('document-account')),
        'Synthetic private account',
      );
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Synthetic private account'), findsNothing);
      expect(find.text('Sign in to access document evidence.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
