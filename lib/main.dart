import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
  url: 'https://hcqboyhipawnicsgyiro.supabase.co',
  publishableKey: 'sb_publishable_lo4iw_FJgP8CfzmvL5XfIg_hzzDfIgH',
);

  runApp(const ProjectAtlasApp());
}

class ProjectAtlasApp extends StatelessWidget {
  const ProjectAtlasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Project Atlas',
      home: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        body: const Center(
          child: Text(
            'Project Atlas collegato a Supabase',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF172033),
            ),
          ),
        ),
      ),
    );
  }
}