import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/screens/auth_screen.dart';
import 'package:simpletaxautoextraction/screens/home_screen.dart';
import 'package:simpletaxautoextraction/screens/investment_cgt_calculation_setup_screen.dart';
import 'package:simpletaxautoextraction/screens/investment_cgt_home_screen.dart';
import 'package:simpletaxautoextraction/screens/investment_cgt_result_screen.dart';
import 'package:simpletaxautoextraction/screens/investment_cgt_routes.dart';
import 'package:simpletaxautoextraction/screens/investment_transaction_list_screen.dart';
import 'package:simpletaxautoextraction/screens/investment_transaction_upload_screen.dart';
import 'package:simpletaxautoextraction/services/auth_service.dart';
import 'package:simpletaxautoextraction/services/draft_sync_service.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';
import 'package:simpletaxautoextraction/services/parsers/commsec_trade_confirmation_parser.dart';
import 'package:simpletaxautoextraction/services/pdf_extraction_service.dart';

import 'package:simpletaxautoextraction/models/investment_transaction.dart';

class _MockUser implements User {
  @override
  String get uid => 'test_uid';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockAuthService implements AuthService {
  bool isCreateCalled = false;
  bool isSignInCalled = false;

  @override
  Stream<User?> get authStateChanges => Stream.value(_MockUser());

  @override
  User? get currentUser => _MockUser();

  @override
  Future<User?> signInWithEmailPassword(String email, String password) async {
    isSignInCalled = true;
    return _MockUser();
  }

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
    final record = TaxRecord.empty(
      userId,
      financialYear,
      propertyId: propertyId,
      propertyName: propertyName,
    );
    return PdfExtractionResult(
      record: record.copyWith(sourceFileName: sourceFileName),
      parserName: 'Patrol Fake Parser',
      confidence: 1.0,
      unmappedEntries: const [],
      mappedEntryCount: 1,
      totalEntryCount: 1,
    );
  }

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

  patrolTest('auth sign-up toggle flow', ($) async {
    final auth = _MockAuthService();
    await $.tester.pumpWidget(MaterialApp(home: AuthScreen(authService: auth)));
    await $.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    await $.tester.tap(find.text('Don\'t have an account? Sign Up'));
    await $.pumpAndSettle();

    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Already have an account? Sign In'), findsOneWidget);
    await $.tester.enterText(
      find.byType(TextField).at(0),
      'investment-cgt-test@example.invalid',
    );
    await $.tester.enterText(find.byType(TextField).at(1), 'TestPassword123!');
    await $.tester.tap(find.text('Sign Up'));
    await $.pumpAndSettle();

    expect(auth.isCreateCalled, isTrue);
  });

  patrolTest('pdf upload flow to worksheet', ($) async {
    FilePicker.platform = _FakeFilePicker(
      pickResult: FilePickerResult([
        PlatformFile(
          name: 'statement.pdf',
          size: 5,
          bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        ),
      ]),
    );

    final firestoreService = FirestoreService(db: FakeFirebaseFirestore());
    await $.tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          authService: _MockAuthService(),
          firestoreService: firestoreService,
          pdfExtractionService: _FakePdfExtractionService(),
        ),
      ),
    );
    await $.pumpAndSettle();

    await $.tester.tap(find.text('Upload Property Summary PDF'));
    await $.pumpAndSettle();
    expect(find.text('Select Financial Year'), findsOneWidget);

    await $.tester.tap(find.text('Continue'));
    await $.pump();
    await $.pump(const Duration(milliseconds: 600));

    expect(find.text('Import Preview'), findsOneWidget);
    await $.tester.tap(find.text('Continue to Worksheet'));
    await $.pump();
    await $.pump(const Duration(milliseconds: 600));

    expect(find.textContaining('Tax Worksheet'), findsOneWidget);
  });

  patrolTest('mapping dialog save flow', ($) async {
    final firestoreService = FirestoreService(db: FakeFirebaseFirestore());
    await $.tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          authService: _MockAuthService(),
          firestoreService: firestoreService,
          pdfExtractionService: _FakePdfExtractionService(),
        ),
      ),
    );
    await $.pumpAndSettle();

    await $.tester.tap(find.byType(PopupMenuButton<String>));
    await $.pumpAndSettle();
    await $.tester.tap(find.text('Custom Mapping Rules'));
    await $.pumpAndSettle();

    final fields = find.byType(TextField);
    await $.tester.enterText(fields.at(0), 'bonus=Other rental-related income');
    await $.tester.enterText(
      fields.at(1),
      'strata=Body corporate fees and charges',
    );
    await $.tester.tap(find.text('Save'));
    await $.pumpAndSettle();

    expect(find.text('Custom mappings saved.'), findsOneWidget);
  });

  patrolTest('comparison page navigation flow', ($) async {
    final fakeDb = FakeFirebaseFirestore();
    final firestoreService = FirestoreService(db: fakeDb);
    await firestoreService.saveTaxRecord(
      TaxRecord(
        userId: 'test_uid',
        financialYear: '2025-2026',
        propertyId: 'default',
        propertyName: 'Primary Property',
        income: {'Gross rent': 1000},
        expenses: {'Water charges': 100},
      ),
    );

    await $.tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          authService: _MockAuthService(),
          firestoreService: firestoreService,
          pdfExtractionService: _FakePdfExtractionService(),
        ),
      ),
    );
    await $.pumpAndSettle();

    await $.tester.tap(find.byType(PopupMenuButton<String>));
    await $.pumpAndSettle();
    await $.tester.tap(find.text('Trends & Comparison'));
    await $.pumpAndSettle();

    expect(find.text('Yearly Comparison'), findsOneWidget);
    expect(
      find.textContaining('Income vs Expenses vs Net Position'),
      findsOneWidget,
    );
  });

  patrolTest('investment cgt tracker upload save and calculate flow', (
    $,
  ) async {
    FilePicker.platform = _FakeFilePicker(
      pickResult: FilePickerResult([
        PlatformFile(
          name: 'commsec-trade-confirmation.pdf',
          size: 5,
          bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        ),
      ]),
    );

    final authService = _MockAuthService();
    final firestoreService = FirestoreService(db: FakeFirebaseFirestore());
    final pdfService = _FakePdfExtractionService();

    await $.tester.pumpWidget(
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
    await $.pumpAndSettle();

    await $.tester.tap(find.text('Investment CGT'));
    await $.pumpAndSettle();
    await $.tester.tap(find.text('Upload trade confirmation PDFs'));
    await $.pumpAndSettle();
    await $.tester.tap(find.text('Upload PDFs'));
    await $.pumpAndSettle();

    expect(find.text('commsec-trade-confirmation.pdf'), findsOneWidget);
    await $.tester.tap(find.text('Review'));
    await $.pumpAndSettle();
    expect(find.text('Review Investment Transaction'), findsOneWidget);
    expect(find.text('NDQ'), findsOneWidget);
    await $.tester.drag(find.byType(ListView), const Offset(0, -800));
    await $.pumpAndSettle();
    await $.tester.tap(find.text('Save'));
    await $.pumpAndSettle();
    expect(find.text('Investment transaction saved.'), findsOneWidget);

    Navigator.of($.tester.element(find.text('Upload Investment PDFs'))).pop();
    await $.pumpAndSettle();
    await $.tester.tap(find.text('View saved transactions'));
    await $.pumpAndSettle();
    expect(find.textContaining('NDQ'), findsOneWidget);

    Navigator.of($.tester.element(find.text('Investment Transactions'))).pop();
    await $.pumpAndSettle();
    await $.tester.tap(find.text('Run CGT estimate'));
    await $.pumpAndSettle();
    await $.tester.tap(find.text('Select cut-off date'));
    await $.pumpAndSettle();
    await $.tester.tap(find.text('13').last);
    await $.tester.tap(find.text('OK'));
    await $.pumpAndSettle();
    await $.tester.enterText(find.byType(TextField).first, '75');
    await $.tester.tap(find.text('Calculate'));
    await $.pumpAndSettle();

    expect(find.textContaining('Investment CGT Results'), findsOneWidget);
    expect(find.textContaining('Estimated gain/loss'), findsOneWidget);
  });
}
