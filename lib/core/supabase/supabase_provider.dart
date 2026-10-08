import 'package:dukaan_book/app/bootstrap/app_bootstrap.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (!AppBootstrap.isSupabaseReady) {
    return null;
  }

  return Supabase.instance.client;
});
