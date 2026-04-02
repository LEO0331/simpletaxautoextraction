import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../widgets/stage_background.dart';

class AuthScreen extends StatefulWidget {
  final AuthService? authService;

  const AuthScreen({super.key, this.authService});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late final AuthService _authService;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
  }

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _errorMessage = 'Please enter a valid email address.';
      });
      return;
    }
    if (password.length < 6) {
      setState(() {
        _errorMessage = 'Password must be at least 6 characters.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isLogin) {
        await _authService.signInWithEmailPassword(email, password);
      } else {
        await _authService.createUserWithEmailPassword(email, password);
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.message ?? 'An error occurred during authentication.';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final accent = Theme.of(context).colorScheme.secondary;
    return Scaffold(
      body: StageBackground(
        child: Center(
          child: SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 760;
                    return AppPanel(
                      padding: const EdgeInsets.all(0),
                      child: compact
                          ? _buildAuthForm(primary, accent, compact: true)
                          : Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(36),
                                    decoration: BoxDecoration(
                                      color: primary,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(24),
                                        bottomLeft: Radius.circular(24),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Tax Auto Extraction',
                                          style: GoogleFonts.dmSerifDisplay(
                                            fontSize: 40,
                                            height: 1.05,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Australian rental-property worksheets, prepared faster with guided PDF extraction.',
                                          style: GoogleFonts.workSans(
                                            color: Colors.white.withValues(
                                              alpha: 0.9,
                                            ),
                                            fontSize: 15,
                                            height: 1.5,
                                          ),
                                        ),
                                        const SizedBox(height: 40),
                                        Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: accent.withValues(
                                              alpha: 0.2,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: Text(
                                            'Built for accuracy, with review controls before every save.',
                                            style: GoogleFonts.workSans(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: _buildAuthForm(
                                    primary,
                                    accent,
                                    compact: false,
                                  ),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthForm(Color primary, Color accent, {required bool compact}) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact)
            Text(
              'Tax Auto Extraction',
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 34,
                color: primary,
                height: 1.05,
              ),
              textAlign: TextAlign.center,
            ),
          if (compact) const SizedBox(height: 20),
          Text(
            _isLogin ? 'Welcome Back' : 'Create Account',
            style: GoogleFonts.dmSerifDisplay(
              fontSize: 34,
              color: primary,
              height: 1.1,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _isLogin
                ? 'Sign in to access your tax extractions'
                : 'Sign up to start auto-extracting taxes',
            style: GoogleFonts.workSans(
              fontSize: 14,
              color: const Color(0xFF486581),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEE9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF15A29)),
              ),
              child: Text(
                _errorMessage!,
                style: GoogleFonts.workSans(color: const Color(0xFF7A271A)),
              ),
            ),
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    _isLogin ? 'Sign In' : 'Sign Up',
                    style: GoogleFonts.workSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              setState(() {
                _isLogin = !_isLogin;
                _errorMessage = null;
              });
            },
            child: Text(
              _isLogin
                  ? 'Don\'t have an account? Sign Up'
                  : 'Already have an account? Sign In',
              style: GoogleFonts.workSans(
                color: primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Why users trust this app',
                  style: GoogleFonts.workSans(
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '• Account-protected records via Firebase Auth',
                  style: GoogleFonts.workSans(fontSize: 12, color: primary),
                ),
                Text(
                  '• Firestore rules isolate each user\'s data',
                  style: GoogleFonts.workSans(fontSize: 12, color: primary),
                ),
                Text(
                  '• No bank login required',
                  style: GoogleFonts.workSans(fontSize: 12, color: primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
