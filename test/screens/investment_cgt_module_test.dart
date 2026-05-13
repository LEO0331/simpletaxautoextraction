import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/investment_transaction.dart';
import 'package:simpletaxautoextraction/screens/investment_cgt_calculation_setup_screen.dart';
import 'package:simpletaxautoextraction/screens/investment_cgt_result_screen.dart';
import 'package:simpletaxautoextraction/screens/investment_transaction_list_screen.dart';
import 'package:simpletaxautoextraction/screens/investment_transaction_upload_screen.dart';
import 'package:simpletaxautoextraction/services/auth_service.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';
import 'package:simpletaxautoextraction/services/parsers/commsec_trade_confirmation_parser.dart';
import 'package:simpletaxautoextraction/services/pdf_extraction_service.dart';

class _MockUser implements User {
  @override
  String get uid => 'u1';

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

class _FakePdfPicker extends FilePicker {
  _FakePdfPicker(this.result);
  final FilePickerResult? result;

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
    return result;
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

class _FakePdfExtractionService extends PdfExtractionService {
  @override
  Future<InvestmentExtractionResult> extractInvestmentTransactionFromPdf(
    List<int> bytes, {
    String? sourceFileName,
  }) async {
    return InvestmentExtractionResult(
      draft: InvestmentTransactionDraft(
        ticker: 'NDQ',
        securityName: 'BETASHARES NASDAQ 100 ETF',
        transactionType: InvestmentTransactionType.buy,
        tradeDate: DateTime(2026, 3, 30),
        settlementDate: DateTime(2026, 4, 1),
        units: 80,
        averagePrice: 49.66,
        consideration: 3972.8,
        brokerage: 7.94,
        gst: 0.72,
        totalCost: 3980.74,
        confirmationNumber: 'C1',
        accountNumber: 'A1',
        sourceFileName: sourceFileName,
        sourceParser: 'test',
        parserVersion: 'v1',
        notes: '',
        needsReview: false,
      ),
      confidence: 1.0,
      missingFields: const [],
      warnings: const [],
      rawText: '',
    );
  }
}

void main() {
  testWidgets('upload screen parses and shows review action', (tester) async {
    FilePicker.platform = _FakePdfPicker(
      FilePickerResult([
        PlatformFile(
          name: 'sample.pdf',
          size: 1,
          bytes: Uint8List.fromList([1]),
        ),
      ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InvestmentTransactionUploadScreen(
          authService: _MockAuthService(),
          firestoreService: FirestoreService(db: FakeFirebaseFirestore()),
          pdfExtractionService: _FakePdfExtractionService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload PDFs'));
    await tester.pumpAndSettle();
    expect(find.text('sample.pdf'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
  });

  testWidgets('transaction list screen renders records', (tester) async {
    final db = FakeFirebaseFirestore();
    final fs = FirestoreService(db: db);
    await fs.saveInvestmentTransaction(
      InvestmentTransaction(
        userId: 'u1',
        ticker: 'NDQ',
        securityName: 'ETF',
        transactionType: InvestmentTransactionType.buy,
        tradeDate: DateTime(2026, 3, 30),
        units: 10,
        averagePrice: 10,
        consideration: 100,
        brokerage: 1,
        totalCost: 101,
        sourceParser: 'test',
        parserVersion: 'v1',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InvestmentTransactionListScreen(
          authService: _MockAuthService(),
          firestoreService: fs,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('NDQ'), findsOneWidget);
  });

  testWidgets('calculation setup requires cut-off date', (tester) async {
    final db = FakeFirebaseFirestore();
    final fs = FirestoreService(db: db);
    await fs.saveInvestmentTransaction(
      InvestmentTransaction(
        userId: 'u1',
        ticker: 'NDQ',
        securityName: 'ETF',
        transactionType: InvestmentTransactionType.buy,
        tradeDate: DateTime(2025, 2, 10),
        units: 1,
        averagePrice: 100,
        consideration: 100,
        brokerage: 0,
        totalCost: 100,
        sourceParser: 'test',
        parserVersion: 'v1',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InvestmentCgtCalculationSetupScreen(
          authService: _MockAuthService(),
          firestoreService: fs,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '120');
    await tester.tap(find.text('Calculate'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cut-off date is required'), findsOneWidget);
  });

  testWidgets('result screen shows discount eligibility text', (tester) async {
    final tx = InvestmentTransaction(
      userId: 'u1',
      ticker: 'NDQ',
      securityName: 'ETF',
      transactionType: InvestmentTransactionType.buy,
      tradeDate: DateTime(2025, 2, 10),
      units: 80,
      averagePrice: 49.66,
      consideration: 3972.8,
      brokerage: 7.94,
      totalCost: 5000,
      sourceParser: 'test',
      parserVersion: 'v1',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InvestmentCgtResultScreen(
          args: InvestmentCgtResultArgs(
            cutOffDate: DateTime(2026, 3, 10),
            tickerPrices: const {'NDQ': 75},
            transactions: [tx],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Potential CGT discount eligible'),
      findsOneWidget,
    );
  });
}
