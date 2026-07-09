import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dusuq/providers/auth_providers.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _canResend = true;
  Timer? _timer;
  bool _loading = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Auto-reload to check if email was verified every 3 seconds
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) => _checkEmailVerified());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkEmailVerified() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await user.reload();
      if (user.emailVerified) {
        _timer?.cancel();
        // Trigger a notifier update or refresh in providers
        ref.invalidate(authStateProvider);
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    if (!_canResend) return;

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      await ref.read(authServiceProvider).sendEmailVerification();
      setState(() {
        _canResend = false;
        _message = 'Verification email has been resent.';
        _loading = false;
      });
      // Throttle resends to every 60 seconds
      Future.delayed(const Duration(seconds: 60), () {
        if (mounted) setState(() => _canResend = true);
      });
    } catch (e) {
      setState(() {
        _message = 'Could not send verification email. Try again later.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mark_email_read_outlined, size: 64, color: Color(0xFF2E7D32)),
                  const SizedBox(height: 24),
                  const Text(
                    'Verify your Email',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'A verification link has been sent to:\n${user?.email ?? ""}\n\nPlease check your inbox and verify your email to continue.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  if (_message != null) ...[
                    Text(
                      _message!,
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],
                  _loading
                      ? const CircularProgressIndicator()
                      : FilledButton.icon(
                          onPressed: _canResend ? _resendVerificationEmail : null,
                          icon: const Icon(Icons.email_outlined),
                          label: Text(_canResend ? 'Resend Email' : 'Resend in 60s'),
                        ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => ref.read(authServiceProvider).signOut(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Cancel & Sign Out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
