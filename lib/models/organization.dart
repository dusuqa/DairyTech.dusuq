import 'package:cloud_firestore/cloud_firestore.dart';

/// Mirrors `organizations/{orgId}`, including the `aggregates` map that the
/// Cloud Functions in functions/index.js maintain incrementally
/// (onMilkRecordWrite, onFinanceRecordWrite, onAnimalWrite,
/// onUserWriteUpdateFarmerCount). The Admin Dashboard reads ONE document —
/// this one — instead of summing potentially thousands of operational
/// records on every page load.
class Organization {
  final String id;
  final String name;
  final String planTier;
  final String status;
  final int animalCount;
  final int lactatingCount;
  final int activeFarmerCount;
  final double totalMilkLiters;
  final double totalIncome;
  final double totalExpense;
  final double netRevenue;
  final Map<String, double> milkByMonth; // "2026-06" -> 1840.5
  final DateTime? lastUpdated;

  const Organization({
    required this.id,
    required this.name,
    required this.planTier,
    required this.status,
    required this.animalCount,
    required this.lactatingCount,
    required this.activeFarmerCount,
    required this.totalMilkLiters,
    required this.totalIncome,
    required this.totalExpense,
    required this.netRevenue,
    required this.milkByMonth,
    this.lastUpdated,
  });

  /// Milk total for the current calendar month, derived from the
  /// month-keyed map so the dashboard can show "this month" without a
  /// separate query or a separate counter to maintain.
  double get milkThisMonth {
    final now = DateTime.now();
    final key = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    return milkByMonth[key] ?? 0;
  }

  double get milkLastMonth {
    final now = DateTime.now();
    final lastMonthDate = DateTime(now.year, now.month - 1, 1);
    final key =
        '${lastMonthDate.year}-${lastMonthDate.month.toString().padLeft(2, '0')}';
    return milkByMonth[key] ?? 0;
  }

  /// Percentage change month-over-month, null if no prior-month data exists
  /// yet (avoids showing a misleading "+100%" or divide-by-zero on a
  /// brand-new org's first month).
  double? get milkMonthOverMonthPct {
    if (milkLastMonth <= 0) return null;
    return ((milkThisMonth - milkLastMonth) / milkLastMonth) * 100;
  }

  factory Organization.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final agg = (data['aggregates'] as Map<String, dynamic>?) ?? {};
    final milkByMonthRaw = (agg['milkByMonth'] as Map<String, dynamic>?) ?? {};

    return Organization(
      id: doc.id,
      name: data['name'] as String? ?? '(unnamed)',
      planTier: data['planTier'] as String? ?? 'trial',
      status: data['status'] as String? ?? 'active',
      animalCount: (data['animalCount'] as num?)?.toInt() ?? 0,
      lactatingCount: (agg['lactatingCount'] as num?)?.toInt() ?? 0,
      activeFarmerCount: (agg['activeFarmerCount'] as num?)?.toInt() ?? 0,
      totalMilkLiters: (agg['totalMilkLiters'] as num?)?.toDouble() ?? 0,
      totalIncome: (agg['totalIncome'] as num?)?.toDouble() ?? 0,
      totalExpense: (agg['totalExpense'] as num?)?.toDouble() ?? 0,
      netRevenue: (agg['netRevenue'] as num?)?.toDouble() ?? 0,
      milkByMonth: milkByMonthRaw.map((k, v) => MapEntry(k, (v as num).toDouble())),
      lastUpdated: (agg['lastUpdated'] as Timestamp?)?.toDate(),
    );
  }

  /// Combines multiple Organization snapshots into one synthetic aggregate —
  /// used only by SuperAdmin's "all organizations" view. This IS a live
  /// client-side sum, but over N organization documents (dozens, not
  /// thousands of operational records), so it stays cheap. See the comment
  /// in functions/index.js explaining why this one case is deliberately
  /// NOT pre-aggregated server-side.
  static Organization combine(List<Organization> orgs) {
    final combinedMilkByMonth = <String, double>{};
    for (final org in orgs) {
      for (final entry in org.milkByMonth.entries) {
        combinedMilkByMonth[entry.key] =
            (combinedMilkByMonth[entry.key] ?? 0) + entry.value;
      }
    }
    return Organization(
      id: '__all__',
      name: 'All Organizations',
      planTier: '',
      status: '',
      animalCount: orgs.fold(0, (sum, o) => sum + o.animalCount),
      lactatingCount: orgs.fold(0, (sum, o) => sum + o.lactatingCount),
      activeFarmerCount: orgs.fold(0, (sum, o) => sum + o.activeFarmerCount),
      totalMilkLiters: orgs.fold(0.0, (sum, o) => sum + o.totalMilkLiters),
      totalIncome: orgs.fold(0.0, (sum, o) => sum + o.totalIncome),
      totalExpense: orgs.fold(0.0, (sum, o) => sum + o.totalExpense),
      netRevenue: orgs.fold(0.0, (sum, o) => sum + o.netRevenue),
      milkByMonth: combinedMilkByMonth,
    );
  }
}
