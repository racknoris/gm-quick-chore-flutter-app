import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AuthPhase { unknown, signedOut, signedIn, busy }

class AuthState {
  const AuthState({required this.phase, this.error});
  final AuthPhase phase;
  final String? error;
}

/// Single source of truth for auth readiness (Supabase Auth is mandatory).
///
/// Critically, we only report `signedIn` once we hold a **valid** token — on a
/// cold start `Supabase.initialize` restores the persisted session synchronously
/// but its access-token may be **expired**, and it refreshes in the background.
/// If we showed the app on the restored-but-expired session, the first backend
/// call would 401. So we stay in `unknown` (splash) until either there's no
/// session (-> signedOut) or we've confirmed / refreshed a valid one
/// (-> signedIn). No retry logic, no error flash: the authed UI simply doesn't
/// mount until the token is usable.
class AuthCubit extends Cubit<AuthState> {
  AuthCubit() : super(const AuthState(phase: AuthPhase.unknown)) {
    _sub = _client.auth.onAuthStateChange.listen(_onAuthChange);
    _bootstrap();
  }

  SupabaseClient get _client => Supabase.instance.client;
  late final StreamSubscription<dynamic> _sub;

  /// Decide the initial phase, refreshing an expired session before we commit
  /// to `signedIn`.
  Future<void> _bootstrap() async {
    final session = _client.auth.currentSession;
    if (session == null) {
      emit(const AuthState(phase: AuthPhase.signedOut));
      return;
    }
    if (session.isExpired) {
      try {
        await _client.auth.refreshSession();
        emit(const AuthState(phase: AuthPhase.signedIn));
      } catch (_) {
        // Refresh failed (expired/revoked/offline) — treat as signed out.
        emit(const AuthState(phase: AuthPhase.signedOut));
      }
      return;
    }
    emit(const AuthState(phase: AuthPhase.signedIn));
  }

  /// Ongoing auth changes (login, logout, background token refresh). The
  /// `initialSession` event is handled by `_bootstrap`, so we ignore it here to
  /// avoid committing to `signedIn` on a not-yet-refreshed token.
  void _onAuthChange(dynamic data) {
    final AuthChangeEvent event = data.event as AuthChangeEvent;
    final Session? session = data.session as Session?;
    switch (event) {
      case AuthChangeEvent.initialSession:
        return; // owned by _bootstrap
      case AuthChangeEvent.signedOut:
        emit(const AuthState(phase: AuthPhase.signedOut));
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.userUpdated:
        if (session != null && !session.isExpired) {
          emit(const AuthState(phase: AuthPhase.signedIn));
        }
      default:
        break;
    }
  }

  Future<void> signIn(String email, String password) =>
      _run(() => _client.auth.signInWithPassword(email: email, password: password));

  Future<void> signUp(String email, String password) =>
      _run(() => _client.auth.signUp(email: email, password: password));

  Future<void> signOut() => _client.auth.signOut();

  Future<void> _run(Future<void> Function() action) async {
    emit(const AuthState(phase: AuthPhase.busy));
    try {
      await action();
      // _onAuthChange emits signedIn once the session is valid.
    } on AuthException catch (e) {
      emit(AuthState(phase: AuthPhase.signedOut, error: e.message));
    } catch (e) {
      emit(AuthState(phase: AuthPhase.signedOut, error: e.toString()));
    }
  }

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}
