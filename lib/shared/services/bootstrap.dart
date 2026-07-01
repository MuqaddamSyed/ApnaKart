import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/supabase_config.dart';

/// Shared startup used by every flavor's main().
Future<void> bootstrap({bool initializeFirebase = false}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  if (initializeFirebase) {
    await Firebase.initializeApp();
  }
  await Hive.initFlutter();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );
}
