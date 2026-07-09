import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AuthPhase { unknown, signedOut, signedIn, busy }

class AuthState {
  const AuthState({required this.phase, this.error});
  final AuthPhase phase;
  final String? error;
}

/// Wraps Supabase Auth (mandatory for the app). Exposes sign in / up / out and
/// reflects the current session.
class AuthCubit extends Cubit<AuthState> {
  AuthCubit() : super(const AuthState(phase: AuthPhase.unknown)) {
    final session = _client.auth.currentSession;
    emit(AuthState(
      phase: session != null ? AuthPhase.signedIn : AuthPhase.signedOut,
    ));
    _client.auth.onAuthStateChange.listen((data) {
      final signedIn = data.session != null;
      emit(AuthState(
        phase: signedIn ? AuthPhase.signedIn : AuthPhase.signedOut,
      ));
    });
  }

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> signIn(String email, String password) =>
      _run(() => _client.auth.signInWithPassword(email: email, password: password));

  Future<void> signUp(String email, String password) =>
      _run(() => _client.auth.signUp(email: email, password: password));

  Future<void> signOut() => _client.auth.signOut();

  Future<void> _run(Future<void> Function() action) async {
    emit(const AuthState(phase: AuthPhase.busy));
    try {
      await action();
      // onAuthStateChange emits signedIn; nothing else to do.
    } on AuthException catch (e) {
      emit(AuthState(phase: AuthPhase.signedOut, error: e.message));
    } catch (e) {
      emit(AuthState(phase: AuthPhase.signedOut, error: e.toString()));
    }
  }
}
