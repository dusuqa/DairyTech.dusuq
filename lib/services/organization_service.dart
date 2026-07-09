import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dusuq/models/organization.dart';

class OrganizationService {
  final SupabaseClient _supabase;
  OrganizationService({SupabaseClient? client}) : _supabase = client ?? Supabase.instance.client;

  /// OrgAdmin view: a single live document read.
  Stream<Organization?> watchOrganization(String orgId) {
    return _supabase
        .from('organizations')
        .stream(primaryKey: ['id'])
        .eq('id', orgId)
        .map((list) => list.isEmpty ? null : Organization.fromMap(list.first));
  }

  /// SuperAdmin view: every organization doc, combined client-side.
  Stream<List<Organization>> watchAllOrganizations() {
    return _supabase
        .from('organizations')
        .stream(primaryKey: ['id'])
        .map((list) => list.map((m) => Organization.fromMap(m)).toList());
  }
}
