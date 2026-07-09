import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dusuq/models/organization.dart';

class OrganizationService {
  final FirebaseFirestore _db;
  OrganizationService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  /// OrgAdmin view: a single live document read. This is the cheap,
  /// real-time path — Firestore rules also restrict an OrgAdmin to only
  /// being able to read their own org doc, so this query can't accidentally
  /// leak another tenant's numbers even if called wrong.
  Stream<Organization?> watchOrganization(String orgId) {
    return _db.collection('organizations').doc(orgId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Organization.fromFirestore(doc);
    });
  }

  /// SuperAdmin view: every organization doc, combined client-side. Cheap
  /// because it scales with org COUNT (dozens), not with operational
  /// record count (which could be in the hundreds of thousands across a
  /// season). See Organization.combine() and the matching comment in
  /// functions/index.js for why this is deliberately a live query rather
  /// than another maintained aggregate.
  Stream<List<Organization>> watchAllOrganizations() {
    return _db.collection('organizations').snapshots().map((snap) {
      return snap.docs.map((d) => Organization.fromFirestore(d)).toList();
    });
  }
}
