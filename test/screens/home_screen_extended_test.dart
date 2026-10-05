import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/screens/home_screen.dart';
import 'package:simpletaxautoextraction/screens/worksheet_screen.dart';
import 'package:simpletaxautoextraction/services/auth_service.dart';
import 'package:simpletaxautoextraction/services/draft_sync_service.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';
import 'package:simpletaxautoextraction/services/pdf_extraction_service.dart';

class _MockUser implements User {
  @override
  String get uid => 'test_uid';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockAuthService implements AuthService {
  @override
  User? get currentUser => _MockUser();

  @override
  Stream<User?> get authStateChanges => Stream.value(_MockUser());

  @override
  Future<void> signOut() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePdfExtractionService extends PdfExtractionService {
  _FakePdfExtractionService({this.previewOverride});

  final PdfExtractionResult? previewOverride;
  @override
  Future<PdfExtractionResult> extractPreviewFromPdf(
    List<int> bytes,
    String userId,
    String financialYear, {
    String propertyId = 'default',
    String propertyName = 'Primary Property',
    String? sourceFileName,
    Map<String, String>? customIncomeMappings,
    Map<String, String>? customExpenseMappings,
  }) async {
    if (previewOverride != null) return previewOverride!;
    final record =
        TaxRecord.empty(
          userId,
          financialYear,
          propertyId: propertyId,
          propertyName: propertyName,
        ).copyWith(
          sourceFileName: sourceFileName,
          lineItems: [
            {
              'sourceCategory': 'Management Fee',
              'amount': 77.0,
              'isIncome': false,
              'mappedCategory': 'Property agent fees and commission',
            },
          ],
        );

    return PdfExtractionResult(
      record: record,
      parserName: 'Fake Parser',
      confidence: 1.0,
      unmappedEntries: const [],
      mappedEntryCount: 1,
      totalEntryCount: 1,
    );
  }
}

class _ThrowingPdfExtractionService extends PdfExtractionService {
  @override
  Future<PdfExtractionResult> extractPreviewFromPdf(
    List<int> bytes,
    String userId,
    String financialYear, {
    String propertyId = 'default',
    String propertyName = 'Primary Property',
    String? sourceFileName,
    Map<String, String>? customIncomeMappings,
    Map<String, String>? customExpenseMappings,
  }) async {
    throw StateError('boom');
  }
}

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker({required this.pickResult});

  final FilePickerResult? pickResult;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus p1)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return pickResult;
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    return null;
  }
}

void main() {
  setUp(() {
    FilePicker.platform = _FakeFilePicker(pickResult: null);
    DraftSyncService.instance.clearPendingDrafts();
  });

  tearDown(() {
    FilePicker.platform = _FakeFilePicker(pickResult: null);
    DraftSyncService.instance.clearPendingDrafts();
  });

  for (final scenario in [
    'empty',
    'invalid',
    'unmapped income',
    'unmapped expense',
  ]) {
    testWidgets('import preview blocks $scenario extraction', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      FilePicker.platform = _FakeFilePicker(
        pickResult: FilePickerResult([
          PlatformFile(
            name: 'statement.pdf',
            size: 3,
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ]),
      );
      final preview = PdfExtractionResult(
        record: TaxRecord.empty('test_uid', '2025-2026').copyWith(
          lineItems: [
            {
              'sourceCategory': 'Unknown receipt',
              'amount': 50.0,
              'isIncome': scenario == 'unmapped income',
              'mappedCategory': 'UNMAPPED',
            },
          ],
        ),
        parserName: 'Test',
        confidence: 0,
        mappedEntryCount: 0,
        totalEntryCount: scenario == 'empty' ? 0 : 1,
        validationErrors: scenario == 'invalid'
            ? ['Subtotal does not reconcile.']
            : [],
        unmappedEntries: scenario.startsWith('unmapped')
            ? [
                UnmappedExtractionEntry(
                  sourceCategory: 'Unknown receipt',
                  amount: 50,
                  isIncome: scenario == 'unmapped income',
                ),
              ]
            : [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            authService: _MockAuthService(),
            firestoreService: FirestoreService(db: FakeFirebaseFirestore()),
            pdfExtractionService: _FakePdfExtractionService(
              previewOverride: preview,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload Property Summary PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Continue to Worksheet'),
            )
            .onPressed,
        isNull,
      );
      if (scenario == 'empty') {
        expect(
          find.text('All extracted lines were mapped automatically.'),
          findsNothing,
        );
        expect(
          find.textContaining('No transactions were extracted.'),
          findsOneWidget,
        );
      }
      if (scenario == 'invalid') {
        expect(find.text('Subtotal does not reconcile.'), findsOneWidget);
      }
      if (scenario.startsWith('unmapped')) {
        await tester.tap(find.byType(DropdownButtonFormField<String>).last);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        final category = scenario == 'unmapped income'
            ? 'Other rental-related income'
            : 'Repairs and maintenance';
        await tester.tap(find.text(category).last);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Continue to Worksheet'),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.text('Continue to Worksheet'));
        await tester.pumpAndSettle();
        final reviewed = tester
            .widget<WorksheetScreen>(find.byType(WorksheetScreen))
            .record;
        expect(reviewed.lineItems.single['mappedCategory'], category);
        expect(preview.record.lineItems.single['mappedCategory'], 'UNMAPPED');
        expect(
          scenario == 'unmapped income'
              ? reviewed.totalIncome
              : reviewed.totalExpenses,
          50,
        );
      } else {
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });
  }

  Widget buildApp(FirestoreService firestoreService) {
    return MaterialApp(
      home: HomeScreen(
        authService: _MockAuthService(),
        firestoreService: firestoreService,
        pdfExtractionService: _FakePdfExtractionService(),
      ),
    );
  }

  Widget buildAppWith({
    required AuthService authService,
    required FirestoreService firestoreService,
    required PdfExtractionService pdfService,
  }) {
    return MaterialApp(
      home: HomeScreen(
        authService: authService,
        firestoreService: firestoreService,
        pdfExtractionService: pdfService,
      ),
    );
  }

  Future<void> openPreview(
    WidgetTester tester,
    FirestoreService service,
    PdfExtractionResult preview,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    FilePicker.platform = _FakeFilePicker(
      pickResult: FilePickerResult([
        PlatformFile(
          name: 'statement.pdf',
          size: 3,
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ]),
    );
    await tester.pumpWidget(
      buildAppWith(
        authService: _MockAuthService(),
        firestoreService: service,
        pdfService: _FakePdfExtractionService(previewOverride: preview),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload Property Summary PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  for (final hasOtherError in [false, true]) {
    testWidgets(
      'year correction preserves other validation errors=$hasOtherError',
      (tester) async {
        await openPreview(
          tester,
          FirestoreService(db: FakeFirebaseFirestore()),
          PdfExtractionResult(
            record: TaxRecord.empty('test_uid', '2026-2027'),
            parserName: 'Test',
            confidence: 1,
            unmappedEntries: [],
            mappedEntryCount: 1,
            totalEntryCount: 1,
            detectedFinancialYear: '2025-2026',
            validationErrors: hasOtherError
                ? ['Subtotal does not reconcile.']
                : [],
          ),
        );
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Continue to Worksheet'),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('Use FY 2025-2026'));
        await tester.pump();
        expect(find.text('Financial year: 2025-2026'), findsOneWidget);
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Continue to Worksheet'),
              )
              .onPressed,
          hasOtherError ? isNull : isNotNull,
        );
        if (hasOtherError) {
          expect(find.text('Subtotal does not reconcile.'), findsOneWidget);
          await tester.tap(find.text('Cancel'));
        } else {
          await tester.tap(find.text('Continue to Worksheet'));
        }
        await tester.pumpAndSettle();
        if (!hasOtherError) {
          expect(
            tester
                .widget<WorksheetScreen>(find.byType(WorksheetScreen))
                .record
                .financialYear,
            '2025-2026',
          );
        }
      },
    );
  }

  testWidgets(
    'overwrite preview detects category reallocations with equal totals',
    (tester) async {
      final service = FirestoreService(db: FakeFirebaseFirestore());
      await service.saveTaxRecord(
        TaxRecord(
          userId: 'test_uid',
          financialYear: '2025-2026',
          income: {'Gross rent': 100},
        ),
      );
      await openPreview(
        tester,
        service,
        PdfExtractionResult(
          record: TaxRecord(
            userId: 'test_uid',
            financialYear: '2025-2026',
            income: {'Other rental-related income': 100},
          ),
          parserName: 'Test',
          confidence: 1,
          unmappedEntries: [],
          mappedEntryCount: 1,
          totalEntryCount: 1,
        ),
      );
      await tester.tap(find.text('Continue to Worksheet'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.textContaining('Gross rent: \$100.00 -> \$0.00'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Other rental-related income: \$0.00 -> \$100.00'),
        findsOneWidget,
      );
      expect(find.text('No numeric difference detected.'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('identical source rows retain independent reviewed mappings', (
    tester,
  ) async {
    final record = TaxRecord.empty('test_uid', '2025-2026').copyWith(
      lineItems: [
        for (var i = 0; i < 2; i++)
          {
            'sourceCategory': 'Unknown cost',
            'amount': 50.0,
            'isIncome': false,
            'mappedCategory': 'UNMAPPED',
          },
      ],
    );
    await openPreview(
      tester,
      FirestoreService(db: FakeFirebaseFirestore()),
      PdfExtractionResult(
        record: record,
        parserName: 'Test',
        confidence: 0,
        mappedEntryCount: 0,
        totalEntryCount: 2,
        unmappedEntries: [
          for (var i = 0; i < 2; i++)
            const UnmappedExtractionEntry(
              sourceCategory: 'Unknown cost',
              amount: 50,
              isIncome: false,
            ),
        ],
      ),
    );
    for (var i = 0; i < 2; i++) {
      final dropdown = find
          .descendant(
            of: find.ancestor(
              of: find.text('Import Preview'),
              matching: find.byType(AlertDialog),
            ),
            matching: find.byType(DropdownButtonFormField<String>),
          )
          .at(i);
      await tester.tap(dropdown);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(
        find.text(i == 0 ? 'Insurance' : 'Repairs and maintenance').last,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.tap(find.text('Continue to Worksheet'));
    await tester.pumpAndSettle();
    final reviewed = tester
        .widget<WorksheetScreen>(find.byType(WorksheetScreen))
        .record;
    expect(reviewed.expenses['Insurance'], 50);
    expect(reviewed.expenses['Repairs and maintenance'], 50);
    expect(reviewed.lineItems.map((line) => line['mappedCategory']), [
      'Insurance',
      'Repairs and maintenance',
    ]);
  });

  testWidgets('mapping editor keeps invalid rules open for correction', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = FirestoreService(db: FakeFirebaseFirestore());
    await tester.pumpWidget(buildApp(service));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom Mapping Rules'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'rent=Insurance');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unsupported income category'), findsOneWidget);
    expect((await service.getCustomMappings('test_uid'))['income'], isEmpty);
    await tester.enterText(find.byType(TextField).first, 'rent=Gross rent');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await service.getCustomMappings('test_uid'))['income'], {
      'rent': 'Gross rent',
    });
  });

  testWidgets('custom mapping dialog saves mappings', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    final firestoreService = FirestoreService(db: FakeFirebaseFirestore());
    await tester.pumpWidget(buildApp(firestoreService));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom Mapping Rules'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'bonus=Other rental-related income');
    await tester.enterText(
      fields.at(1),
      'strata=Body corporate fees and charges',
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Custom mappings saved.'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('export menu warns when no records', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    final firestoreService = FirestoreService(db: FakeFirebaseFirestore());
    await tester.pumpWidget(buildApp(firestoreService));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export CSV'));
    await tester.pumpAndSettle();
    expect(find.text('No records to export.'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export Summary PDF'));
    await tester.pumpAndSettle();
    expect(find.text('No records to export.'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('year dialog validates input before continuing', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    final firestoreService = FirestoreService(db: FakeFirebaseFirestore());
    FilePicker.platform = _FakeFilePicker(
      pickResult: FilePickerResult([
        PlatformFile(
          name: 'statement.pdf',
          size: 3,
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ]),
    );

    await tester.pumpWidget(buildApp(firestoreService));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upload Property Summary PDF'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '2025');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(
      find.text('Use YYYY-YYYY and ensure end year is start+1.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('add property updates selected property', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    final firestoreService = FirestoreService(db: FakeFirebaseFirestore());
    await tester.pumpWidget(buildApp(firestoreService));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Property'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Beach House');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Beach House'), findsWidgets);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('sync menu syncs queued drafts and compare navigation works', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    final firestoreService = FirestoreService(db: FakeFirebaseFirestore());
    DraftSyncService.instance.queueDraft(
      TaxRecord.empty('test_uid', '2025-2026'),
    );

    await tester.pumpWidget(buildApp(firestoreService));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync Offline Drafts'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trends & Comparison'));
    await tester.pumpAndSettle();

    expect(find.text('Yearly Comparison'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('processing failure shows retry snackbar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    final firestoreService = FirestoreService(db: FakeFirebaseFirestore());
    FilePicker.platform = _FakeFilePicker(
      pickResult: FilePickerResult([
        PlatformFile(
          name: 'statement.pdf',
          size: 3,
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ]),
    );

    await tester.pumpWidget(
      buildAppWith(
        authService: _MockAuthService(),
        firestoreService: firestoreService,
        pdfService: _ThrowingPdfExtractionService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upload Property Summary PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to process PDF:'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
