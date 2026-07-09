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

  double? get milkMonthOverMonthPct {
    if (milkLastMonth <= 0) return null;
    return ((milkThisMonth - milkLastMonth) / milkLastMonth) * 100;
  }

  factory Organization.fromMap(Map<String, dynamic> data) {
    final milkByMonthRaw = (data['milk_by_month'] as Map<String, dynamic>?) ?? {};
    return Organization(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? '(unnamed)',
      planTier: data['plan_tier'] as String? ?? data['planTier'] as String? ?? 'trial',
      status: data['status'] as String? ?? 'active',
      animalCount: (data['animal_count'] as num? ?? data['animalCount'] as num?)?.toInt() ?? 0,
      lactatingCount: (data['lactating_count'] as num? ?? data['lactatingCount'] as num?)?.toInt() ?? 0,
      activeFarmerCount: (data['active_farmer_count'] as num? ?? data['activeFarmerCount'] as num?)?.toInt() ?? 0,
      totalMilkLiters: (data['total_milk_liters'] as num? ?? data['totalMilkLiters'] as num?)?.toDouble() ?? 0,
      totalIncome: (data['total_income'] as num? ?? data['totalIncome'] as num?)?.toDouble() ?? 0,
      totalExpense: (data['total_expense'] as num? ?? data['totalExpense'] as num?)?.toDouble() ?? 0,
      netRevenue: (data['net_revenue'] as num? ?? data['netRevenue'] as num?)?.toDouble() ?? 0,
      milkByMonth: milkByMonthRaw.map((k, v) => MapEntry(k, (v as num).toDouble())),
      lastUpdated: data['last_updated'] != null
          ? DateTime.tryParse(data['last_updated'] as String)
          : data['lastUpdated'] != null
              ? DateTime.tryParse(data['lastUpdated'] as String)
              : null,
    );
  }

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
