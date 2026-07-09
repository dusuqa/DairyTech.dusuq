import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PendingInviteScreen extends StatelessWidget {
  const PendingInviteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hourglass_top, size: 64, color: Color(0xFF2E7D32)),
              const SizedBox(height: 24),
              const Text(
                'Account Pending',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your account is being set up or has been disabled.\nPlease contact your farm administrator.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
