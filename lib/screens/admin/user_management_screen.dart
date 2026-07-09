import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dusuq/providers/auth_providers.dart';

class UserManagementScreen extends ConsumerWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Text(
          'User management coming soon\nOrg: ${profile?.orgId ?? "All"}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
