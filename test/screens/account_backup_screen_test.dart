import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/screens/account_backup_screen.dart';
import 'package:simpletaxautoextraction/services/account_backup_service.dart';
import 'package:simpletaxautoextraction/services/auth_service.dart';

void main() {
  testWidgets('sign-out clears owner evidence even while its dialog is open', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'owner'),
      signedIn: true,
    );
    final operation = db
        .collection('users')
        .doc('owner')
        .collection('account_restores')
        .doc('synthetic');
    await operation.set({'schemaVersion': 1, 'userId': 'owner'});
    await operation.collection('records').doc('example').set({
      'path': 'tax_records/synthetic',
      'payload': {'notes': 'Synthetic private evidence'},
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AccountBackupScreen(
          authService: AuthService(auth: auth),
          backupService: AccountBackupService(db: db),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recovered source history'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Synthetic private evidence'), findsOneWidget);
    await auth.signOut();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Synthetic private evidence'), findsNothing);
    expect(
      find.text('Sign in as the original owner to view this evidence.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to access account backups.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
