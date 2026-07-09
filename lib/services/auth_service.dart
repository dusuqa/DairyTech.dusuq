import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dusuq/models/user_profile.dart';

/// Centralizes every auth + role-bootstrapping operation. Screens never talk
/// to FirebaseAuth or Firestore directly for auth concerns — they go through
/// this service, so the claims-refresh-after-login gotcha (see below) only
/// has to be handled correctly in ONE place.
class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
    FirebaseFunctions? functions,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // ── Email/password sign in ──
  Future<void> signInWithEmail(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await _postSignIn(cred.user);
  }

  // ── Google sign in ──
  Future<void> signInWithGoogle() async {
    final provider = GoogleAuthProvider();
    UserCredential cred;
    // signInWithPopup is supported on web. On native platforms we throw or fallback.
    cred = await _auth.signInWithPopup(provider);
    await _postSignIn(cred.user);
  }

  // ── Email/password registration ──
  Future<UserCredential> registerWithEmail(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return cred;
  }

  // ── Send Email Verification ──
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  // ── Check if email is verified ──
  bool get isEmailVerified {
    final user = _auth.currentUser;
    if (user == null) return false;
    user.reload(); // Refresh the local cache of auth user status
    return user.emailVerified;
  }

  // ── Phone OTP: step 1, send code ──
  Future<void> startPhoneSignIn({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(FirebaseAuthException e) onError,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto-retrieval on some Android devices — sign in immediately.
        final result = await _auth.signInWithCredential(credential);
        await _postSignIn(result.user);
      },
      verificationFailed: onError,
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  // ── Phone OTP: step 2, confirm code ──
  Future<void> confirmPhoneCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final result = await _auth.signInWithCredential(credential);
    await _postSignIn(result.user);
  }

  /// CRITICAL: custom claims (role, orgId) set by the syncUserClaims Cloud
  /// Function do NOT appear on the client's current ID token automatically.
  /// Firebase caches the token and only refreshes it ~hourly by default.
  /// Forcing a refresh here means a freshly-invited Farmer's first login
  /// immediately has correct claims, instead of being denied by Firestore
  /// rules for up to an hour with a confusing "permission-denied" error.
  Future<void> _postSignIn(User? user) async {
    if (user == null) return;
    await user.getIdToken(true); // force refresh — see note above
    await _db.collection('users').doc(user.uid).update({
      'lastLoginAt': FieldValue.serverTimestamp(),
    }).catchError((_) {
      // Non-fatal: profile doc may not exist yet on very first signup race;
      // the signUpOrgAdmin function sets lastLoginAt itself in that case.
    });
  }

  /// Call again any time you suspect claims are stale (e.g. after an
  /// OrgAdmin changes a user's role and that user is still in-session).
  Future<void> refreshClaims() async {
    final user = _auth.currentUser;
    if (user != null) await user.getIdToken(true);
  }

  // ── Live user profile stream — what the router watches ──
  Stream<UserProfile?> watchUserProfile(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserProfile.fromFirestore(doc);
    });
  }

  // ── First-time OrgAdmin signup: creates org + user doc atomically ──
  Future<Map<String, dynamic>> signUpAsOrgAdmin({
    required String orgName,
    required String displayName,
  }) async {
    final callable = _functions.httpsCallable('signUpOrgAdmin');
    final result = await callable.call({
      'orgName': orgName,
      'displayName': displayName,
    });
    await refreshClaims();
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());
}
