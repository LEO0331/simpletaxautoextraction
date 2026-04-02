import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/screens/auth_screen.dart';
import 'package:simpletaxautoextraction/services/auth_service.dart';

class MockAuthService implements AuthService {
  bool isCreateCalled = false;
  bool isSignInCalled = false;
  bool throwUnexpected = false;

  @override
  Stream<User?> get authStateChanges => const Stream.empty();

  @override
  User? get currentUser => null;

  @override
  Future<User?> signInWithEmailPassword(String email, String password) async {
    if (throwUnexpected) {
      throw Exception('boom');
    }
    if (email == 'error@test.com') {
      throw FirebaseAuthException(code: 'error', message: 'Test error message');
    }
    isSignInCalled = true;
    return null;
  }

  @override
  Future<User?> createUserWithEmailPassword(
    String email,
    String password,
  ) async {
    if (throwUnexpected) {
      throw Exception('boom');
    }
    if (email == 'error@test.com') {
      throw FirebaseAuthException(code: 'error', message: 'Test error message');
    }
    isCreateCalled = true;
    return null;
  }

  @override
  Future<void> signOut() async {}
}

void main() {
  Widget buildApp(MockAuthService mockAuthService) {
    return MaterialApp(home: AuthScreen(authService: mockAuthService));
  }

  testWidgets('AuthScreen shows login UI by default', (
    WidgetTester tester,
  ) async {
    final mockAuth = MockAuthService();
    await tester.pumpWidget(buildApp(mockAuth));

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign In'), findsWidgets);
    expect(find.text('Don\'t have an account? Sign Up'), findsOneWidget);
  });

  testWidgets('AuthScreen switches to sign up UI when tapped', (
    WidgetTester tester,
  ) async {
    final mockAuth = MockAuthService();
    await tester.pumpWidget(buildApp(mockAuth));

    await tester.tap(find.text('Don\'t have an account? Sign Up'));
    await tester.pumpAndSettle();

    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Sign Up'), findsWidgets);
    expect(find.text('Already have an account? Sign In'), findsOneWidget);
  });

  testWidgets('AuthScreen shows error message on failure', (
    WidgetTester tester,
  ) async {
    final mockAuth = MockAuthService();
    await tester.pumpWidget(buildApp(mockAuth));

    await tester.enterText(find.byType(TextField).first, 'error@test.com');
    await tester.enterText(find.byType(TextField).last, 'password');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Test error message'), findsOneWidget);
  });

  testWidgets('AuthScreen calls signInWithEmailPassword', (
    WidgetTester tester,
  ) async {
    final mockAuth = MockAuthService();
    await tester.pumpWidget(buildApp(mockAuth));

    await tester.enterText(find.byType(TextField).first, 'user@test.com');
    await tester.enterText(find.byType(TextField).last, 'password');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(mockAuth.isSignInCalled, isTrue);
  });

  testWidgets('AuthScreen calls createUserWithEmailPassword', (
    WidgetTester tester,
  ) async {
    final mockAuth = MockAuthService();
    await tester.pumpWidget(buildApp(mockAuth));

    await tester.tap(find.text('Don\'t have an account? Sign Up'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'user@test.com');
    await tester.enterText(find.byType(TextField).last, 'password');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign Up'));
    await tester.pumpAndSettle();

    expect(mockAuth.isCreateCalled, isTrue);
  });

  testWidgets('AuthScreen shows validation messages for invalid input', (
    WidgetTester tester,
  ) async {
    final mockAuth = MockAuthService();
    await tester.pumpWidget(buildApp(mockAuth));

    await tester.enterText(find.byType(TextField).first, 'invalid-email');
    await tester.enterText(find.byType(TextField).last, '123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a valid email address.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'valid@test.com');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(
      find.text('Password must be at least 6 characters.'),
      findsOneWidget,
    );
  });

  testWidgets('AuthScreen handles unexpected errors', (
    WidgetTester tester,
  ) async {
    final mockAuth = MockAuthService()..throwUnexpected = true;
    await tester.pumpWidget(buildApp(mockAuth));

    await tester.enterText(find.byType(TextField).first, 'user@test.com');
    await tester.enterText(find.byType(TextField).last, 'password');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('An unexpected error occurred.'), findsOneWidget);
  });

  testWidgets('AuthScreen renders wide layout content', (
    WidgetTester tester,
  ) async {
    final mockAuth = MockAuthService();
    await tester.binding.setSurfaceSize(const Size(1200, 900));

    await tester.pumpWidget(buildApp(mockAuth));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Australian rental-property worksheets, prepared faster with guided PDF extraction.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Built for accuracy, with review controls before every save.'),
      findsOneWidget,
    );

    await tester.binding.setSurfaceSize(null);
  });
}
