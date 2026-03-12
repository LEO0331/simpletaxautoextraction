import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/screens/home_screen.dart';
import 'package:simpletaxautoextraction/services/auth_service.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';
import 'package:simpletaxautoextraction/services/pdf_extraction_service.dart';

class MockUser implements User {
  @override
  String get uid => 'test_uid';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuthService implements AuthService {
  bool isSignOutCalled = false;

  @override
  User? get currentUser => MockUser();

  @override
  Stream<User?> get authStateChanges => Stream.value(MockUser());

  @override
  Future<void> signOut() async {
    isSignOutCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockFirestoreService implements FirestoreService {
  @override
  Stream<List<TaxRecord>> getUserTaxRecords(String userId) {
    return Stream.value([
      TaxRecord(
        id: 'record1',
        userId: userId,
        financialYear: '2024-2025',
        income: {'Gross rent': 5000.0},
        expenses: {'Water charges': 100.0},
      )
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockPdfExtractionService implements PdfExtractionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget buildApp({
    AuthService? authService,
    FirestoreService? firestoreService,
    PdfExtractionService? pdfService,
  }) {
    return MaterialApp(
      home: HomeScreen(
        authService: authService ?? MockAuthService(),
        firestoreService: firestoreService ?? MockFirestoreService(),
        pdfExtractionService: pdfService ?? MockPdfExtractionService(),
      ),
    );
  }

  testWidgets('HomeScreen shows records properly', (WidgetTester tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('FY 2024-2025'), findsOneWidget);
    expect(find.text('Income: \$5000.00'), findsOneWidget);
    expect(find.text('Expenses: \$100.00'), findsOneWidget);
    expect(find.text('\$4900.00'), findsOneWidget); // Net Position
  });

  testWidgets('HomeScreen calls signOut on logout button tap', (WidgetTester tester) async {
    final authService = MockAuthService();
    await tester.pumpWidget(buildApp(authService: authService));
    await tester.pumpAndSettle();

    // The logout button
    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(authService.isSignOutCalled, isTrue);
  });
}
