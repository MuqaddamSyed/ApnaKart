import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Reads Supabase config from the bundled .env asset.
class SupabaseConfig {
  static String get url => dotenv.env['SUPABASE_URL'] ?? '';
  static String get anonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  static String get fcmServerKey => dotenv.env['FCM_SERVER_KEY'] ?? '';

  static const String productImageBucket = 'product-images';
}
