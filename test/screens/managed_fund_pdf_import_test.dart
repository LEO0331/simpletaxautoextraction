import 'dart:async';
import 'dart:typed_data';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/managed_fund_statement.dart';
import 'package:simpletaxautoextraction/screens/managed_fund_statement_screen.dart';
import 'package:simpletaxautoextraction/services/auth_service.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';
import 'package:simpletaxautoextraction/services/managed_fund_pdf_service.dart';
import 'package:simpletaxautoextraction/services/parsers/managed_fund_statement_parser.dart';

class Picker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
    PlatformFile(
      name: 'synthetic.pdf',
      size: 3,
      bytes: Uint8List.fromList([1, 2, 3]),
    ),
  ]);
}

ManagedFundExtractionResult draft() => ManagedFundExtractionResult(
  draft: ManagedFundStatement(
    id: null,
    userId: 'owner',
    ticker: 'SYN',
    accountNumber: 'synthetic-account',
    issuer: 'Betashares',
    layoutVersion: 'amma-spatial-v1',
    yearStart: 2024,
    sourceReference: 'sha256:synthetic;pages:1,2',
    components: {
      for (final key in ManagedFundStatement.componentKeys) key: '',
      'grossCapitalGain': '100',
    },
  ),
  warnings: ['Review every source field.'],
  missingFields: ['australianIncome'],
  fieldEvidence: {'grossCapitalGain': 'Page 1: grossCapitalGain'},
);

class Extractor extends ManagedFundPdfService {
  Completer<ManagedFundExtractionResult>? completion;
  bool fail = false;
  int? selectedFirst, selectedLast;
  @override
  Future<ManagedFundExtractionResult> extract(
    List<int> bytes, {
    required String userId,
    int? firstPage,
    int? lastPage,
  }) async {
    selectedFirst = firstPage;
    selectedLast = lastPage;
    if (fail) throw StateError('PRIVATE SOURCE TEXT MUST NOT APPEAR');
    return completion == null ? draft() : completion!.future;
  }
}

void main() {
  setUpAll(() => FilePicker.platform = Picker());
  late FilePicker previous;
  setUp(() => previous = FilePicker.platform);
  tearDown(() => FilePicker.platform = previous);
  Future<(FirestoreService, MockFirebaseAuth)> open(
    WidgetTester tester,
    Extractor service,
  ) async {
    FilePicker.platform = Picker();
    final store = FirestoreService(db: FakeFirebaseFirestore());
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'owner'),
      signedIn: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ManagedFundStatementScreen(
          authService: AuthService(auth: auth),
          firestoreService: store,
          pdfService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-fund-pdf')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('fund-pdf-pages')), '1-2');
    await tester.tap(find.byKey(const Key('parse-fund-pdf')));
    return (store, auth);
  }

  testWidgets('Selected pages open an unreviewed draft without saving', (
    tester,
  ) async {
    final service = Extractor();
    final (store, _) = await open(tester, service);
    await tester.pumpAndSettle();
    expect(service.selectedFirst, 1);
    expect(service.selectedLast, 2);
    expect(find.text('Add annual fund statement'), findsOneWidget);
    expect(find.textContaining('PDF extraction draft'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('fund-australianIncome')),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('fund-australianIncome')),
    );
    expect(field.controller!.text, '');
    expect(await store.getManagedFundStatementsOnce('owner'), isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Account changes during extraction discard the private draft', (
    tester,
  ) async {
    final service = Extractor()
      ..completion = Completer<ManagedFundExtractionResult>();
    final (store, auth) = await open(tester, service);
    await tester.pump();
    await auth.signOut();
    service.completion!.complete(draft());
    await tester.pumpAndSettle();
    expect(find.text('Add annual fund statement'), findsNothing);
    expect(find.text('Please sign in again.'), findsOneWidget);
    expect(await store.getManagedFundStatementsOnce('owner'), isEmpty);
  });
  testWidgets('Parser exceptions never expose raw source contents', (
    tester,
  ) async {
    final service = Extractor()..fail = true;
    await open(tester, service);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Unable to extract these pages'),
      findsOneWidget,
    );
    expect(find.textContaining('PRIVATE SOURCE TEXT'), findsNothing);
  });
}
