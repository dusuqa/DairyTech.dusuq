import 'package:cloud_firestore/cloud_firestore.dart';

/// Mirrors a `users/{uid}` Firestore document.
///
/// This is the CLIENT-SIDE source of truth the Flutter UI reads to decide
/// what to render. It is intentionally separate from the Auth custom claims
/// (which the security rules use) because claims lag behind a token refresh,
/// while this Firestore doc is live via StreamBuilder and always current.
enum UserRole { superAdmin, orgAdmin, farmer, unknown }

UserRole roleFromString(String? raw) {
  switch (raw) {
    case 'SuperAdmin':
      return UserRole.superAdmin;
    case 'OrgAdmin':
      return UserRole.orgAdmin;
    case 'Farmer':
      return UserRole.farmer;
    default:
      return UserRole.unknown;
  }
}

String roleToString(UserRole role) {
  switch (role) {
    case UserRole.superAdmin:
      return 'SuperAdmin';
    case UserRole.orgAdmin:
      return 'OrgAdmin';
    case UserRole.farmer:
      return 'Farmer';
    case UserRole.unknown:
      return 'unknown';
  }
}

enum UserStatus { active, invited, disabled, unknown }

UserStatus statusFromString(String? raw) {
  switch (raw) {
    case 'active':
      return UserStatus.active;
    case 'invited':
      return UserStatus.invited;
    case 'disabled':
      return UserStatus.disabled;
    default:
      return UserStatus.unknown;
  }
}

class UserProfile {
  final String uid;
  final String orgId; // empty string for SuperAdmin
  final UserRole role;
  final String email;
  final String? phone;
  final String displayName;
  final UserStatus status;
  final DateTime? createdAt;

  const UserProfile({
    required this.uid,
    required this.orgId,
    required this.role,
    required this.email,
    this.phone,
    required this.displayName,
    required this.status,
    this.createdAt,
  });

  bool get isSuperAdmin => role == UserRole.superAdmin;
  bool get isOrgAdmin => role == UserRole.orgAdmin;
  bool get isFarmer => role == UserRole.farmer;

  /// Admin Dashboard is for SuperAdmin and OrgAdmin only. Farmers must never
  /// reach this — enforced both here (routing) AND in firestore.rules
  /// (data access), defense in depth.
  bool get canAccessAdminDashboard => isSuperAdmin || isOrgAdmin;

  factory UserProfile.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return UserProfile(
      uid: doc.id,
      orgId: data['orgId'] as String? ?? '',
      role: roleFromString(data['role'] as String?),
      email: data['email'] as String? ?? '',
      phone: data['phone'] as String?,
      displayName: data['displayName'] as String? ?? '',
      status: statusFromString(data['status'] as String?),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
