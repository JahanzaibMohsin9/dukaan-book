import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  const EnvConfig({required this.supabaseUrl, required this.supabaseAnonKey});

  factory EnvConfig.fromEnvironment() {
    const dartDefineUrl = String.fromEnvironment('SUPABASE_URL');
    const dartDefineAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    return EnvConfig(
      supabaseUrl: dartDefineUrl.isNotEmpty
          ? dartDefineUrl
          : dotenv.maybeGet('SUPABASE_URL') ?? '',
      supabaseAnonKey: dartDefineAnonKey.isNotEmpty
          ? dartDefineAnonKey
          : dotenv.maybeGet('SUPABASE_ANON_KEY') ?? '',
    );
  }

  final String supabaseUrl;
  final String supabaseAnonKey;

  bool get hasSupabaseCredentials =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
