import 'dart:async';

import 'package:dukaan_book/app/bootstrap/app_bootstrap.dart';
import 'package:dukaan_book/core/supabase/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final authSessionProvider = StreamProvider<Session?>((ref) {
  return ref.watch(authRepositoryProvider).sessionChanges();
});

class AuthRepository {
  const AuthRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  User? get currentUser => _client?.auth.currentUser;

  Session? get currentSession => _client?.auth.currentSession;

  Stream<Session?> sessionChanges() async* {
    final client = _client;
    if (client == null) {
      yield null;
      return;
    }

    yield client.auth.currentSession;
    await for (final state in client.auth.onAuthStateChange) {
      yield state.session;
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    final client = _requireClient();
    await client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUp({required String email, required String password}) async {
    final client = _requireClient();
    await client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: AppBootstrap.authEmailRedirectTo,
    );
  }

  Future<void> signOut() async {
    final client = _requireClient();
    await client.auth.signOut();
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw const AuthConfigException();
    }
    return client;
  }
}

class AuthConfigException implements Exception {
  const AuthConfigException();
}
