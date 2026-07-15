import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../config/app_config.dart';

/// Thrown for any auth failure with a user-friendly message.
class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Minimal result describing an authenticated user.
class AuthResult {
  AuthResult({required this.userId, required this.email});
  final String userId;
  final String? email;
}

/// Wraps Supabase Auth (email/password + Google) and profile bootstrapping.
///
/// When Supabase is not configured (see [AppConfig.supabaseEnabled]) the
/// service runs in an offline "demo" mode that mints a deterministic local
/// user id so the entire UI/gameplay remains explorable without a project.
class AuthService {
  sb.SupabaseClient? get _client =>
      AppConfig.supabaseEnabled ? sb.Supabase.instance.client : null;

  /// The currently authenticated user id, or null if signed out.
  String? get currentUserId => _client?.auth.currentUser?.id;

  /// Register a new account with email + password, then ensure a profile row.
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String username,
    required String startingClass,
  }) async {
    if (!AppConfig.supabaseEnabled) {
      return _offlineUser(email);
    }
    try {
      final res = await _client!.auth.signUp(email: email, password: password);
      final user = res.user;
      if (user == null) {
        throw AuthException('Sign-up failed. Please try again.');
      }
      await _upsertProfile(
        userId: user.id,
        username: username,
        startingClass: startingClass,
      );
      return AuthResult(userId: user.id, email: user.email);
    } on sb.AuthException catch (e) {
      throw AuthException(e.message);
    }
  }

  /// Sign in with email + password.
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    if (!AppConfig.supabaseEnabled) {
      return _offlineUser(email);
    }
    try {
      final res = await _client!.auth
          .signInWithPassword(email: email, password: password);
      final user = res.user;
      if (user == null) {
        throw AuthException('Invalid credentials.');
      }
      return AuthResult(userId: user.id, email: user.email);
    } on sb.AuthException catch (e) {
      throw AuthException(e.message);
    }
  }

  /// Sign in with Google via Supabase OAuth.
  ///
  /// Uses the OAuth web flow which works cross-platform without extra native
  /// client-id wiring. For a fully native Google button, integrate
  /// `google_sign_in` and exchange the idToken with
  /// `signInWithIdToken(...)` here.
  Future<void> signInWithGoogle() async {
    if (!AppConfig.supabaseEnabled) {
      throw AuthException('Google Sign-In requires a configured Supabase project.');
    }
    try {
      await _client!.auth.signInWithOAuth(
        sb.OAuthProvider.google,
        redirectTo: 'io.supabase.faunabattler://login-callback/',
      );
    } on sb.AuthException catch (e) {
      throw AuthException(e.message);
    }
  }

  /// Sign the user out (and revoke the session, per Supabase security guidance).
  Future<void> signOut() async {
    await _client?.auth.signOut();
  }

  /// Create or update the player's `profiles` row.
  Future<void> _upsertProfile({
    required String userId,
    required String username,
    required String startingClass,
  }) async {
    final client = _client;
    if (client == null) return;
    // The DB trigger may already have inserted a stub row on sign-up; upsert
    // keeps this idempotent and lets us attach the chosen username/class.
    await client.from('profiles').upsert({
      'user_id': userId,
      'username': username,
      'starting_class': startingClass,
    });
  }

  /// Deterministic offline user so demo mode is stable across restarts.
  AuthResult _offlineUser(String email) {
    final seed = email.trim().toLowerCase();
    final id = 'offline-${seed.hashCode.toRadixString(16)}';
    return AuthResult(userId: id, email: email);
  }
}
