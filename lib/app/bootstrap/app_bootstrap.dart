import 'package:dukaan_book/core/config/env_config.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppBootstrap {
  const AppBootstrap._();

  static const String authRedirectScheme = 'dukaanbook';
  static const String authRedirectHost = 'auth-callback';

  static bool isSupabaseReady = false;

  static String get authEmailRedirectTo =>
      '$authRedirectScheme://$authRedirectHost/';

  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;

    await dotenv.load(fileName: '.env', isOptional: true);

    final config = EnvConfig.fromEnvironment();
    if (config.hasSupabaseCredentials) {
      await Supabase.initialize(
        url: config.supabaseUrl,
        anonKey: config.supabaseAnonKey,
      );
      isSupabaseReady = true;
    }
  }
}
