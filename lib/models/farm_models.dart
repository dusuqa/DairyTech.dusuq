// =============================================================================
// DUSUQ - Dairy Farm ERP
// Models: MilkRecord | FeedExpense | BreedingRecord | MedicalRecord
//
// CHANGE FROM ORIGINAL MVP MODELS:
// Every model below gains two fields that didn't exist in the single-tenant
// version: `orgId` (immutable, set once at creation — see firestore.rules)
// and `createdBy` (the uid of whoever logged the entry — lets an OrgAdmin
// see which farmhand entered what, useful for accountability and for the
// finance_records read-scoping rule that restricts Farmers to their own
// entries). Every other field is unchanged from the original models.
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────
// MilkRecord — daily production per animal
// ─────────────────────────────────────────────────────────────────────────
class MilkRecord {
  final String id;
  final String orgId; // NEW — immutable, scopes this record to a tenant
  final String animalId;
  final DateTime date;
  final double quantity; // litres
  final String? session; // "Morning" | "Evening" | "Midday" — optional, additive
  final String createdBy; // NEW — uid of the farmhand who logged this

  const MilkRecord({
    required this.id,
    required this.orgId,
    required this.animalId,
    required this.date,
    required this.quantity,
    this.session,
    required this.createdBy,
  });

  factory MilkRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MilkRecord(
      id: doc.id,
      orgId: data['orgId'] as String? ?? '',
      animalId: data['animalId'] as String,
      date: (data['date'] as Timestamp).toDate(),
      quantity: (data['quantity'] as num).toDouble(),
      session: data['session'] as String?,
      createdBy: data['createdBy'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'orgId': orgId,
        'animalId': animalId,
        'date': Timestamp.fromDate(date),
        'quantity': quantity,
        if (session != null) 'session': session,
        'createdBy': createdBy,
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
//
// `type` stays free-text-backed-by-a-UI-dropdown (not a Dart enum) since,
// unlike BreedingEvent/HealthCategory, nothing in the app branches on feed
// type — it's a label, not a driver of business logic. The dropdown options
// live in the entry screen (see feed_entry_screen.dart) and match the
// Sheets logbook's local terminology (Wanda, Bhoosa, Chokar, etc.).
//
// ADDED vs. original MVP shape: `unit` (the original had a bare `quantity`
// with no unit — meaningless for a dashboard cost-per-unit calc without
// knowing if it's kg, a Maund, or a trolley load) and `supplier` (matches
// the Sheets Feed Log, useful for an OrgAdmin tracking which vendor to
// reorder from).
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

  factory FeedExpense.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FeedExpense(
      id: doc.id,
      orgId: data['orgId'] as String? ?? '',
      type: data['type'] as String,
      cost: (data['cost'] as num).toDouble(),
      quantity: (data['quantity'] as num).toDouble(),
      // Old-shape docs (pre-unit) default to "kg" rather than throwing —
      // approximate but never wrong in a way that crashes the list view.
      unit: data['unit'] as String? ?? 'kg',
      supplier: data['supplier'] as String?,
      date: (data['date'] as Timestamp).toDate(),
      createdBy: data['createdBy'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'orgId': orgId,
        'type': type,
        'cost': cost,
        'quantity': quantity,
        'unit': unit,
        if (supplier != null) 'supplier': supplier,
        'date': Timestamp.fromDate(date),
        'createdBy': createdBy,
      };
}

// ─────────────────────────────────────────────────────────────────────────
// BreedingRecord — EXPANDED workflow (was: pending/confirmed/calved/failed)
//
// The 4-state enum couldn't represent the actual sequence of events a
// farmhand observes: detecting heat, the AI/service event itself, a
// pregnancy check days/weeks later, and finally calving. Collapsing all of
// that into "pending" lost information the Breeding Log (Sheets version)
// already captured. This expands BreedingStatus into BreedingEvent — note
// the rename, since "status" implied a single current state machine, while
// "event" correctly models this as a LOG of discrete things that happened,
// which is what the UI and the rest of the system actually need.
//
// MIGRATION NOTE: any existing BreedingRecord documents using the old
// 4-value enum will fail to parse against BreedingEvent.values.firstWhere
// and fall through to the orElse default (oestrusDetected) — see fromFirestore
// below. If you have real BreedingRecord data already in Firestore under the
// old schema, run a one-time migration script mapping old->new values before
// shipping this (pending->oestrusDetected, confirmed->pregnancyCheckPositive,
// calved->calving, failed->pregnancyCheckNegative) rather than relying on
// the fallback, which would silently misclassify historical records.
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
  final DateTime date; // renamed from breedingDate — this is the event date,
  // not necessarily a breeding date (e.g. a pregnancy check has its own date)
  final BreedingEvent event;
  final String? method; // "Artificial Insemination" | "Natural Mount" | null
  final String? bullSireId;
  final String? technicianName;
  final DateTime? expectedCalvingDate; // auto-computed +280 days when event==aiDone
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

  factory BreedingRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BreedingRecord(
      id: doc.id,
      orgId: data['orgId'] as String? ?? '',
      animalId: data['animalId'] as String,
      date: (data['date'] as Timestamp).toDate(),
      event: BreedingEvent.values.firstWhere(
        (e) => e.name == data['event'],
        // See migration note above — this fallback exists so a malformed
        // or pre-migration doc doesn't crash the app, but it WILL silently
        // misclassify old data. Don't rely on it past the migration window.
        orElse: () => BreedingEvent.oestrusDetected,
      ),
      method: data['method'] as String?,
      bullSireId: data['bullSireId'] as String?,
      technicianName: data['technicianName'] as String?,
      expectedCalvingDate:
          (data['expectedCalvingDate'] as Timestamp?)?.toDate(),
      notes: data['notes'] as String?,
      createdBy: data['createdBy'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'orgId': orgId,
        'animalId': animalId,
        'date': Timestamp.fromDate(date),
        'event': event.name,
        if (method != null) 'method': method,
        if (bullSireId != null) 'bullSireId': bullSireId,
        if (technicianName != null) 'technicianName': technicianName,
        if (expectedCalvingDate != null)
          'expectedCalvingDate': Timestamp.fromDate(expectedCalvingDate!),
        if (notes != null) 'notes': notes,
        'createdBy': createdBy,
      };
}

// ─────────────────────────────────────────────────────────────────────────
// MedicalRecord — EXPANDED to a structured category + medicine/dosage shape
// (was: a single free-text `treatment` string).
//
// Matches the same reasoning as the BreedingRecord expansion: a free-text
// field can't be filtered, charted, or cost-broken-down by the Admin
// Dashboard later (e.g. "total spent on Mastitis treatment this quarter"),
// and farmers benefit from a dropdown over typing the same handful of
// recurring treatment types from scratch every time, especially on a phone
// keyboard in a cowshed. Category list matches the Sheets logbook's
// Health Log vocabulary exactly, so terminology stays consistent across
// the two products.
//
// MIGRATION NOTE: same caveat as BreedingRecord — if real MedicalRecord
// documents already exist under the old `treatment: String` shape, they
// won't parse against HealthCategory.values.firstWhere and will fall
// through to the `other` fallback (see fromFirestore below) with the old
// free-text preserved in `notes` instead of lost. That's a deliberate
// least-harm fallback, not a substitute for a real migration script before
// shipping if production data exists.
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
  fmd, // Foot and Mouth Disease — "Mun Khar" locally
  hemorrhagicSepticemia, // HS
  blackQuarter, // BQ
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
  final String? description; // free-text detail, e.g. "Annual FMD vaccine"
  final String? medicine; // e.g. "Oxytetracycline"
  final String? dosage; // e.g. "10ml IM"
  final String? vetName;
  final double? cost; // PKR — optional, lets the dashboard sum health spend
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

  factory MedicalRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Backward-compat: an old-shape doc has `treatment` (String) but no
    // `category`. Preserve its content in notes rather than dropping it
    // silently — see migration note above.
    final hasOldShape = data.containsKey('treatment') && !data.containsKey('category');

    return MedicalRecord(
      id: doc.id,
      orgId: data['orgId'] as String? ?? '',
      animalId: data['animalId'] as String,
      category: HealthCategory.values.firstWhere(
        (c) => c.name == data['category'],
        orElse: () => HealthCategory.other,
      ),
      description: data['description'] as String?,
      medicine: data['medicine'] as String? ?? (hasOldShape ? data['vaccine'] as String? : null),
      dosage: data['dosage'] as String?,
      vetName: data['vetName'] as String?,
      cost: (data['cost'] as num?)?.toDouble(),
      date: (data['date'] as Timestamp).toDate(),
      followUpDate: (data['followUpDate'] as Timestamp?)?.toDate(),
      notes: hasOldShape
          ? 'Imported from old format: ${data['treatment']}${data['notes'] != null ? ' — ${data['notes']}' : ''}'
          : data['notes'] as String?,
      createdBy: data['createdBy'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'orgId': orgId,
        'animalId': animalId,
        'category': category.name,
        if (description != null) 'description': description,
        if (medicine != null) 'medicine': medicine,
        if (dosage != null) 'dosage': dosage,
        if (vetName != null) 'vetName': vetName,
        if (cost != null) 'cost': cost,
        'date': Timestamp.fromDate(date),
        if (followUpDate != null) 'followUpDate': Timestamp.fromDate(followUpDate!),
        if (notes != null) 'notes': notes,
        'createdBy': createdBy,
      };
}
