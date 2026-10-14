import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:simpletaxautoextraction/main.dart';
import 'package:simpletaxautoextraction/models/tax_workspace.dart';
import 'package:simpletaxautoextraction/services/tax_workspace_service.dart';
import 'package:simpletaxautoextraction/services/document_coverage_service.dart';

/// Runs only against demo emulators. Never uses firebase_options.dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real browser login, reviewed item, stale sources and signout', (
    tester,
  ) async {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'demo-local-only-key',
        appId: '1:123456789:web:release-test',
        messagingSenderId: '123456789',
        projectId: 'demo-phase1',
        authDomain: 'demo-phase1.firebaseapp.com',
      ),
    );
    final auth = FirebaseAuth.instance;
    final db = FirebaseFirestore.instance;
    await auth.useAuthEmulator('127.0.0.1', 9099);
    db.useFirestoreEmulator('127.0.0.1', 8186);
    db.settings = const Settings(persistenceEnabled: false);
    final email =
        'release-${DateTime.now().microsecondsSinceEpoch}@example.test';
    const password = 'synthetic-release-password';
    final credential = await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final uid = credential.user!.uid;
    await auth.signOut();
    await tester.pumpWidget(const MyApp());
    Future<void> until(Finder target) async {
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.pump(const Duration(milliseconds: 150));
        if (target.evaluate().isNotEmpty) return;
      }
      final visible = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .take(25)
          .join(' | ');
      fail('Timed out waiting for $target. Synthetic UI state: $visible');
    }

    await until(find.text('Welcome Back'));
    await tester.enterText(find.widgetWithText(TextField, 'Email'), email);
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      password,
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await until(find.byTooltip('Tax-year workspace'));
    await tester.tap(find.byTooltip('Tax-year workspace'));
    await until(find.byKey(const Key('workspace-year')));
    await tester.scrollUntilVisible(
      find.byKey(const Key('section-salary')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('section-salary')),
        matching: find.byType(IconButton),
      ),
    );
    await until(find.text('Salary review'));
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Reconciled').last);
    await tester.enterText(
      find.widgetWithText(TextField, 'Evidence or reason not applicable'),
      'Synthetic payslip reviewed',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await until(find.textContaining('Reconciled\nSynthetic payslip reviewed'));
    final store = TaxWorkspaceService(db: db);
    final workspace = await store.getWorkspace(uid, 2025);
    expect(workspace!.sectionStates['salary'], 'reconciled');
    await tester.scrollUntilVisible(
      find.byKey(const Key('workspace-add-item')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('workspace-add-item')));
    await until(find.byKey(const Key('item-amount')));
    await tester.enterText(
      find.byKey(const Key('item-sourceReference')),
      'Synthetic payslip',
    );
    await tester.enterText(find.byKey(const Key('item-amount')), '1234.56');
    await tester.ensureVisible(find.byKey(const Key('item-reviewed')));
    await tester.tap(find.byKey(const Key('item-reviewed')));
    await tester.tap(find.byKey(const Key('item-save')));
    await until(find.textContaining('Reviewed · amount 1234.56'));
    final items = await store.getItems(uid, 2025);
    expect(items.single.amount, '1234.56');
    expect(items.single.isReviewed, isTrue);
    await tester.scrollUntilVisible(
      find.byKey(const Key('workspace-year')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    // A different tab changes source generation using normal owner rules.
    await store.saveItem(
      TaxWorkspaceItem(
        userId: uid,
        yearStart: 2025,
        category: 'interest',
        sourceReference: 'Synthetic interest certificate',
        amount: '7.89',
        isReviewed: true,
      ),
    );
    await until(
      find.text(
        'Sources changed. Reload before calculating, editing or exporting.',
      ),
    );
    await tester.tap(find.byKey(const Key('workspace-reload')));
    await until(find.byKey(const Key('workspace-year')));
    await tester.scrollUntilVisible(
      find.byKey(const Key('workspace-add-item')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await until(find.textContaining('Reviewed · amount 7.89'));
    expect(
      find.text(
        'Sources changed. Reload before calculating, editing or exporting.',
      ),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('workspace-year')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('workspace-year')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('2024-2025').last);
    await until(find.byKey(const Key('workspace-year')));
    expect(find.textContaining('Reviewed · amount 1234.56'), findsNothing);
    await auth.signOut();
    await until(find.text('Sign in again to access your tax workspace.'));
    expect(find.textContaining('Synthetic payslip'), findsNothing);
    await tester.pageBack();
    await until(find.text('Welcome Back'));
    expect(auth.currentUser, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'Email'), email);
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      password,
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await until(find.byTooltip('Document inventory'));
    await tester.tap(find.byTooltip('Document inventory'));
    await until(find.byKey(const Key('document-add')));
    await tester.tap(find.byKey(const Key('document-add')));
    await until(find.byKey(const Key('document-account')));
    await tester.enterText(
      find.byKey(const Key('document-account')),
      'Synthetic broker',
    );
    await tester.enterText(find.byKey(const Key('document-ticker')), 'TEST');
    await tester.tap(find.byKey(const Key('document-save')));
    await until(find.text('Synthetic broker / TEST: fundAnnual'));
    final coverage = await DocumentCoverageService(
      db: db,
    ).getCoverage(uid, 2024);
    expect(coverage.single.state, 'missing');
    expect(coverage.single.required, isTrue);
    await tester.pageBack();
    await until(find.byTooltip('Logout'));
    await tester.tap(find.byTooltip('Logout'));
    await until(find.text('Welcome Back'));
    expect(auth.currentUser, isNull);
  });
}
