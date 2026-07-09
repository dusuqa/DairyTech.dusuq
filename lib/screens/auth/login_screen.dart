import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:dusuq/services/auth_service.dart';

enum _LoginMode { email, phone }

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  const LoginScreen({super.key, required this.authService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  _LoginMode _mode = _LoginMode.email;

  // Email/password controllers
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFormKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  // Phone OTP controllers
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  String? _verificationId;
  bool _otpSent = false;

  bool _loading = false;
  String? _errorText;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _setError(String? message) {
    setState(() => _errorText = message);
  }

  Future<void> _submitEmailLogin() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await widget.authService.signInWithEmail(
        _emailCtrl.text,
        _passwordCtrl.text,
      );
      // Navigation happens automatically — the router listens to
      // authStateChanges + watchUserProfile and redirects based on role.
      // This screen does not navigate manually.
    } on FirebaseAuthException catch (e) {
      _setError(_friendlyAuthError(e));
    } catch (e) {
      _setError('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await widget.authService.signInWithGoogle();
    } on FirebaseAuthException catch (e) {
      _setError(_friendlyAuthError(e));
    } catch (e) {
      _setError('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty || !phone.startsWith('+')) {
      _setError('Enter phone number with country code, e.g. +92 3xx xxxxxxx');
      return;
    }
    setState(() {
      _loading = true;
      _errorText = null;
    });
    await widget.authService.startPhoneSignIn(
      phoneNumber: phone,
      onCodeSent: (verificationId) {
        setState(() {
          _verificationId = verificationId;
          _otpSent = true;
          _loading = false;
        });
      },
      onError: (e) {
        setState(() {
          _loading = false;
          _errorText = _friendlyAuthError(e);
        });
      },
    );
  }

  Future<void> _confirmOtp() async {
    if (_verificationId == null) return;
    final code = _otpCtrl.text.trim();
    if (code.length < 6) {
      _setError('Enter the 6-digit code sent to your phone.');
      return;
    }
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await widget.authService.confirmPhoneCode(
        verificationId: _verificationId!,
        smsCode: code,
      );
    } on FirebaseAuthException catch (e) {
      _setError(_friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-disabled':
        return 'This account has been disabled. Contact your farm admin.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'invalid-verification-code':
        return 'That code is incorrect. Check and try again.';
      case 'network-request-failed':
        return 'No internet connection. Check your signal and retry.';
      default:
        return e.message ?? 'Login failed. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildLogo(theme),
                  const SizedBox(height: 32),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildModeToggle(theme),
                          const SizedBox(height: 20),
                          if (_errorText != null) ...[
                            _buildErrorBanner(theme),
                            const SizedBox(height: 16),
                          ],
                          if (_mode == _LoginMode.email)
                            _buildEmailForm(theme)
                          else
                            _buildPhoneForm(theme),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'New farm or cooperative?',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextButton(
                        onPressed: _loading ? null : () => context.go('/register'),
                        child: const Text('Register Now'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo(ThemeData theme) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            Icons.agriculture_outlined,
            size: 36,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 16),
        Text('DUSUQ', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
        Text(
          'Dairy Farm Management',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildModeToggle(ThemeData theme) {
    return SegmentedButton<_LoginMode>(
      segments: const [
        ButtonSegment(
          value: _LoginMode.email,
          label: Text('Email'),
          icon: Icon(Icons.email_outlined),
        ),
        ButtonSegment(
          value: _LoginMode.phone,
          label: Text('Phone'),
          icon: Icon(Icons.phone_android_outlined),
        ),
      ],
      selected: {_mode},
      onSelectionChanged: _loading
          ? null
          : (selection) {
              setState(() {
                _mode = selection.first;
                _errorText = null;
                _otpSent = false;
              });
            },
    );
  }

  Widget _buildErrorBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorText!,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailForm(ThemeData theme) {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            enabled: !_loading,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            autofillHints: const [AutofillHints.password],
            enabled: !_loading,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
              border: const OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              return null;
            },
            onFieldSubmitted: (_) => _submitEmailLogin(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _loading ? null : _showForgotPasswordDialog,
              child: const Text('Forgot password?'),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _loading ? null : _submitEmailLogin,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Sign In'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'OR',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _loading ? null : _signInWithGoogle,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            icon: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              alignment: Alignment.center,
              child: const Text(
                'G',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.blue,
                ),
              ),
            ),
            label: const Text('Sign In with Google'),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneForm(ThemeData theme) {
    if (!_otpSent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            enabled: !_loading,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '+92 3xx xxxxxxx',
              prefixIcon: Icon(Icons.phone_android_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading ? null : _sendOtp,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Send Code'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the 6-digit code sent to ${_phoneCtrl.text}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          enabled: !_loading,
          decoration: const InputDecoration(
            labelText: 'Verification code',
            prefixIcon: Icon(Icons.sms_outlined),
            border: OutlineInputBorder(),
            counterText: '',
          ),
          onFieldSubmitted: (_) => _confirmOtp(),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _loading ? null : _confirmOtp,
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Verify & Sign In'),
        ),
        TextButton(
          onPressed: _loading
              ? null
              : () => setState(() {
                    _otpSent = false;
                    _otpCtrl.clear();
                  }),
          child: const Text('Use a different number'),
        ),
      ],
    );
  }

  void _showForgotPasswordDialog() {
    final resetEmailCtrl = TextEditingController(text: _emailCtrl.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset password'),
        content: TextField(
          controller: resetEmailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await widget.authService.sendPasswordReset(resetEmailCtrl.text);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password reset email sent.')),
                  );
                }
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not send reset email.')),
                  );
                }
              }
            },
            child: const Text('Send Reset Link'),
          ),
        ],
      ),
    );
  }
}
