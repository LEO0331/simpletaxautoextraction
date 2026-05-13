import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/investment_transaction.dart';
import 'package:simpletaxautoextraction/screens/auth_screen.dart';
import 'package:simpletaxautoextraction/screens/home_screen.dart';
import 'package:simpletaxautoextraction/screens/investment_cgt_calculation_setup_screen.dart';
import 'package:simpletaxautoextraction/screens/investment_cgt_home_screen.dart';
import 'package:simpletaxautoextraction/screens/investment_cgt_result_screen.dart';
import 'package:simpletaxautoextraction/screens/investment_cgt_routes.dart';
import 'package:simpletaxautoextraction/screens/investment_transaction_list_screen.dart';
import 'package:simpletaxautoextraction/screens/investment_transaction_upload_screen.dart';
import 'package:simpletaxautoextraction/services/auth_service.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';
import 'package:simpletaxautoextraction/services/parsers/commsec_trade_confirmation_parser.dart';
import 'package:simpletaxautoextraction/services/pdf_extraction_service.dart';

class _MockUser implements User {
  @override
  String get uid => 'investment_cgt_e2e_user';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockAuthService implements AuthService {
  bool isCreateCalled = false;

  @override
  Stream<User?> get authStateChanges => Stream.value(_MockUser());

  @override
  User? get currentUser => _MockUser();

  @override
  Future<User?> createUserWithEmailPassword(
    String email,
    String password,
  ) async {
    isCreateCalled = true;
    return _MockUser();
  }

  @override
  Future<void> signOut() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.pickResult);

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
        consideration: 3972.80,
        brokerage: 7.94,
        gst: 0.72,
        totalCost: 3980.74,
        confirmationNumber: 'sample-confirmation',
        accountNumber: 'sample-account',
        sourceFileName: sourceFileName,
        sourceParser: CommsecTradeConfirmationParser.parserName,
        parserVersion: CommsecTradeConfirmationParser.parserVersion,
        notes: '',
        needsReview: false,
      ),
      confidence: 1,
      missingFields: const [],
      warnings: const [],
      rawText: 'redacted test fixture',
    );
  }
}

void main() {
  testWidgets('creates account and completes investment cgt tracker flow', (
    tester,
  ) async {
    final authService = _MockAuthService();

    await tester.pumpWidget(
      MaterialApp(home: AuthScreen(authService: authService)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Don\'t have an account? Sign Up'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(0),
      'investment-cgt-e2e@example.invalid',
    );
    await tester.enterText(find.byType(TextField).at(1), 'TestPassword123!');
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();
    expect(authService.isCreateCalled, isTrue);

    FilePicker.platform = _FakeFilePicker(
      FilePickerResult([
        PlatformFile(
          name: 'commsec-trade-confirmation.pdf',
          size: 5,
          bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        ),
      ]),
    );

    final firestoreService = FirestoreService(db: FakeFirebaseFirestore());
    final pdfService = _FakePdfExtractionService();

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          authService: authService,
          firestoreService: firestoreService,
          pdfExtractionService: pdfService,
        ),
        routes: {
          InvestmentCgtRoutes.home: (_) => const InvestmentCgtHomeScreen(),
          InvestmentCgtRoutes.upload: (_) => InvestmentTransactionUploadScreen(
            authService: authService,
            firestoreService: firestoreService,
            pdfExtractionService: pdfService,
          ),
          InvestmentCgtRoutes.transactions: (_) =>
              InvestmentTransactionListScreen(
                authService: authService,
                firestoreService: firestoreService,
              ),
          InvestmentCgtRoutes.calculate: (_) =>
              InvestmentCgtCalculationSetupScreen(
                authService: authService,
                firestoreService: firestoreService,
              ),
        },
        onGenerateRoute: (settings) {
          if (settings.name == InvestmentCgtRoutes.results) {
            return MaterialPageRoute(
              builder: (_) => InvestmentCgtResultScreen(
                args: settings.arguments as InvestmentCgtResultArgs,
              ),
            );
          }
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Investment CGT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload trade confirmation PDFs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload PDFs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Review Investment Transaction'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Investment transaction saved.'), findsOneWidget);

    Navigator.of(tester.element(find.text('Upload Investment PDFs'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('View saved transactions'));
    await tester.pumpAndSettle();
    expect(find.textContaining('NDQ'), findsOneWidget);

    Navigator.of(tester.element(find.text('Investment Transactions'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run CGT estimate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select cut-off date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('13').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '75');
    await tester.tap(find.text('Calculate'));
    await tester.pumpAndSettle();

    expect(find.text('Investment CGT Results'), findsOneWidget);
    expect(find.textContaining('Estimated gain/loss'), findsOneWidget);
  });
}
