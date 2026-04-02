import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Security: on Flutter Web (e.g. GitHub Pages), default Firebase Auth
  // persistence can survive tab close and be restored on next open. Use
  // SESSION persistence so closing the tab clears auth state for that tab.
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.SESSION);
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = GoogleFonts.workSansTextTheme(
      Theme.of(context).textTheme,
    );
    final displayTextTheme = GoogleFonts.dmSerifDisplayTextTheme(baseTextTheme);
    final colorScheme = const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF102A43),
      onPrimary: Colors.white,
      secondary: Color(0xFFC58545),
      onSecondary: Color(0xFF102A43),
      error: Color(0xFFB42318),
      onError: Colors.white,
      surface: Color(0xFFF9F6EE),
      onSurface: Color(0xFF102A43),
    );

    return MaterialApp(
      title: 'Tax Auto Extraction',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF6F3EA),
        textTheme: baseTextTheme.copyWith(
          headlineLarge: displayTextTheme.headlineLarge,
          headlineMedium: displayTextTheme.headlineMedium,
          headlineSmall: displayTextTheme.headlineSmall,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: Color(0xFF102A43),
        ),
        cardTheme: CardThemeData(
          color: Colors.white.withValues(alpha: 0.88),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: const Color(0xFF102A43).withValues(alpha: 0.10),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.92),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: const Color(0xFF102A43).withValues(alpha: 0.18),
            ),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Color(0xFFC58545), width: 1.4),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF102A43),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasData) {
            return const HomeScreen(); // User is logged in
          }

          return const AuthScreen(); // User is not logged in
        },
      ),
    );
  }
}
