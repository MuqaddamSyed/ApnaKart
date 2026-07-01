import 'package:supabase_flutter/supabase_flutter.dart';

/// Convenience accessor for the singleton Supabase client.
SupabaseClient get supabase => Supabase.instance.client;
