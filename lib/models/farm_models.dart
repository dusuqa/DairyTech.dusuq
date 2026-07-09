// =============================================================================
// DUSUQ - Dairy Farm ERP
// Models: MilkRecord | FeedExpense | BreedingRecord | MedicalRecord
// =============================================================================

// ─────────────────────────────────────────────────────────────────────────
// MilkRecord — daily production per animal
// ─────────────────────────────────────────────────────────────────────────
class MilkRecord {
  final String id;
  final String orgId;
  final String animalId;
  final DateTime date;
  final double quantity; // litres
  final String? session; // "Morning" | "Evening" | "Midday"
  final String createdBy;

  const MilkRecord({
    required this.id,
    required this.orgId,
    required this.animalId,
    required this.date,
    required this.quantity,
    this.session,
    required this.createdBy,
  });

  factory MilkRecord.fromMap(Map<String, dynamic> data) {
    return MilkRecord(
      id: data['id'] as String? ?? '',
      orgId: data['org_id'] as String? ?? data['orgId'] as String? ?? '',
      animalId: data['animal_id'] as String? ?? data['animalId'] as String? ?? '',
      date: DateTime.parse(data['date'] as String).toLocal(),
      quantity: (data['quantity'] as num).toDouble(),
      session: data['session'] as String?,
      createdBy: data['created_by'] as String? ?? data['createdBy'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'org_id': orgId,
        'animal_id': animalId,
        'date': date.toUtc().toIso8601String(),
        'quantity': quantity,
        if (session != null) 'session': session,
        'created_by': createdBy,
      };

  MilkRecord copyWith({
    String? id,
    String? orgId,
    String? animalId,
    DateTime? date,
    double? quantity,
    String? session,
    String? createdBy,
  }) =>
      MilkRecord(
        id: id ?? this.id,
        orgId: orgId ?? this.orgId,
        animalId: animalId ?? this.animalId,
        date: date ?? this.date,
        quantity: quantity ?? this.quantity,
        session: session ?? this.session,
        createdBy: createdBy ?? this.createdBy,
      );
}

// ─────────────────────────────────────────────────────────────────────────
// FeedExpense — feed purchases and costs.
// ─────────────────────────────────────────────────────────────────────────
class FeedExpense {
  final String id;
  final String orgId;
  final String type; // "Wanda (Concentrate)", "Hay / Bhoosa", "Silage", etc.
  final double cost; // total cost in PKR, not cost-per-unit
  final double quantity;
  final String unit; // "kg" | "Maund (40kg)" | "Bori (50kg)" | "Trolley" | "Litres"
  final String? supplier;
  final DateTime date;
  final String createdBy;

  const FeedExpense({
    required this.id,
    required this.orgId,
    required this.type,
    required this.cost,
    required this.quantity,
    required this.unit,
    this.supplier,
    required this.date,
    required this.createdBy,
  });

  factory FeedExpense.fromMap(Map<String, dynamic> data) {
    return FeedExpense(
      id: data['id'] as String? ?? '',
      orgId: data['org_id'] as String? ?? data['orgId'] as String? ?? '',
      type: data['type'] as String? ?? '',
      cost: (data['cost'] as num).toDouble(),
      quantity: (data['quantity'] as num).toDouble(),
      unit: data['unit'] as String? ?? 'kg',
      supplier: data['supplier'] as String?,
      date: DateTime.parse(data['date'] as String).toLocal(),
      createdBy: data['created_by'] as String? ?? data['createdBy'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'org_id': orgId,
        'type': type,
        'cost': cost,
        'quantity': quantity,
        'unit': unit,
        if (supplier != null) 'supplier': supplier,
        'date': date.toUtc().toIso8601String(),
        'created_by': createdBy,
      };
}

// ─────────────────────────────────────────────────────────────────────────
// BreedingRecord — EXPANDED workflow
// ─────────────────────────────────────────────────────────────────────────
enum BreedingEvent {
  oestrusDetected,
  aiDone,
  naturalService,
  pregnancyCheckPositive,
  pregnancyCheckNegative,
  calving,
  abortion,
  dryOff,
  repeatBreeder,
}

String breedingEventLabel(BreedingEvent e) {
  switch (e) {
    case BreedingEvent.oestrusDetected:
      return 'Oestrus Detected';
    case BreedingEvent.aiDone:
      return 'AI Done';
    case BreedingEvent.naturalService:
      return 'Natural Service';
    case BreedingEvent.pregnancyCheckPositive:
      return 'Pregnancy Check (+)';
    case BreedingEvent.pregnancyCheckNegative:
      return 'Pregnancy Check (−)';
    case BreedingEvent.calving:
      return 'Calving';
    case BreedingEvent.abortion:
      return 'Abortion';
    case BreedingEvent.dryOff:
      return 'Dry-Off';
    case BreedingEvent.repeatBreeder:
      return 'Repeat Breeder';
  }
}

class BreedingRecord {
  final String id;
  final String orgId;
  final String animalId;
  final DateTime date;
  final BreedingEvent event;
  final String? method; // "Artificial Insemination" | "Natural Mount"
  final String? bullSireId;
  final String? technicianName;
  final DateTime? expectedCalvingDate;
  final String? notes;
  final String createdBy;

  const BreedingRecord({
    required this.id,
    required this.orgId,
    required this.animalId,
    required this.date,
    required this.event,
    this.method,
    this.bullSireId,
    this.technicianName,
    this.expectedCalvingDate,
    this.notes,
    required this.createdBy,
  });

  factory BreedingRecord.fromMap(Map<String, dynamic> data) {
    return BreedingRecord(
      id: data['id'] as String? ?? '',
      orgId: data['org_id'] as String? ?? data['orgId'] as String? ?? '',
      animalId: data['animal_id'] as String? ?? data['animalId'] as String? ?? '',
      date: DateTime.parse(data['date'] as String).toLocal(),
      event: BreedingEvent.values.firstWhere(
        (e) => e.name == data['event'],
        orElse: () => BreedingEvent.oestrusDetected,
      ),
      method: data['method'] as String?,
      bullSireId: data['bull_sire_id'] as String? ?? data['bullSireId'] as String?,
      technicianName: data['technician_name'] as String? ?? data['technicianName'] as String?,
      expectedCalvingDate: data['expected_calving_date'] != null
          ? DateTime.parse(data['expected_calving_date'] as String).toLocal()
          : data['expectedCalvingDate'] != null
              ? DateTime.parse(data['expectedCalvingDate'] as String).toLocal()
              : null,
      notes: data['notes'] as String?,
      createdBy: data['created_by'] as String? ?? data['createdBy'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'org_id': orgId,
        'animal_id': animalId,
        'date': date.toUtc().toIso8601String(),
        'event': event.name,
        if (method != null) 'method': method,
        if (bullSireId != null) 'bull_sire_id': bullSireId,
        if (technicianName != null) 'technician_name': technicianName,
        if (expectedCalvingDate != null)
          'expected_calving_date': expectedCalvingDate!.toUtc().toIso8601String(),
        if (notes != null) 'notes': notes,
        'created_by': createdBy,
      };
}

// ─────────────────────────────────────────────────────────────────────────
// MedicalRecord — EXPANDED
// ─────────────────────────────────────────────────────────────────────────
enum HealthCategory {
  vaccination,
  deworming,
  mastitisTreatment,
  footRot,
  bloatTympany,
  diarrhoea,
  fever,
  injury,
  surgery,
  tickTreatment,
  fmd,
  hemorrhagicSepticemia,
  blackQuarter,
  routineCheckup,
  other,
}

String healthCategoryLabel(HealthCategory c) {
  switch (c) {
    case HealthCategory.vaccination:
      return 'Vaccination';
    case HealthCategory.deworming:
      return 'Deworming';
    case HealthCategory.mastitisTreatment:
      return 'Mastitis Treatment';
    case HealthCategory.footRot:
      return 'Foot Rot';
    case HealthCategory.bloatTympany:
      return 'Bloat / Tympany';
    case HealthCategory.diarrhoea:
      return 'Diarrhoea';
    case HealthCategory.fever:
      return 'Fever';
    case HealthCategory.injury:
      return 'Injury';
    case HealthCategory.surgery:
      return 'Surgery';
    case HealthCategory.tickTreatment:
      return 'Tick Treatment';
    case HealthCategory.fmd:
      return 'FMD (Mun Khar)';
    case HealthCategory.hemorrhagicSepticemia:
      return 'Hemorrhagic Septicemia (HS)';
    case HealthCategory.blackQuarter:
      return 'Black Quarter (BQ)';
    case HealthCategory.routineCheckup:
      return 'Routine Checkup';
    case HealthCategory.other:
      return 'Other';
  }
}

class MedicalRecord {
  final String id;
  final String orgId;
  final String animalId;
  final HealthCategory category;
  final String? description;
  final String? medicine;
  final String? dosage;
  final String? vetName;
  final double? cost;
  final DateTime date;
  final DateTime? followUpDate;
  final String? notes;
  final String createdBy;

  const MedicalRecord({
    required this.id,
    required this.orgId,
    required this.animalId,
    required this.category,
    this.description,
    this.medicine,
    this.dosage,
    this.vetName,
    this.cost,
    required this.date,
    this.followUpDate,
    this.notes,
    required this.createdBy,
  });

  factory MedicalRecord.fromMap(Map<String, dynamic> data) {
    return MedicalRecord(
      id: data['id'] as String? ?? '',
      orgId: data['org_id'] as String? ?? data['orgId'] as String? ?? '',
      animalId: data['animal_id'] as String? ?? data['animalId'] as String? ?? '',
      category: HealthCategory.values.firstWhere(
        (c) => c.name == data['category'],
        orElse: () => HealthCategory.other,
      ),
      description: data['description'] as String?,
      medicine: data['medicine'] as String?,
      dosage: data['dosage'] as String?,
      vetName: data['vet_name'] as String? ?? data['vetName'] as String?,
      cost: (data['cost'] as num?)?.toDouble(),
      date: DateTime.parse(data['date'] as String).toLocal(),
      followUpDate: data['follow_up_date'] != null
          ? DateTime.parse(data['follow_up_date'] as String).toLocal()
          : data['followUpDate'] != null
              ? DateTime.parse(data['followUpDate'] as String).toLocal()
              : null,
      notes: data['notes'] as String?,
      createdBy: data['created_by'] as String? ?? data['createdBy'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'org_id': orgId,
        'animal_id': animalId,
        'category': category.name,
        if (description != null) 'description': description,
        if (medicine != null) 'medicine': medicine,
        if (dosage != null) 'dosage': dosage,
        if (vetName != null) 'vet_name': vetName,
        if (cost != null) 'cost': cost,
        'date': date.toUtc().toIso8601String(),
        if (followUpDate != null) 'follow_up_date': followUpDate!.toUtc().toIso8601String(),
        if (notes != null) 'notes': notes,
        'created_by': createdBy,
      };
}
