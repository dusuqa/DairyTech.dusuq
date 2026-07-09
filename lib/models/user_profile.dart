/// Mirrors a user profile from the database.
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

  bool get canAccessAdminDashboard => isSuperAdmin || isOrgAdmin;

  factory UserProfile.fromMap(Map<String, dynamic> data) {
    return UserProfile(
      uid: data['id'] as String? ?? data['uid'] as String? ?? '',
      orgId: data['org_id'] as String? ?? data['orgId'] as String? ?? '',
      role: roleFromString(data['role'] as String?),
      email: data['email'] as String? ?? '',
      phone: data['phone'] as String?,
      displayName: data['display_name'] as String? ?? data['displayName'] as String? ?? '',
      status: statusFromString(data['status'] as String?),
      createdAt: data['created_at'] != null 
          ? DateTime.tryParse(data['created_at'] as String) 
          : null,
    );
  }
}
