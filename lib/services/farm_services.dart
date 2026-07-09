// =============================================================================
// DUSUQ - Dairy Farm ERP
// Services: MilkService | BreedingService
//
// IMPORTANT — REPLACES the original farm_services.dart MilkService/
// BreedingService implementations. The original single-tenant versions
// queried milk_records/breeding_records with no orgId filter — under the
// new firestore.rules, an unfiltered query would now return PERMISSION
// DENIED for any document outside the caller's org (rules deny at the
// document level, but Firestore still requires the query itself to be
// shaped compatibly — an unscoped collection().snapshots() works for
// SuperAdmin only). Every method below takes orgId explicitly so a Farmer
// or OrgAdmin's queries are scoped correctly and don't trip rule denials
// on partial result sets.
//
// FeedService / MedicalService follow the identical pattern — not written
// out here to keep this file focused on the two services the farmer tiles
// in this task actually need; replicate this same orgId-scoping shape for
// those two when wiring the Feed Log and Health Log tiles next.
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dusuq/models/farm_models.dart';

class MilkService {
  final FirebaseFirestore _db;
  MilkService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('milk_records');

  /// Add a new milk record. orgId and createdBy are required arguments
  /// (not optional, not defaulted) specifically so a caller can't
  /// accidentally omit them and create an orphaned record that the
  /// security rules' `request.resource.data.orgId == orgId()` check would
  /// reject anyway — better to fail at the Dart type level than at the
  /// network round-trip.
  Future<String> addRecord({
    required String orgId,
    required String animalId,
    required DateTime date,
    required double quantity,
    String? session,
    required String createdBy,
  }) async {
    final record = MilkRecord(
      id: '', // assigned by Firestore
      orgId: orgId,
      animalId: animalId,
      date: date,
      quantity: quantity,
      session: session,
      createdBy: createdBy,
    );
    final ref = await _col.add(record.toFirestore());
    return ref.id;
  }

  Future<void> updateRecord(MilkRecord record) =>
      _col.doc(record.id).update(record.toFirestore());

  Future<void> deleteRecord(String recordId) => _col.doc(recordId).delete();

  /// Live stream of today's milk records for one org — what the farmer's
  /// quick-entry screen shows as "already logged today".
  Stream<List<MilkRecord>> watchToday(String orgId) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _col
        .where('orgId', isEqualTo: orgId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('date', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => MilkRecord.fromFirestore(d)).toList());
  }

  /// Records for one specific animal across a date range (used by
  /// animal_detail_screen's Milk tab).
  Stream<List<MilkRecord>> watchForAnimal({
    required String orgId,
    required String animalId,
    DateTime? from,
    DateTime? to,
  }) {
    Query<Map<String, dynamic>> q = _col
        .where('orgId', isEqualTo: orgId)
        .where('animalId', isEqualTo: animalId);
    if (from != null) {
      q = q.where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(from));
    }
    if (to != null) {
      q = q.where('date', isLessThanOrEqualTo: Timestamp.fromDate(to));
    }
    return q
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => MilkRecord.fromFirestore(d)).toList());
  }

  /// One-off total for a date range — used for ad-hoc reports. For the
  /// Admin Dashboard's running totals, prefer the maintained aggregate on
  /// organizations/{orgId} (see OrganizationService) instead of calling
  /// this repeatedly; this method still reads every matching document and
  /// is appropriate for bounded, occasional queries (e.g. "show me last
  /// week"), not for a metric refreshed on every dashboard open.
  Future<double> totalForRange({
    required String orgId,
    required DateTime from,
    required DateTime to,
  }) async {
    final snap = await _col
        .where('orgId', isEqualTo: orgId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(to))
        .get();
    return snap.docs.fold<double>(
      0,
      (sum, doc) => sum + ((doc.data()['quantity'] as num?)?.toDouble() ?? 0),
    );
  }
}

class BreedingService {
  final FirebaseFirestore _db;
  BreedingService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('breeding_records');

  Future<String> addRecord({
    required String orgId,
    required String animalId,
    required DateTime date,
    required BreedingEvent event,
    String? method,
    String? bullSireId,
    String? technicianName,
    String? notes,
    required String createdBy,
  }) async {
    // Auto-compute expected calving date when an AI/service event is
    // logged, same logic as the Sheets version (date + 280 days). Farmer
    // never has to calculate this by hand.
    DateTime? expectedCalving;
    if (event == BreedingEvent.aiDone || event == BreedingEvent.naturalService) {
      expectedCalving = date.add(const Duration(days: 280));
    }

    final record = BreedingRecord(
      id: '',
      orgId: orgId,
      animalId: animalId,
      date: date,
      event: event,
      method: method,
      bullSireId: bullSireId,
      technicianName: technicianName,
      expectedCalvingDate: expectedCalving,
      notes: notes,
      createdBy: createdBy,
    );
    final ref = await _col.add(record.toFirestore());
    return ref.id;
  }

  Future<void> deleteRecord(String recordId) => _col.doc(recordId).delete();

  Stream<List<BreedingRecord>> watchForAnimal({
    required String orgId,
    required String animalId,
  }) {
    return _col
        .where('orgId', isEqualTo: orgId)
        .where('animalId', isEqualTo: animalId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => BreedingRecord.fromFirestore(d)).toList());
  }

  /// Animals with an expected calving date in the next N days — the
  /// "calving reminders" capability from the original MVP, now org-scoped.
  /// NOTE: this requires a composite index on (orgId ASC, expectedCalvingDate ASC) —
  /// see FIRESTORE_SCHEMA.md for the full index list to add.
  Stream<List<BreedingRecord>> watchUpcomingCalvings({
    required String orgId,
    int withinDays = 30,
  }) {
    final now = DateTime.now();
    final cutoff = now.add(Duration(days: withinDays));
    return _col
        .where('orgId', isEqualTo: orgId)
        .where('expectedCalvingDate', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .where('expectedCalvingDate', isLessThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('expectedCalvingDate')
        .snapshots()
        .map((snap) => snap.docs.map((d) => BreedingRecord.fromFirestore(d)).toList());
  }

  /// Recent breeding events across the whole org (not filtered to one
  /// animal) — used by the farmer tile's activity list.
  Stream<List<BreedingRecord>> watchRecent({
    required String orgId,
    int limit = 20,
  }) {
    return _col
        .where('orgId', isEqualTo: orgId)
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => BreedingRecord.fromFirestore(d)).toList());
  }
}

class FeedService {
  final FirebaseFirestore _db;
  FeedService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('feed_expenses');

  Future<String> addRecord({
    required String orgId,
    required String type,
    required double cost,
    required double quantity,
    required String unit,
    String? supplier,
    required DateTime date,
    required String createdBy,
  }) async {
    final record = FeedExpense(
      id: '',
      orgId: orgId,
      type: type,
      cost: cost,
      quantity: quantity,
      unit: unit,
      supplier: supplier,
      date: date,
      createdBy: createdBy,
    );
    final ref = await _col.add(record.toFirestore());
    return ref.id;
  }

  Future<void> deleteRecord(String recordId) => _col.doc(recordId).delete();

  /// Today's feed purchases for one org — mirrors MilkService.watchToday,
  /// shown beneath the entry form so a farmhand sees what's already been
  /// logged today without leaving the screen.
  Stream<List<FeedExpense>> watchToday(String orgId) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _col
        .where('orgId', isEqualTo: orgId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('date', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => FeedExpense.fromFirestore(d)).toList());
  }

  /// Recent feed purchases across the org, not date-bounded — used for a
  /// general activity list (e.g. "last 20 purchases") rather than a
  /// strictly-today view.
  Stream<List<FeedExpense>> watchRecent({
    required String orgId,
    int limit = 20,
  }) {
    return _col
        .where('orgId', isEqualTo: orgId)
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => FeedExpense.fromFirestore(d)).toList());
  }

  /// One-off cost total for a date range. As with MilkService.totalForRange,
  /// this reads every matching document — fine for bounded ad-hoc reports,
  /// not for a metric refreshed on every dashboard open (use a maintained
  /// aggregate on organizations/{orgId} for that instead — feed cost isn't
  /// wired into the aggregate Cloud Functions yet; add an onFeedExpenseWrite
  /// trigger mirroring onMilkRecordWrite if/when a "Total Feed Cost"
  /// dashboard tile is needed).
  Future<double> totalCostForRange({
    required String orgId,
    required DateTime from,
    required DateTime to,
  }) async {
    final snap = await _col
        .where('orgId', isEqualTo: orgId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(to))
        .get();
    return snap.docs.fold<double>(
      0,
      (sum, doc) => sum + ((doc.data()['cost'] as num?)?.toDouble() ?? 0),
    );
  }
}

class MedicalService {
  final FirebaseFirestore _db;
  MedicalService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('medical_records');

  Future<String> addRecord({
    required String orgId,
    required String animalId,
    required HealthCategory category,
    String? description,
    String? medicine,
    String? dosage,
    String? vetName,
    double? cost,
    required DateTime date,
    DateTime? followUpDate,
    String? notes,
    required String createdBy,
  }) async {
    final record = MedicalRecord(
      id: '',
      orgId: orgId,
      animalId: animalId,
      category: category,
      description: description,
      medicine: medicine,
      dosage: dosage,
      vetName: vetName,
      cost: cost,
      date: date,
      followUpDate: followUpDate,
      notes: notes,
      createdBy: createdBy,
    );
    final ref = await _col.add(record.toFirestore());
    return ref.id;
  }

  Future<void> deleteRecord(String recordId) => _col.doc(recordId).delete();

  Stream<List<MedicalRecord>> watchForAnimal({
    required String orgId,
    required String animalId,
  }) {
    return _col
        .where('orgId', isEqualTo: orgId)
        .where('animalId', isEqualTo: animalId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => MedicalRecord.fromFirestore(d)).toList());
  }

  Stream<List<MedicalRecord>> watchRecent({
    required String orgId,
    int limit = 20,
  }) {
    return _col
        .where('orgId', isEqualTo: orgId)
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => MedicalRecord.fromFirestore(d)).toList());
  }

  /// Records with a follow-up date in the next N days — surfaces things
  /// like "re-check this animal's mastitis treatment in 5 days" so an
  /// OrgAdmin or farmer doesn't have to remember manually. Mirrors
  /// BreedingService.watchUpcomingCalvings' shape intentionally, since both
  /// are "things coming due soon" queries the dashboard/field view could
  /// surface the same way.
  /// NOTE: requires composite index (orgId ASC, followUpDate ASC) — add to
  /// FIRESTORE_SCHEMA.md's index list before relying on this in production.
  Stream<List<MedicalRecord>> watchUpcomingFollowUps({
    required String orgId,
    int withinDays = 14,
  }) {
    final now = DateTime.now();
    final cutoff = now.add(Duration(days: withinDays));
    return _col
        .where('orgId', isEqualTo: orgId)
        .where('followUpDate', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .where('followUpDate', isLessThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('followUpDate')
        .snapshots()
        .map((snap) => snap.docs.map((d) => MedicalRecord.fromFirestore(d)).toList());
  }
}
