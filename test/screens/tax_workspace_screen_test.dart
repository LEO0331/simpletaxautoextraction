import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_workspace.dart';
import 'package:simpletaxautoextraction/screens/tax_workspace_screen.dart';
import 'package:simpletaxautoextraction/services/auth_service.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';
import 'package:simpletaxautoextraction/services/tax_workspace_service.dart';
import 'package:simpletaxautoextraction/services/tax_workspace_coordinator.dart';

class DelayedSnapshotStore extends TaxWorkspaceService {
  final reached = Completer<void>();
  final release = Completer<void>();
  DelayedSnapshotStore({required super.db});

  @override
  Future<List<Map<String, dynamic>>> getSnapshots(
    String uid,
    int year, {
    bool all = false,
  }) async {
    if (!reached.isCompleted) reached.complete();
    await release.future;
    return super.getSnapshots(uid, year, all: all);
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late TaxWorkspaceService workspaces;
  late MockFirebaseAuth auth;
  Future<void> open(WidgetTester tester) async {
    db = FakeFirebaseFirestore();
    workspaces = TaxWorkspaceService(db: db);
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'synthetic-owner'),
      signedIn: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TaxWorkspaceScreen(
          authService: AuthService(auth: auth),
          workspaceService: workspaces,
          firestoreService: FirestoreService(db: db),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Key key) async {
    final scrollable = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(key),
      350,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('unreviewed empty workspace stays provisional', (tester) async {
    await open(tester);
    await reveal(tester, const Key('workspace-calculate'));
    await tester.tap(find.byKey(const Key('workspace-calculate')));
    await tester.pumpAndSettle();
    expect(find.text('Needs tax review'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('workspace-finalise')),
    );
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual item requires source and retains explicit review', (
    tester,
  ) async {
    await open(tester);
    await reveal(tester, const Key('workspace-add-item'));
    await tester.tap(find.byKey(const Key('workspace-add-item')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Invalid item identity'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('item-sourceReference')),
      'Synthetic salary statement',
    );
    await tester.enterText(find.byKey(const Key('item-amount')), '12000.25');
    await tester.ensureVisible(find.byKey(const Key('item-reviewed')));
    await tester.tap(find.byKey(const Key('item-reviewed')));
    await tester.tap(find.byKey(const Key('item-save')));
    await tester.pumpAndSettle();
    final item = (await workspaces.getItems('synthetic-owner', 2025)).single;
    expect(item.amount, '12000.25');
    expect(item.isReviewed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign out closes sensitive edit dialog and clears workspace', (
    tester,
  ) async {
    await open(tester);
    await reveal(tester, const Key('workspace-add-item'));
    await tester.tap(find.byKey(const Key('workspace-add-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('item-sourceReference')),
      'Synthetic private evidence',
    );
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Synthetic private evidence'), findsNothing);
    expect(find.byKey(const Key('item-save')), findsNothing);
    expect(
      find.text('Sign in again to access your tax workspace.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('external item mutation invalidates loaded workpaper', (
    tester,
  ) async {
    await open(tester);
    await workspaces.saveWorkspace(
      const TaxWorkspace(userId: 'synthetic-owner', yearStart: 2025),
    );
    await workspaces.saveItem(
      const TaxWorkspaceItem(
        userId: 'synthetic-owner',
        yearStart: 2025,
        category: 'interest',
        sourceReference: 'Synthetic bank',
        amount: '20',
        isReviewed: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Sources changed. Reload before calculating, editing or exporting.',
      ),
      findsOneWidget,
    );
    await reveal(tester, const Key('workspace-calculate'));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('workspace-calculate')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final investmentChange in [false, true]) {
    testWidgets(
      'source change during snapshot loading rejects stale bundle: investment=$investmentChange',
      (tester) async {
        final database = FakeFirebaseFirestore();
        final delayed = DelayedSnapshotStore(db: database);
        final authentication = MockFirebaseAuth(
          mockUser: MockUser(uid: 'synthetic-owner'),
          signedIn: true,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: TaxWorkspaceScreen(
              authService: AuthService(auth: authentication),
              workspaceService: delayed,
              firestoreService: FirestoreService(db: database),
            ),
          ),
        );
        for (var i = 0; i < 20 && !delayed.reached.isCompleted; i++) {
          await tester.pump();
        }
        expect(delayed.reached.isCompleted, isTrue);
        if (investmentChange) {
          await database
              .collection('users')
              .doc('synthetic-owner')
              .collection('investment_metadata')
              .doc('ledger')
              .set({'generation': 1});
        } else {
          await delayed.saveWorkspace(
            const TaxWorkspace(userId: 'synthetic-owner', yearStart: 2025),
          );
        }
        delayed.release.complete();
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Unable to load current sources. Reload before editing or calculating.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('workspace-calculate')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'matching imported archive remains unreviewed historical evidence',
    (tester) async {
      await open(tester);
      await workspaces.saveWorkspace(
        const TaxWorkspace(userId: 'synthetic-owner', yearStart: 2025),
      );
      final bundle = await TaxWorkspaceCoordinator(
        workspaces: workspaces,
        sources: FirestoreService(db: db),
      ).load('synthetic-owner', 2025);
      await workspaces.importHistoricalSnapshot('synthetic-owner', 2025, {
        'report': bundle.report.toMap(),
      });
      await tester.tap(find.byKey(const Key('workspace-reload')));
      await tester.pumpAndSettle();
      const label = 'Imported archive · unreviewed historical evidence';
      await tester.scrollUntilVisible(
        find.text(label),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(
        find.text('Immutable workpaper · matches current sources'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
