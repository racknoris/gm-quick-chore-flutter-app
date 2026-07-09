import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/auth_cubit.dart';

/// Minimal email/password auth. Supabase Auth is mandatory before any backend
/// call, so this gates the whole app.
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isSignUp = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final cubit = context.read<AuthCubit>();
    final email = _email.text.trim();
    final password = _password.text;
    if (_isSignUp) {
      cubit.signUp(email, password);
    } else {
      cubit.signIn(email, password);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: BlocBuilder<AuthCubit, AuthState>(
                builder: (context, state) {
                  final busy = state.phase == AuthPhase.busy;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Quick Chores',
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (state.error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          state.error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: busy ? null : _submit,
                        child: busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_isSignUp ? 'Sign up' : 'Sign in'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => _isSignUp = !_isSignUp),
                        child: Text(_isSignUp
                            ? 'Have an account? Sign in'
                            : 'New here? Create an account'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
