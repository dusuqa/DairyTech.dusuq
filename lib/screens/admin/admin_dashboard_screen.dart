import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:dusuq/models/organization.dart';
import 'package:dusuq/providers/auth_providers.dart';

/// Admin Dashboard — reachable ONLY by SuperAdmin and OrgAdmin (enforced in
/// app_router.dart's redirect logic).
///
/// Every number on this screen comes from `dashboardOrganizationProvider`,
/// which reads ONE Firestore document (or, for SuperAdmin, combines a
/// handful of org documents client-side) — never a live SUM over
/// operational records. See functions/index.js for the Cloud Functions
/// that keep that document's `aggregates` map current as farmers log data.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final orgAsync = ref.watch(dashboardOrganizationProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(profile?.isSuperAdmin == true
            ? 'DUSUQ — All Organizations'
            : 'DUSUQ — Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: 'Manage farmers',
            onPressed: () => context.go('/admin/users'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: orgAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorState(message: err.toString()),
        data: (org) {
          if (org == null) {
            return const _EmptyState();
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (org.lastUpdated != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Last updated ${_relativeTime(org.lastUpdated!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  _MetricCard(
                    label: 'Total Animals',
                    value: org.animalCount.toString(),
                    icon: Icons.pets_outlined,
                    color: Colors.green,
                  ),
                  _MetricCard(
                    label: 'Lactating Now',
                    value: org.lactatingCount.toString(),
                    icon: Icons.water_drop_outlined,
                    color: Colors.blue,
                  ),
                  _MetricCard(
                    label: 'Milk This Month (L)',
                    value: _formatNumber(org.milkThisMonth),
                    icon: Icons.opacity_outlined,
                    color: Colors.teal,
                    trend: org.milkMonthOverMonthPct,
                  ),
                  _MetricCard(
                    label: 'Active Farmers',
                    value: org.activeFarmerCount.toString(),
                    icon: Icons.groups_outlined,
                    color: Colors.purple,
                  ),
                  _MetricCard(
                    label: 'Income (PKR)',
                    value: _formatCurrency(org.totalIncome),
                    icon: Icons.trending_up,
                    color: Colors.green,
                  ),
                  _MetricCard(
                    label: 'Expenses (PKR)',
                    value: _formatCurrency(org.totalExpense),
                    icon: Icons.trending_down,
                    color: Colors.red,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _NetRevenueCard(org: org),
              const SizedBox(height: 20),
              if (org.milkByMonth.isNotEmpty) _MilkTrendCard(org: org),
            ],
          );
        },
      ),
    );
  }

  String _formatNumber(double v) => NumberFormat('#,##0.0').format(v);
  String _formatCurrency(double v) => 'Rs ${NumberFormat('#,##0').format(v)}';

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final double? trend; // percentage, null = no trend shown

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.trend,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const Spacer(),
                if (trend != null) _TrendChip(value: trend!),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendChip extends StatelessWidget {
  final double value;
  const _TrendChip({required this.value});

  @override
  Widget build(BuildContext context) {
    final isUp = value >= 0;
    final color = isUp ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isUp ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: color),
          Text(
            '${value.abs().toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _NetRevenueCard extends StatelessWidget {
  final Organization org;
  const _NetRevenueCard({required this.org});

  @override
  Widget build(BuildContext context) {
    final isPositive = org.netRevenue >= 0;
    return Card(
      elevation: 0,
      color: isPositive
          ? Colors.green.withOpacity(0.08)
          : Colors.red.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              isPositive ? Icons.account_balance_wallet_outlined : Icons.warning_amber_outlined,
              color: isPositive ? Colors.green : Colors.red,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Net Revenue', style: TextStyle(color: Colors.grey)),
                  Text(
                    'Rs ${NumberFormat('#,##0').format(org.netRevenue)}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isPositive ? Colors.green.shade800 : Colors.red.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MilkTrendCard extends StatelessWidget {
  final Organization org;
  const _MilkTrendCard({required this.org});

  @override
  Widget build(BuildContext context) {
    final sortedMonths = org.milkByMonth.keys.toList()..sort();
    final last6 = sortedMonths.length > 6
        ? sortedMonths.sublist(sortedMonths.length - 6)
        : sortedMonths;
    final maxVal = last6.fold<double>(
        0, (max, k) => org.milkByMonth[k]! > max ? org.milkByMonth[k]! : max);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Milk Production — Last 6 Months',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: last6.map((month) {
                  final value = org.milkByMonth[month] ?? 0;
                  final heightFraction = maxVal > 0 ? value / maxVal : 0.0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            value >= 1000
                                ? '${(value / 1000).toStringAsFixed(1)}k'
                                : value.toStringAsFixed(0),
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          FractionallySizedBox(
                            heightFactor: heightFraction.clamp(0.02, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.teal,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(month.substring(5), style: const TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bar_chart, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'No data yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Numbers will appear here as your farm logs milk, animals, and expenses.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Couldn\'t load dashboard data',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
