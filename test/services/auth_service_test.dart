import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/services/auth_service.dart';

void main() {
  group('AuthService', () {
    late MockFirebaseAuth mockAuth;
    late AuthService authService;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      authService = AuthService(auth: mockAuth);
    });

    test('signInWithEmailPassword returns user on success', () async {
      final user = await authService.signInWithEmailPassword('test@example.com', 'password');
      expect(user, isNotNull);
      expect(mockAuth.currentUser, isNotNull);
    });

    test('createUserWithEmailPassword returns user on success', () async {
      final user = await authService.createUserWithEmailPassword('new@example.com', 'password');
      expect(user, isNotNull);
      expect(mockAuth.currentUser, isNotNull);
    });

    test('signOut clears current user', () async {
      await authService.signInWithEmailPassword('test@example.com', 'password');
      expect(mockAuth.currentUser, isNotNull);
      
      await authService.signOut();
      expect(mockAuth.currentUser, isNull);
    });

    test('authStateChanges returns stream of users', () async {
      final stream = authService.authStateChanges;
      expect(stream, emitsInOrder([isNull, isNotNull, isNull]));
      
      await authService.signInWithEmailPassword('test@example.com', 'password');
      await authService.signOut();
    });
  });
}
