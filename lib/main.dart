import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'config.dart';
import 'cubit/auth_cubit.dart';
import 'cubit/record_cubit.dart';
import 'cubit/recordings_cubit.dart';
import 'services/api_client.dart';
import 'services/background_recorder.dart';
import 'services/pending_uploads.dart';
import 'services/storage_service.dart';
import 'ui/auth_page.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
  );
  final recorder = BackgroundRecorder()..init();
  runApp(App(recorder: recorder));
}

class App extends StatelessWidget {
  const App({super.key, required this.recorder});

  final BackgroundRecorder recorder;

  @override
  Widget build(BuildContext context) {
    final api = ApiClient();
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: api),
        RepositoryProvider(create: (_) => StorageService()),
        RepositoryProvider.value(value: recorder),
        RepositoryProvider(create: (_) => PendingUploads()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => AuthCubit()),
          BlocProvider(
            create: (ctx) => RecordCubit(
              api: ctx.read<ApiClient>(),
              storage: ctx.read<StorageService>(),
              recorder: ctx.read<BackgroundRecorder>(),
              pending: ctx.read<PendingUploads>(),
            ),
          ),
          BlocProvider(create: (_) => RecordingsCubit(api)),
        ],
        child: MaterialApp(
          title: 'Quick Chores',
          theme: ThemeData(
            colorSchemeSeed: Colors.indigo,
            useMaterial3: true,
          ),
          // WithForegroundTask keeps the foreground-service lifecycle wired to
          // the widget tree (required by flutter_foreground_task).
          home: const WithForegroundTask(child: _AuthGate()),
        ),
      ),
    );
  }
}

/// Shows the app when signed in, the auth screen otherwise. Auth is mandatory.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        switch (state.phase) {
          case AuthPhase.signedIn:
            return const HomePage();
          case AuthPhase.unknown:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          case AuthPhase.signedOut:
          case AuthPhase.busy:
            return const AuthPage();
        }
      },
    );
  }
}
