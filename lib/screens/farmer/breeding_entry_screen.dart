import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dusuq/models/farm_models.dart';
import 'package:dusuq/providers/auth_providers.dart';
import 'package:dusuq/services/animal_service.dart';

/// Breeding / Heat entry screen — reached from the farmer field view's
/// "Heat / Breeding" tile. Covers the full event vocabulary (oestrus, AI,
/// pregnancy checks, calving) instead of a single status field, matching
/// the expanded BreedingEvent enum. Expected calving date is computed
/// automatically by BreedingService when the event is AI/natural service —
/// the farmer never has to do that math.
class BreedingEntryScreen extends ConsumerStatefulWidget {
  const BreedingEntryScreen({super.key});

  @override
  ConsumerState<BreedingEntryScreen> createState() => _BreedingEntryScreenState();
}

class _BreedingEntryScreenState extends ConsumerState<BreedingEntryScreen> {
  AnimalOption? _selectedAnimal;
  BreedingEvent _event = BreedingEvent.oestrusDetected;
  DateTime _date = DateTime.now();
  final _sireCtrl = TextEditingController();
  final _techCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _sireCtrl.dispose();
    _techCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _needsSireAndMethod =>
      _event == BreedingEvent.aiDone || _event == BreedingEvent.naturalService;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    final profile = ref.read(userProfileProvider).valueOrNull;
    if (profile == null || profile.orgId.isEmpty) return;

    if (_selectedAnimal == null) {
      _showSnack('Select an animal first.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(breedingServiceProvider).addRecord(
            orgId: profile.orgId,
            animalId: _selectedAnimal!.id,
            date: _date,
            event: _event,
            method: _needsSireAndMethod
                ? (_event == BreedingEvent.aiDone
                    ? 'Artificial Insemination'
                    : 'Natural Mount')
                : null,
            bullSireId: _sireCtrl.text.trim().isEmpty ? null : _sireCtrl.text.trim(),
            technicianName: _techCtrl.text.trim().isEmpty ? null : _techCtrl.text.trim(),
            notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            createdBy: profile.uid,
          );
      setState(() {
        _selectedAnimal = null;
        _event = BreedingEvent.oestrusDetected;
        _date = DateTime.now();
        _sireCtrl.clear();
        _techCtrl.clear();
        _notesCtrl.clear();
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

    final animalsAsync = ref.watch(_allAnimalsProvider(profile.orgId));
    final recentAsync = ref.watch(_recentBreedingProvider(profile.orgId));

    return Scaffold(
      appBar: AppBar(title: const Text('Heat / Breeding')),
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
                  Text('Log Breeding Event', style: theme.textTheme.titleMedium),
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
                  DropdownButtonFormField<BreedingEvent>(
                    value: _event,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Event',
                      prefixIcon: Icon(Icons.favorite_outline),
                      border: OutlineInputBorder(),
                    ),
                    items: BreedingEvent.values
                        .map((e) => DropdownMenuItem(
                              value: e,
                              child: Text(breedingEventLabel(e)),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _event = v!),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                        border: OutlineInputBorder(),
                      ),
                      child: Text(DateFormat('dd MMM yyyy').format(_date)),
                    ),
                  ),
                  if (_needsSireAndMethod) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _sireCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Bull / Sire ID (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _techCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Technician (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_event == BreedingEvent.aiDone) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiaryContainer.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Expected calving: ${DateFormat('dd MMM yyyy').format(_date.add(const Duration(days: 280)))} (auto-calculated)',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
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
          Text('Recent Events', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          recentAsync.when(
            loading: () => const Center(
              child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Could not load recent events: $e'),
            data: (records) {
              if (records.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No breeding events logged yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                );
              }
              return Column(
                children: records
                    .map((r) => Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.favorite_outline),
                            title: Text(breedingEventLabel(r.event)),
                            subtitle: Text(
                              '${DateFormat('dd MMM yyyy').format(r.date)}'
                              '${r.expectedCalvingDate != null ? ' • Expected: ${DateFormat('dd MMM').format(r.expectedCalvingDate!)}' : ''}',
                            ),
                            dense: true,
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

final _allAnimalsProvider =
    StreamProvider.family<List<AnimalOption>, String>((ref, orgId) {
  return ref.watch(animalServiceProvider).watchAnimals(orgId);
});

final _recentBreedingProvider =
    StreamProvider.family<List<BreedingRecord>, String>((ref, orgId) {
  return ref.watch(breedingServiceProvider).watchRecent(orgId: orgId);
});
