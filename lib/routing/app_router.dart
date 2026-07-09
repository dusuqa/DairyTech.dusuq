import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dusuq/models/user_profile.dart';
import 'package:dusuq/providers/auth_providers.dart';
import 'package:dusuq/screens/auth/login_screen.dart';
import 'package:dusuq/screens/admin/admin_dashboard_screen.dart';
import 'package:dusuq/screens/admin/user_management_screen.dart';
import 'package:dusuq/screens/farmer/farmer_field_view_screen.dart';
import 'package:dusuq/screens/loading_screen.dart';
import 'package:dusuq/screens/pending_invite_screen.dart';
import 'package:dusuq/screens/auth/register_screen.dart';
import 'package:dusuq/screens/auth/verify_email_screen.dart';
import 'package:dusuq/screens/auth/setup_org_screen.dart';

/// Central route guard. This is the ONLY place that decides which screen a
/// signed-in user sees. Farmers are routed to /farmer and the router refuses
/// to let them reach anything under /admin/* — even a direct deep link or a
/// browser back-button trick redirects them away. This is the routing-layer
/// half of access control; firestore.rules is the data-layer half. Neither
/// is sufficient alone (rules without route guards would let a Farmer see
/// an empty Admin UI shell; route guards without rules would be bypassable
/// by anyone calling Firestore directly).
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final profileState = ref.watch(userProfileProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: _RouterRefreshNotifier(ref),
    redirect: (context, state) {
      final user = authState.valueOrNull;
      final isLoggedIn = user != null;
      final loggingIn = state.matchedLocation == '/login';
      final registering = state.matchedLocation == '/register';

      // Auth state itself still resolving (app just launched) — show a
      // neutral loading screen rather than flashing the login page.
      if (authState.isLoading) return '/loading';

      if (!isLoggedIn) {
        if (loggingIn || registering) return null;
        return '/login';
      }

      // ── Email Verification Guard ──
      // If signed in via email, but email is not verified, force them to verify page.
      // (Excluding phone numbers which don't have email verification or have verified phone).
      if (user.email != null && user.email!.isNotEmpty && !user.emailVerified) {
        if (state.matchedLocation == '/verify-email') return null;
        return '/verify-email';
      }

      // Signed in, but Firestore profile doc hasn't loaded yet (or doesn't
      // exist — e.g. mid-signup race). Don't route into either dashboard
      // until we actually know the role.
      if (profileState.isLoading) return '/loading';

      final profile = profileState.valueOrNull;
      if (profile == null) {
        // If they are registering, they might not have a profile yet (need to select / create org).
        // Send to onboarding / setup-org screen if they have no profile.
        if (state.matchedLocation == '/setup-org') return null;
        return '/setup-org';
      }

      if (profile.status == UserStatus.disabled) {
        return '/pending'; // shows a "contact your admin" message
      }

      if (loggingIn || registering || state.matchedLocation == '/setup-org' || state.matchedLocation == '/verify-email') {
        // Already authenticated and landed back on auth/onboarding pages — bounce to the
        // correct home for their role.
        return profile.canAccessAdminDashboard ? '/admin' : '/farmer';
      }

      // ── The core role split ──
      final goingToAdmin = state.matchedLocation.startsWith('/admin');
      final goingToFarmer = state.matchedLocation.startsWith('/farmer');

      if (goingToAdmin && !profile.canAccessAdminDashboard) {
        // A Farmer tried to reach /admin/* by any means (typed URL, deep
        // link, stale bookmark). Hard redirect, no admin UI ever renders.
        return '/farmer';
      }

      if (goingToFarmer && profile.canAccessAdminDashboard) {
        // OrgAdmin/SuperAdmin landing on /farmer (e.g. testing) is allowed
        // through in this design — admins CAN see the field view to verify
        // what farmers see. If you want to forbid this too, redirect to
        // '/admin' here instead. Left permissive intentionally.
        return null;
      }

      // Root path with no explicit destination — send to role home.
      if (state.matchedLocation == '/') {
        return profile.canAccessAdminDashboard ? '/admin' : '/farmer';
      }

      return null; // no redirect needed
    },
    routes: [
      GoRoute(path: '/loading', builder: (_, __) => const LoadingScreen()),
      GoRoute(path: '/pending', builder: (_, __) => const PendingInviteScreen()),
      GoRoute(
        path: '/login',
        builder: (_, __) => LoginScreen(authService: ref.read(authServiceProvider)),
      ),
      GoRoute(
        path: '/register',
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (_, __) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: '/setup-org',
        builder: (_, __) => const SetupOrgScreen(),
      ),

      // ── Admin shell: SuperAdmin + OrgAdmin only (enforced above) ──
      GoRoute(
        path: '/admin',
        builder: (_, __) => const AdminDashboardScreen(),
        routes: [
          GoRoute(
            path: 'users',
            builder: (_, __) => const UserManagementScreen(),
          ),
        ],
      ),

      // ── Farmer shell: field data entry only ──
      GoRoute(
        path: '/farmer',
        builder: (_, __) => const FarmerFieldViewScreen(),
      ),
    ],
  );
});

/// Bridges Riverpod's stream-based state into GoRouter's Listenable-based
/// refresh mechanism, so route guards re-evaluate the moment auth state OR
/// the profile doc changes — not just on navigation events.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(userProfileProvider, (_, __) => notifyListeners());
  }
}
