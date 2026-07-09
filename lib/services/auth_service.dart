import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dusuq/models/user_profile.dart';

/// Centralizes every auth + role-bootstrapping operation. Screens never talk
/// to Supabase directly for auth concerns — they go through this service.
class AuthService {
  final SupabaseClient _supabase;

  AuthService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  Stream<User?> get authStateChanges =>
      _supabase.auth.onAuthStateChange.map((event) => event.session?.user);

  User? get currentUser => _supabase.auth.currentUser;

  // ── Email/password sign in ──
  Future<void> signInWithEmail(String email, String password) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    await _postSignIn(response.user);
  }

  // ── Google sign in ──
  Future<void> signInWithGoogle() async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'https://rwlomitusajzuujygwyd.supabase.co/auth/v1/callback',
    );
  }

  // ── Email/password registration ──
  Future<void> registerWithEmail(String email, String password) async {
    final response = await _supabase.auth.signUp(
      email: email.trim(),
      password: password,
    );
    await _postSignIn(response.user);
  }

  // ── Send Email Verification ──
  Future<void> sendEmailVerification() async {
    // Supabase sends sign up verification emails automatically if enabled in dashboard.
    // To resend or trigger OTP/verification link:
    final email = _supabase.auth.currentUser?.email;
    if (email != null) {
      await _supabase.auth.resend(
        type: OtpType.signup,
        email: email,
      );
    }
  }

  // ── Check if email is verified ──
  bool get isEmailVerified {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    return user.emailConfirmedAt != null;
  }

  // ── Phone OTP: step 1, send code ──
  Future<void> startPhoneSignIn({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(dynamic e) onError,
  }) async {
    try {
      await _supabase.auth.signInWithOtp(phone: phoneNumber);
      // Use phone number as the verification ID for step 2 verification
      onCodeSent(phoneNumber);
    } catch (e) {
      onError(e);
    }
  }

  // ── Phone OTP: step 2, confirm code ──
  Future<void> confirmPhoneCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final response = await _supabase.auth.verifyOTP(
      phone: verificationId,
      token: smsCode,
      type: OtpType.sms,
    );
    await _postSignIn(response.user);
  }

  Future<void> _postSignIn(User? user) async {
    if (user == null) return;
    try {
      await _supabase.from('profiles').update({
        'last_login_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', user.id);
    } catch (_) {
      // Non-fatal: profile record might not be created yet in race condition
    }
  }

  /// Keep for interface compatibility, no-op since claims update instantly in Postgres tables
  Future<void> refreshClaims() async {}

  // ── Live user profile stream — what the router watches ──
  Stream<UserProfile?> watchUserProfile(String uid) {
    return _supabase
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', uid)
        .map((event) {
          if (event.isEmpty) return null;
          return UserProfile.fromMap(event.first);
        });
  }

  // ── First-time OrgAdmin signup: creates org + user doc atomically ──
  Future<Map<String, dynamic>> signUpAsOrgAdmin({
    required String orgName,
    required String displayName,
  }) async {
    final result = await _supabase.rpc('sign_up_org_admin', params: {
      'org_name': orgName,
      'display_name': displayName,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> signOut() => _supabase.auth.signOut();

  Future<void> sendPasswordReset(String email) =>
      _supabase.auth.resetPasswordForEmail(email.trim());
}
