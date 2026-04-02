import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/screens/home_screen.dart';
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

class _UnmappedPdfExtractionService extends PdfExtractionService {
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
    final record = TaxRecord.empty(
      userId,
      financialYear,
      propertyId: propertyId,
      propertyName: propertyName,
    );

    return PdfExtractionResult(
      record: record,
      parserName: 'Unmapped Parser',
      confidence: 0.2,
      unmappedEntries: const [
        UnmappedExtractionEntry(
          sourceCategory: 'Unknown Income',
          amount: 123,
          isIncome: true,
        ),
        UnmappedExtractionEntry(
          sourceCategory: 'Unknown Expense',
          amount: 45,
          isIncome: false,
        ),
      ],
      mappedEntryCount: 0,
      totalEntryCount: 2,
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

  testWidgets('upload flow shows preview, diff dialog, and opens worksheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    final fakeDb = FakeFirebaseFirestore();
    final firestoreService = FirestoreService(db: fakeDb);

    await firestoreService.saveTaxRecord(
      TaxRecord(
        userId: 'test_uid',
        financialYear: '2025-2026',
        propertyId: 'default',
        propertyName: 'Primary Property',
        income: {'Gross rent': 10},
        expenses: {'Water charges': 1},
      ),
    );

    FilePicker.platform = _FakeFilePicker(
      pickResult: FilePickerResult([
        PlatformFile(
          name: 'statement.pdf',
          size: 5,
          bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        ),
      ]),
    );

    await tester.pumpWidget(buildApp(firestoreService));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upload Property Summary PDF'));
    await tester.pumpAndSettle();

    expect(find.text('Select Financial Year'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Import Preview'), findsOneWidget);
    await tester.tap(find.text('Continue to Worksheet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Existing Record Found'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.textContaining('Tax Worksheet'), findsOneWidget);
    expect(find.text('Extracted Transaction Details'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
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

  testWidgets('unmapped preview flow maps entries and opens worksheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
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
        pdfService: _UnmappedPdfExtractionService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upload Property Summary PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.text('Unmapped lines (choose destination categories):'),
      findsOneWidget,
    );

    await tester.tap(find.text('Continue to Worksheet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.textContaining('Tax Worksheet'), findsOneWidget);
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
