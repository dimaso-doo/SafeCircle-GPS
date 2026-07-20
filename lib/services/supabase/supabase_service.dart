import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  const SupabaseService({required this.supabaseUrl, required this.anonKey});

  final String supabaseUrl;
  final String anonKey;

  Future<void> initialize() async {
    await Supabase.initialize(url: supabaseUrl, anonKey: anonKey);
  }
}
