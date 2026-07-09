import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dusuq/models/farm_models.dart';

class MilkService {
  final SupabaseClient _supabase;
  MilkService({SupabaseClient? client}) : _supabase = client ?? Supabase.instance.client;

  Future<String> addRecord({
    required String orgId,
    required String animalId,
    required DateTime date,
    required double quantity,
    String? session,
    required String createdBy,
  }) async {
    final record = MilkRecord(
      id: '',
      orgId: orgId,
      animalId: animalId,
      date: date,
      quantity: quantity,
      session: session,
      createdBy: createdBy,
    );
    final response = await _supabase.from('milk_records').insert(record.toMap()).select('id').single();
    return response['id'] as String;
  }

  Future<void> updateRecord(MilkRecord record) =>
      _supabase.from('milk_records').update(record.toMap()).eq('id', record.id);

  Future<void> deleteRecord(String recordId) =>
      _supabase.from('milk_records').delete().eq('id', recordId);

  /// Live stream of today's milk records for one org.
  Stream<List<MilkRecord>> watchToday(String orgId) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _supabase
        .from('milk_records')
        .stream(primaryKey: ['id'])
        .eq('org_id', orgId)
        .map((list) {
          final records = list
              .map((m) => MilkRecord.fromMap(m))
              .where((r) => r.date.isAfter(startOfDay) && r.date.isBefore(endOfDay))
              .toList();
          records.sort((a, b) => b.date.compareTo(a.date));
          return records;
        });
  }

  /// Records for one specific animal across a date range.
  Stream<List<MilkRecord>> watchForAnimal({
    required String orgId,
    required String animalId,
    DateTime? from,
    DateTime? to,
  }) {
    return _supabase
        .from('milk_records')
        .stream(primaryKey: ['id'])
        .eq('org_id', orgId)
        .map((list) {
          var records = list
              .map((m) => MilkRecord.fromMap(m))
              .where((r) => r.animalId == animalId);
          if (from != null) {
            records = records.where((r) => r.date.isAtSameMomentAs(from) || r.date.isAfter(from));
          }
          if (to != null) {
            records = records.where((r) => r.date.isAtSameMomentAs(to) || r.date.isBefore(to));
          }
          final sorted = records.toList();
          sorted.sort((a, b) => b.date.compareTo(a.date));
          return sorted;
        });
  }

  /// One-off total for a date range.
  Future<double> totalForRange({
    required String orgId,
    required DateTime from,
    required DateTime to,
  }) async {
    final response = await _supabase
        .from('milk_records')
        .select('quantity')
        .eq('org_id', orgId)
        .gte('date', from.toUtc().toIso8601String())
        .lte('date', to.toUtc().toIso8601String());
    
    return (response as List).fold<double>(
      0,
      (sum, row) => sum + ((row['quantity'] as num?)?.toDouble() ?? 0),
    );
  }
}

class BreedingService {
  final SupabaseClient _supabase;
  BreedingService({SupabaseClient? client}) : _supabase = client ?? Supabase.instance.client;

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
    final response = await _supabase.from('breeding_records').insert(record.toMap()).select('id').single();
    return response['id'] as String;
  }

  Future<void> deleteRecord(String recordId) =>
      _supabase.from('breeding_records').delete().eq('id', recordId);

  Stream<List<BreedingRecord>> watchForAnimal({
    required String orgId,
    required String animalId,
  }) {
    return _supabase
        .from('breeding_records')
        .stream(primaryKey: ['id'])
        .eq('org_id', orgId)
        .map((list) {
          final records = list
              .map((m) => BreedingRecord.fromMap(m))
              .where((r) => r.animalId == animalId)
              .toList();
          records.sort((a, b) => b.date.compareTo(a.date));
          return records;
        });
  }

  /// Animals with an expected calving date in the next N days.
  Stream<List<BreedingRecord>> watchUpcomingCalvings({
    required String orgId,
    int withinDays = 30,
  }) {
    final now = DateTime.now();
    final cutoff = now.add(Duration(days: withinDays));
    return _supabase
        .from('breeding_records')
        .stream(primaryKey: ['id'])
        .eq('org_id', orgId)
        .map((list) {
          final records = list
              .map((m) => BreedingRecord.fromMap(m))
              .where((r) => r.expectedCalvingDate != null &&
                            (r.expectedCalvingDate!.isAtSameMomentAs(now) || r.expectedCalvingDate!.isAfter(now)) &&
                            (r.expectedCalvingDate!.isAtSameMomentAs(cutoff) || r.expectedCalvingDate!.isBefore(cutoff)))
              .toList();
          records.sort((a, b) => a.expectedCalvingDate!.compareTo(b.expectedCalvingDate!));
          return records;
        });
  }

  /// Recent breeding events across the whole org.
  Stream<List<BreedingRecord>> watchRecent({
    required String orgId,
    int limit = 20,
  }) {
    return _supabase
        .from('breeding_records')
        .stream(primaryKey: ['id'])
        .eq('org_id', orgId)
        .map((list) {
          final records = list.map((m) => BreedingRecord.fromMap(m)).toList();
          records.sort((a, b) => b.date.compareTo(a.date));
          return records.take(limit).toList();
        });
  }
}

class FeedService {
  final SupabaseClient _supabase;
  FeedService({SupabaseClient? client}) : _supabase = client ?? Supabase.instance.client;

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
    final response = await _supabase.from('feed_expenses').insert(record.toMap()).select('id').single();
    return response['id'] as String;
  }

  Future<void> deleteRecord(String recordId) =>
      _supabase.from('feed_expenses').delete().eq('id', recordId);

  /// Today's feed purchases for one org.
  Stream<List<FeedExpense>> watchToday(String orgId) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _supabase
        .from('feed_expenses')
        .stream(primaryKey: ['id'])
        .eq('org_id', orgId)
        .map((list) {
          final records = list
              .map((m) => FeedExpense.fromMap(m))
              .where((r) => r.date.isAfter(startOfDay) && r.date.isBefore(endOfDay))
              .toList();
          records.sort((a, b) => b.date.compareTo(a.date));
          return records;
        });
  }

  /// Recent feed purchases across the org.
  Stream<List<FeedExpense>> watchRecent({
    required String orgId,
    int limit = 20,
  }) {
    return _supabase
        .from('feed_expenses')
        .stream(primaryKey: ['id'])
        .eq('org_id', orgId)
        .map((list) {
          final records = list.map((m) => FeedExpense.fromMap(m)).toList();
          records.sort((a, b) => b.date.compareTo(a.date));
          return records.take(limit).toList();
        });
  }

  /// One-off cost total for a date range.
  Future<double> totalCostForRange({
    required String orgId,
    required DateTime from,
    required DateTime to,
  }) async {
    final response = await _supabase
        .from('feed_expenses')
        .select('cost')
        .eq('org_id', orgId)
        .gte('date', from.toUtc().toIso8601String())
        .lte('date', to.toUtc().toIso8601String());

    return (response as List).fold<double>(
      0,
      (sum, row) => sum + ((row['cost'] as num?)?.toDouble() ?? 0),
    );
  }
}

class MedicalService {
  final SupabaseClient _supabase;
  MedicalService({SupabaseClient? client}) : _supabase = client ?? Supabase.instance.client;

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
    final response = await _supabase.from('medical_records').insert(record.toMap()).select('id').single();
    return response['id'] as String;
  }

  Future<void> deleteRecord(String recordId) =>
      _supabase.from('medical_records').delete().eq('id', recordId);

  Stream<List<MedicalRecord>> watchForAnimal({
    required String orgId,
    required String animalId,
  }) {
    return _supabase
        .from('medical_records')
        .stream(primaryKey: ['id'])
        .eq('org_id', orgId)
        .map((list) {
          final records = list
              .map((m) => MedicalRecord.fromMap(m))
              .where((r) => r.animalId == animalId)
              .toList();
          records.sort((a, b) => b.date.compareTo(a.date));
          return records;
        });
  }

  Stream<List<MedicalRecord>> watchRecent({
    required String orgId,
    int limit = 20,
  }) {
    return _supabase
        .from('medical_records')
        .stream(primaryKey: ['id'])
        .eq('org_id', orgId)
        .map((list) {
          final records = list.map((m) => MedicalRecord.fromMap(m)).toList();
          records.sort((a, b) => b.date.compareTo(a.date));
          return records.take(limit).toList();
        });
  }

  /// Records with a follow-up date in the next N days.
  Stream<List<MedicalRecord>> watchUpcomingFollowUps({
    required String orgId,
    int withinDays = 14,
  }) {
    final now = DateTime.now();
    final cutoff = now.add(Duration(days: withinDays));
    return _supabase
        .from('medical_records')
        .stream(primaryKey: ['id'])
        .eq('org_id', orgId)
        .map((list) {
          final records = list
              .map((m) => MedicalRecord.fromMap(m))
              .where((r) => r.followUpDate != null &&
                            (r.followUpDate!.isAtSameMomentAs(now) || r.followUpDate!.isAfter(now)) &&
                            (r.followUpDate!.isAtSameMomentAs(cutoff) || r.followUpDate!.isBefore(cutoff)))
              .toList();
          records.sort((a, b) => a.followUpDate!.compareTo(b.followUpDate!));
          return records;
        });
  }
}
