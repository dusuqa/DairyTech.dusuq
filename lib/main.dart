import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'routing/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://rwlomitusajzuujygwyd.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ3bG9taXR1c2FqenV1anlnd3lkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM1ODY4NTQsImV4cCI6MjA5OTE2Mjg1NH0.LToNa3AqJOHEsj1V7Z3ulNOrx5X0ohhm7H4ljoTRdbo',
  );
  runApp(const ProviderScope(child: DusuqApp()));
}

class DusuqApp extends ConsumerWidget {
  const DusuqApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'DUSUQ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
