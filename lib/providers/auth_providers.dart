import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dusuq/models/user_profile.dart';
import 'package:dusuq/models/organization.dart';
import 'package:dusuq/services/auth_service.dart';
import 'package:dusuq/services/organization_service.dart';
import 'package:dusuq/services/farm_services.dart';
import 'package:dusuq/services/animal_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final organizationServiceProvider =
    Provider<OrganizationService>((ref) => OrganizationService());
final milkServiceProvider = Provider<MilkService>((ref) => MilkService());
final breedingServiceProvider =
    Provider<BreedingService>((ref) => BreedingService());
final feedServiceProvider = Provider<FeedService>((ref) => FeedService());
final medicalServiceProvider = Provider<MedicalService>((ref) => MedicalService());
final animalServiceProvider = Provider<AnimalService>((ref) => AnimalService());

/// Raw Supabase auth state — null means signed out.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// The live user profile document, re-evaluated whenever auth state changes.
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) {
      if (user == null) return Stream.value(null);
      return ref.watch(authServiceProvider).watchUserProfile(user.id);
    },
    loading: () => Stream.value(null),
    error: (_, __) => Stream.value(null),
  );
});

/// The org aggregate data the Admin Dashboard displays.
final dashboardOrganizationProvider = StreamProvider<Organization?>((ref) {
  final profile = ref.watch(userProfileProvider).valueOrNull;
  if (profile == null) return Stream.value(null);

  final orgService = ref.watch(organizationServiceProvider);

  if (profile.isSuperAdmin) {
    return orgService.watchAllOrganizations().map(
          (orgs) => orgs.isEmpty ? null : Organization.combine(orgs),
        );
  }

  if (profile.isOrgAdmin && profile.orgId.isNotEmpty) {
    return orgService.watchOrganization(profile.orgId);
  }

  return Stream.value(null);
});
