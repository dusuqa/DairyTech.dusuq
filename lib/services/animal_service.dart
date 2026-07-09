// =============================================================================
// DUSUQ - Dairy Farm ERP
// Service: AnimalService (minimal slice)
//
// This is NOT a full replacement of the original animal_service.dart (which
// per the earlier build has full CRUD, watchAllAnimals(), health/lactation
// quick-updates, and getAnimalStats()). This file adds only what the Milk
// and Breeding entry screens need: a lightweight, org-scoped stream of
// animal tag/id pairs for a dropdown picker. When you wire the Feed Log and
// Health Log tiles next, extend THIS class rather than re-duplicating it —
// and merge it with the original animal_service.dart's CRUD methods (adding
// the same orgId scoping pattern used in MilkService/BreedingService above)
// rather than maintaining two separate Animal services.
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class AnimalOption {
  final String id;
  final String tagNumber;
  final String breed;
  final String? name;
  final String lactationStatus;

  const AnimalOption({
    required this.id,
    required this.tagNumber,
    required this.breed,
    this.name,
    required this.lactationStatus,
  });

  String get label => name != null && name!.isNotEmpty
      ? '$tagNumber — $name'
      : '$tagNumber ($breed)';

  factory AnimalOption.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AnimalOption(
      id: doc.id,
      tagNumber: data['tagNumber'] as String? ?? doc.id,
      breed: data['breed'] as String? ?? '',
      name: data['name'] as String?,
      lactationStatus: data['lactationStatus'] as String? ?? '',
    );
  }
}

class AnimalService {
  final FirebaseFirestore _db;
  AnimalService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  /// All animals in the org, for general pickers (breeding, health, feed).
  Stream<List<AnimalOption>> watchAnimals(String orgId) {
    return _db
        .collection('animals')
        .where('orgId', isEqualTo: orgId)
        .orderBy('tagNumber')
        .snapshots()
        .map((snap) => snap.docs.map((d) => AnimalOption.fromFirestore(d)).toList());
  }

  /// Lactating animals only — the relevant subset for the Milk entry
  /// picker, since logging milk for a dry/calf animal is almost always a
  /// data-entry mistake the UI should make harder to make, not easier.
  Stream<List<AnimalOption>> watchLactatingAnimals(String orgId) {
    return _db
        .collection('animals')
        .where('orgId', isEqualTo: orgId)
        .where('lactationStatus', isEqualTo: 'Lactating')
        .orderBy('tagNumber')
        .snapshots()
        .map((snap) => snap.docs.map((d) => AnimalOption.fromFirestore(d)).toList());
  }
}
