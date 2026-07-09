import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dusuq/models/farm_models.dart';
import 'package:dusuq/providers/auth_providers.dart';
import 'package:dusuq/services/animal_service.dart';

/// Milk entry screen — reached from the farmer field view's "Milk Yield"
/// tile. Built for someone standing in a cowshed: large tap targets,
/// number-pad keyboard, animal picker filtered to lactating animals only,
/// and today's already-logged entries shown right below the form so a
/// farmhand can see at a glance what's still missing without leaving the
/// screen.
class MilkEntryScreen extends ConsumerStatefulWidget {
  const MilkEntryScreen({super.key});

  @override
  ConsumerState<MilkEntryScreen> createState() => _MilkEntryScreenState();
}

class _MilkEntryScreenState extends ConsumerState<MilkEntryScreen> {
  AnimalOption? _selectedAnimal;
  String _session = 'Morning';
  final _quantityCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _quantityCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final profile = ref.read(userProfileProvider).valueOrNull;
    if (profile == null || profile.orgId.isEmpty) return;

    if (_selectedAnimal == null) {
      _showSnack('Select an animal first.');
      return;
    }
    final qty = double.tryParse(_quantityCtrl.text.trim());
    if (qty == null || qty <= 0) {
      _showSnack('Enter a valid quantity in litres.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(milkServiceProvider).addRecord(
            orgId: profile.orgId,
            animalId: _selectedAnimal!.id,
            date: DateTime.now(),
            quantity: qty,
            session: _session,
            createdBy: profile.uid,
          );
      _quantityCtrl.clear();
      setState(() => _selectedAnimal = null);
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

    final animalsAsync =
        ref.watch(_lactatingAnimalsProvider(profile.orgId));
    final todayAsync = ref.watch(_todayMilkProvider(profile.orgId));

    return Scaffold(
      appBar: AppBar(title: const Text('Milk Yield')),
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
                  Text('Log Milking', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 16),
                  animalsAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Could not load animals: $e'),
                    data: (animals) => DropdownButtonFormField<AnimalOption>(
                      value: _selectedAnimal,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Animal',
                        prefixIcon: Icon(Icons.pets_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: animals
                          .map((a) => DropdownMenuItem(value: a, child: Text(a.label)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedAnimal = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Morning', label: Text('Morning')),
                      ButtonSegment(value: 'Evening', label: Text('Evening')),
                      ButtonSegment(value: 'Midday', label: Text('Midday')),
                    ],
                    selected: {_session},
                    onSelectionChanged: (s) => setState(() => _session = s.first),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _quantityCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'Quantity (Litres)',
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
            loading: () => const Center(child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )),
            error: (e, _) => Text('Could not load today\'s entries: $e'),
            data: (records) {
              if (records.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No milk logged yet today.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                );
              }
              final total = records.fold<double>(0, (s, r) => s + r.quantity);
              return Column(
                children: [
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.primaryContainer.withOpacity(0.4),
                    child: ListTile(
                      title: const Text('Today\'s Total'),
                      trailing: Text(
                        '${total.toStringAsFixed(1)} L',
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
                          leading: const Icon(Icons.water_drop_outlined),
                          title: Text('${r.quantity} L — ${r.session ?? ''}'),
                          subtitle: Text(DateFormat('h:mm a').format(r.date)),
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

final _lactatingAnimalsProvider =
    StreamProvider.family<List<AnimalOption>, String>((ref, orgId) {
  return ref.watch(animalServiceProvider).watchLactatingAnimals(orgId);
});

final _todayMilkProvider =
    StreamProvider.family<List<MilkRecord>, String>((ref, orgId) {
  return ref.watch(milkServiceProvider).watchToday(orgId);
});
