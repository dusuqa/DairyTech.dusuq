import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dusuq/models/farm_models.dart';
import 'package:dusuq/providers/auth_providers.dart';
import 'package:dusuq/services/animal_service.dart';

/// Health entry screen — reached from the farmer field view's "Animal
/// Health" tile. Per-animal, structured by HealthCategory (Vaccination,
/// Deworming, Mastitis, FMD, etc.) rather than free text, matching the
/// same reasoning as the BreedingEvent expansion: filterable, chartable,
/// and faster to enter from a phone keyboard than typing the same
/// recurring treatment names from scratch.
class HealthEntryScreen extends ConsumerStatefulWidget {
  const HealthEntryScreen({super.key});

  @override
  ConsumerState<HealthEntryScreen> createState() => _HealthEntryScreenState();
}

class _HealthEntryScreenState extends ConsumerState<HealthEntryScreen> {
  AnimalOption? _selectedAnimal;
  HealthCategory _category = HealthCategory.vaccination;
  DateTime _date = DateTime.now();
  DateTime? _followUpDate;
  final _descriptionCtrl = TextEditingController();
  final _medicineCtrl = TextEditingController();
  final _dosageCtrl = TextEditingController();
  final _vetCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _medicineCtrl.dispose();
    _dosageCtrl.dispose();
    _vetCtrl.dispose();
    _costCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFollowUp}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFollowUp ? (_followUpDate ?? DateTime.now()) : _date,
      firstDate: isFollowUp
          ? DateTime.now()
          : DateTime.now().subtract(const Duration(days: 365)),
      lastDate: isFollowUp
          ? DateTime.now().add(const Duration(days: 180))
          : DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isFollowUp) {
        _followUpDate = picked;
      } else {
        _date = picked;
      }
    });
  }

  Future<void> _submit() async {
    final profile = ref.read(userProfileProvider).valueOrNull;
    if (profile == null || profile.orgId.isEmpty) return;

    if (_selectedAnimal == null) {
      _showSnack('Select an animal first.');
      return;
    }

    final cost = _costCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_costCtrl.text.trim());
    if (_costCtrl.text.trim().isNotEmpty && cost == null) {
      _showSnack('Cost must be a number.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(medicalServiceProvider).addRecord(
            orgId: profile.orgId,
            animalId: _selectedAnimal!.id,
            category: _category,
            description:
                _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
            medicine: _medicineCtrl.text.trim().isEmpty ? null : _medicineCtrl.text.trim(),
            dosage: _dosageCtrl.text.trim().isEmpty ? null : _dosageCtrl.text.trim(),
            vetName: _vetCtrl.text.trim().isEmpty ? null : _vetCtrl.text.trim(),
            cost: cost,
            date: _date,
            followUpDate: _followUpDate,
            notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            createdBy: profile.uid,
          );
      setState(() {
        _selectedAnimal = null;
        _category = HealthCategory.vaccination;
        _date = DateTime.now();
        _followUpDate = null;
        _descriptionCtrl.clear();
        _medicineCtrl.clear();
        _dosageCtrl.clear();
        _vetCtrl.clear();
        _costCtrl.clear();
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
    final recentAsync = ref.watch(_recentHealthProvider(profile.orgId));

    return Scaffold(
      appBar: AppBar(title: const Text('Animal Health')),
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
                  Text('Log Health Event', style: theme.textTheme.titleMedium),
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
                  DropdownButtonFormField<HealthCategory>(
                    value: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.medical_services_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: HealthCategory.values
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(healthCategoryLabel(c)),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _category = v!),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => _pickDate(isFollowUp: false),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                        border: OutlineInputBorder(),
                      ),
                      child: Text(DateFormat('dd MMM yyyy').format(_date)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descriptionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      hintText: 'e.g. Annual FMD vaccine',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _medicineCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Medicine (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _dosageCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Dosage (optional)',
                            hintText: 'e.g. 10ml',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _vetCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Vet Name (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _costCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Cost PKR (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => _pickDate(isFollowUp: true),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Follow-up Date (optional)',
                        prefixIcon: const Icon(Icons.event_repeat_outlined),
                        border: const OutlineInputBorder(),
                        suffixIcon: _followUpDate != null
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setState(() => _followUpDate = null),
                              )
                            : null,
                      ),
                      child: Text(
                        _followUpDate != null
                            ? DateFormat('dd MMM yyyy').format(_followUpDate!)
                            : 'Not set',
                        style: TextStyle(
                          color: _followUpDate != null ? null : Colors.grey,
                        ),
                      ),
                    ),
                  ),
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
                    'No health events logged yet.',
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
                            leading: const Icon(Icons.medical_services_outlined),
                            title: Text(healthCategoryLabel(r.category)),
                            subtitle: Text(
                              '${DateFormat('dd MMM yyyy').format(r.date)}'
                              '${r.cost != null ? ' • Rs ${NumberFormat('#,##0').format(r.cost)}' : ''}'
                              '${r.followUpDate != null ? ' • Follow-up: ${DateFormat('dd MMM').format(r.followUpDate!)}' : ''}',
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

final _recentHealthProvider =
    StreamProvider.family<List<MedicalRecord>, String>((ref, orgId) {
  return ref.watch(medicalServiceProvider).watchRecent(orgId: orgId);
});
