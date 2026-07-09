import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:dusuq/providers/auth_providers.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  String? _errorText;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  void _setError(String? msg) {
    setState(() => _errorText = msg);
  }

  Future<void> _submitRegister() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _errorText = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.registerWithEmail(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );
      await authService.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      _setError(_friendlyAuthError(e));
    } catch (e) {
      _setError('Signup failed. Please try again.');
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
      await ref.read(authServiceProvider).signInWithGoogle();
    } on FirebaseAuthException catch (e) {
      _setError(_friendlyAuthError(e));
    } catch (e) {
      _setError('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email address is already in use.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'The password is too weak (min 6 characters).';
      case 'operation-not-allowed':
        return 'Email/password signup is not enabled.';
      default:
        return e.message ?? 'Registration failed. Please try again.';
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
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Create Account',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Register as a new farm administrator',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (_errorText != null) ...[
                              _buildErrorBanner(theme),
                              const SizedBox(height: 16),
                            ],
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
                              autofillHints: const [AutofillHints.newPassword],
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
                                if (v.length < 6) return 'Password must be at least 6 characters';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmPasswordCtrl,
                              obscureText: _obscureConfirmPassword,
                              autofillHints: const [AutofillHints.newPassword],
                              enabled: !_loading,
                              decoration: InputDecoration(
                                labelText: 'Confirm Password',
                                prefixIcon: const Icon(Icons.lock_reset),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  ),
                                  onPressed: () {
                                    setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                                  },
                                ),
                                border: const OutlineInputBorder(),
                              ),
                              validator: (v) {
                                if (v != _passwordCtrl.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: _loading ? null : _submitRegister,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Register'),
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
                              label: const Text('Register with Google'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account?',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextButton(
                        onPressed: _loading ? null : () => context.go('/login'),
                        child: const Text('Sign In'),
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
}
