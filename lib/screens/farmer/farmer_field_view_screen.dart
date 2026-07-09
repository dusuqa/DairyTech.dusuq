import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dusuq/providers/auth_providers.dart';
import 'package:dusuq/screens/farmer/milk_entry_screen.dart';
import 'package:dusuq/screens/farmer/breeding_entry_screen.dart';
import 'package:dusuq/screens/farmer/feed_entry_screen.dart';
import 'package:dusuq/screens/farmer/health_entry_screen.dart';

/// Farmer Field View — reachable by Farmer, OrgAdmin, SuperAdmin (the
/// latter two CAN see this view to verify what farmers experience, but a
/// Farmer can NEVER reach /admin/*, enforced in app_router.dart).
///
/// Deliberately a single-screen, large-tap-target, minimal-navigation
/// layout. This is what gets used standing in a cowshed on a cracked phone
/// screen, possibly with gloves on — it is NOT a smaller version of the
/// admin dashboard, it's a fundamentally different, narrower interface.
///
/// WIRING STATUS — all four tiles are now live, org-scoped, real data:
///   Milk Yield      -> MilkEntryScreen   (MilkService)
///   Heat / Breeding -> BreedingEntryScreen (BreedingService)
///   Animal Health   -> HealthEntryScreen   (MedicalService)
///   Feed Log        -> FeedEntryScreen     (FeedService)
class FarmerFieldViewScreen extends ConsumerWidget {
  const FarmerFieldViewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(profile?.displayName.isNotEmpty == true
            ? 'Welcome, ${profile!.displayName}'
            : 'DUSUQ Field Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.1,
        children: [
          _LogTile(
            label: 'Milk Yield',
            icon: Icons.water_drop,
            color: Colors.teal,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MilkEntryScreen()),
            ),
          ),
          _LogTile(
            label: 'Heat / Breeding',
            icon: Icons.favorite_outline,
            color: Colors.purple,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BreedingEntryScreen()),
            ),
          ),
          _LogTile(
            label: 'Animal Health',
            icon: Icons.medical_services_outlined,
            color: Colors.red,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HealthEntryScreen()),
            ),
          ),
          _LogTile(
            label: 'Feed Log',
            icon: Icons.grass_outlined,
            color: Colors.amber,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FeedEntryScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _LogTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
