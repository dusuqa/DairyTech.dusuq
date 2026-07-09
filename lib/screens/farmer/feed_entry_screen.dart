import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dusuq/models/farm_models.dart';
import 'package:dusuq/providers/auth_providers.dart';

/// Feed entry screen — reached from the farmer field view's "Feed Log"
/// tile. Unlike Milk/Breeding/Health, feed purchases are farm-wide rather
/// than per-animal (matches the original MVP's FeedExpense shape, which
/// has no animalId), so there's no animal picker here — just what was
/// bought, how much, and the cost.
///
/// Cost auto-calculates from quantity × rate when both are entered, but
/// stays editable — a farmhand who only knows the total receipt amount
/// (common when buying from a local supplier without itemized pricing)
/// can type that directly instead.
class FeedEntryScreen extends ConsumerStatefulWidget {
  const FeedEntryScreen({super.key});

  @override
  ConsumerState<FeedEntryScreen> createState() => _FeedEntryScreenState();
}

class _FeedEntryScreenState extends ConsumerState<FeedEntryScreen> {
  static const _feedTypes = [
    'Wanda (Concentrate)',
    'Silage',
    'Hay / Bhoosa',
    'Green Fodder',
    'Cotton Seed Cake',
    'Maize',
    'Wheat Bran (Chokar)',
    'Molasses (Rub/Shira)',
    'Mineral Mix',
    'Salt Lick',
    'TMR (Total Mixed Ration)',
    'Other',
  ];
  static const _units = ['kg', 'Maund (40kg)', 'Bori (50kg)', 'Trolley', 'Litres'];

  String _type = _feedTypes.first;
  String _unit = _units.first;
  final _quantityCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();
  bool _costManuallyEdited = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _quantityCtrl.addListener(_recalculateCost);
    _rateCtrl.addListener(_recalculateCost);
  }

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _rateCtrl.dispose();
    _costCtrl.dispose();
    _supplierCtrl.dispose();
    super.dispose();
  }

  void _recalculateCost() {
    if (_costManuallyEdited) return;
    final qty = double.tryParse(_quantityCtrl.text.trim());
    final rate = double.tryParse(_rateCtrl.text.trim());
    if (qty != null && rate != null) {
      _costCtrl.text = (qty * rate).toStringAsFixed(0);
    }
  }

  Future<void> _submit() async {
    final profile = ref.read(userProfileProvider).valueOrNull;
    if (profile == null || profile.orgId.isEmpty) return;

    final qty = double.tryParse(_quantityCtrl.text.trim());
    final cost = double.tryParse(_costCtrl.text.trim());
    if (qty == null || qty <= 0) {
      _showSnack('Enter a valid quantity.');
      return;
    }
    if (cost == null || cost <= 0) {
      _showSnack('Enter the total cost (or quantity + rate to auto-calculate).');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(feedServiceProvider).addRecord(
            orgId: profile.orgId,
            type: _type,
            cost: cost,
            quantity: qty,
            unit: _unit,
            supplier:
                _supplierCtrl.text.trim().isEmpty ? null : _supplierCtrl.text.trim(),
            date: DateTime.now(),
            createdBy: profile.uid,
          );
      setState(() {
        _quantityCtrl.clear();
        _rateCtrl.clear();
        _costCtrl.clear();
        _supplierCtrl.clear();
        _costManuallyEdited = false;
      });
      if (mounted) _showSnack('Saved ✓', success: true);
    } catch (e) {
      _showSnack('Could not save. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String message, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green.shade700 : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final theme = Theme.of(context);

    if (profile == null || profile.orgId.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final todayAsync = ref.watch(_todayFeedProvider(profile.orgId));

    return Scaffold(
      appBar: AppBar(title: const Text('Feed Log')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Log Feed Purchase', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Feed Type',
                      prefixIcon: Icon(Icons.grass_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: _feedTypes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _quantityCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Quantity',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: _unit,
                          decoration: const InputDecoration(
                            labelText: 'Unit',
                            border: OutlineInputBorder(),
                          ),
                          items: _units
                              .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                              .toList(),
                          onChanged: (v) => setState(() => _unit = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Rate per unit (PKR, optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _costCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'Total Cost (PKR)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _costManuallyEdited = true,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _supplierCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Supplier (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save Entry'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Logged Today', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          todayAsync.when(
            loading: () => const Center(
              child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Could not load today\'s entries: $e'),
            data: (records) {
              if (records.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No feed purchases logged yet today.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                );
              }
              final totalCost = records.fold<double>(0, (s, r) => s + r.cost);
              return Column(
                children: [
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.tertiaryContainer.withOpacity(0.4),
                    child: ListTile(
                      title: const Text('Today\'s Total Spend'),
                      trailing: Text(
                        'Rs ${NumberFormat('#,##0').format(totalCost)}',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...records.map((r) => Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: theme.colorScheme.outlineVariant),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.grass_outlined),
                          title: Text('${r.type} — ${r.quantity} ${r.unit}'),
                          subtitle: Text(
                            'Rs ${NumberFormat('#,##0').format(r.cost)}'
                            '${r.supplier != null ? ' • ${r.supplier}' : ''}',
                          ),
                          dense: true,
                        ),
                      )),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

final _todayFeedProvider =
    StreamProvider.family<List<FeedExpense>, String>((ref, orgId) {
  return ref.watch(feedServiceProvider).watchToday(orgId);
});
