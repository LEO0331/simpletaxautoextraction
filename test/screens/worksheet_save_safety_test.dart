import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/screens/worksheet_screen.dart';
import 'package:simpletaxautoextraction/services/draft_sync_service.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';

class _FailingCopyService extends FirestoreService {
  _FailingCopyService() : super(db: FakeFirebaseFirestore());

  @override
  Future<SaveTaxRecordResult> saveTaxRecordWithStrategy(
    TaxRecord record, {
    bool saveAsNewYear = false,
    String? overrideFinancialYear,
  }) async => throw StateError('offline');
}

void main() {
  setUp(() => DraftSyncService.instance.clearPendingDrafts());
  tearDown(() => DraftSyncService.instance.clearPendingDrafts());

  Future<void> openWorksheet(
    WidgetTester tester,
    FirestoreService service,
    TaxRecord record,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: WorksheetScreen(record: record, firestoreService: service),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save As New Year'));
    await tester.pumpAndSettle();
  }

  testWidgets('copy rejects the source year without leaving the dialog', (
    tester,
  ) async {
    final service = FirestoreService(db: FakeFirebaseFirestore());
    await openWorksheet(tester, service, TaxRecord.empty('u1', '2025-2026'));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '2025-2026',
    );
    await tester.tap(find.text('Save Copy'));
    await tester.pumpAndSettle();
    expect(
      find.text('Choose a different financial year for the copy.'),
      findsOneWidget,
    );
    expect((await service.getUserTaxRecords('u1').first), isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('existing target year cannot be copied over or queued for sync', (
    tester,
  ) async {
    final service = FirestoreService(db: FakeFirebaseFirestore());
    final source = TaxRecord(
      userId: 'u1',
      financialYear: '2025-2026',
      income: {'Gross rent': 100},
    );
    final saved = await service.saveTaxRecordWithStrategy(source);
    await service.saveTaxRecord(
      source.copyWith(financialYear: '2026-2027', income: {'Gross rent': 200}),
    );
    await openWorksheet(tester, service, source.copyWith(id: saved.documentId));
    await tester.tap(find.text('Save Copy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('FY 2026-2027 already exists'), findsOneWidget);
    expect(find.text('Tax Worksheet 2025-2026'), findsOneWidget);
    expect(DraftSyncService.instance.pendingDrafts, isEmpty);
    final records = await service.getUserTaxRecords('u1').first;
    expect(records.length, 2);
    expect(
      records.singleWhere((r) => r.financialYear == '2026-2027').totalIncome,
      200,
    );
    expect(
      records.singleWhere((r) => r.financialYear == '2025-2026').totalIncome,
      100,
    );
  });

  testWidgets(
    'successful copy creates a separate target and leaves source unchanged',
    (tester) async {
      final service = FirestoreService(db: FakeFirebaseFirestore());
      final source = TaxRecord(
        userId: 'u1',
        financialYear: '2025-2026',
        income: {'Gross rent': 100},
      );
      final saved = await service.saveTaxRecordWithStrategy(source);
      await openWorksheet(
        tester,
        service,
        source.copyWith(id: saved.documentId),
      );
      await tester.tap(find.text('Save Copy'));
      await tester.pumpAndSettle();
      expect(find.text('Tax Worksheet 2026-2027'), findsOneWidget);
      final records = await service.getUserTaxRecords('u1').first;
      expect(records.length, 2);
      expect(
        records.singleWhere((r) => r.financialYear == '2025-2026').id,
        saved.documentId,
      );
      expect(
        records.singleWhere((r) => r.financialYear == '2026-2027').id,
        isNot(saved.documentId),
      );
    },
  );

  testWidgets(
    'failed copy stays available without an unsafe normal-update draft',
    (tester) async {
      await openWorksheet(
        tester,
        _FailingCopyService(),
        TaxRecord.empty('u1', '2025-2026').copyWith(id: 'source-id'),
      );
      await tester.tap(find.text('Save Copy'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not save the copy.'), findsOneWidget);
      expect(find.text('Tax Worksheet 2025-2026'), findsOneWidget);
      expect(DraftSyncService.instance.pendingDrafts, isEmpty);
    },
  );
}
