import 'package:supabase_flutter/supabase_flutter.dart';

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

  factory AnimalOption.fromMap(Map<String, dynamic> data) {
    return AnimalOption(
      id: data['id'] as String? ?? '',
      tagNumber: data['tag_number'] as String? ?? data['tagNumber'] as String? ?? '',
      breed: data['breed'] as String? ?? '',
      name: data['name'] as String?,
      lactationStatus: data['lactation_status'] as String? ?? data['lactationStatus'] as String? ?? '',
    );
  }
}

class AnimalService {
  final SupabaseClient _supabase;
  AnimalService({SupabaseClient? client}) : _supabase = client ?? Supabase.instance.client;

  /// All animals in the org, for general pickers (breeding, health, feed).
  Stream<List<AnimalOption>> watchAnimals(String orgId) {
    return _supabase
        .from('animals')
        .stream(primaryKey: ['id'])
        .eq('org_id', orgId)
        .order('tag_number')
        .map((list) => list.map((m) => AnimalOption.fromMap(m)).toList());
  }

  Stream<List<AnimalOption>> watchLactatingAnimals(String orgId) {
    return _supabase
        .from('animals')
        .stream(primaryKey: ['id'])
        .eq('org_id', orgId)
        .map((list) {
          final options = list
              .map((m) => AnimalOption.fromMap(m))
              .where((a) => a.lactationStatus == 'Lactating')
              .toList();
          options.sort((a, b) => a.tagNumber.compareTo(b.tagNumber));
          return options;
        });
  }
}
