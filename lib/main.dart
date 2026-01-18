import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'services/background_sync_service.dart';
import 'services/notification_service.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/message_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await NotificationService.instance.init();
    await BackgroundSyncService.run();
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await Workmanager().registerPeriodicTask(
    'syncMessages',
    'syncMessages',
    frequency: const Duration(minutes: 15),
    initialDelay: const Duration(minutes: 1),
    constraints: Constraints(networkType: NetworkType.connected),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 5),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => MessageProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          final brightness = themeProvider.themeMode == AppThemeMode.system
              ? MediaQuery.platformBrightnessOf(context)
              : themeProvider.themeMode == AppThemeMode.dark
                  ? Brightness.dark
                  : Brightness.light;

          // Update status bar color
          SystemChrome.setSystemUIOverlayStyle(
            SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
            ),
          );

          return MaterialApp(
            title: 'OM Messenger',
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.themeMode == AppThemeMode.system
                ? ThemeMode.system
                : themeProvider.themeMode == AppThemeMode.dark
                    ? ThemeMode.dark
                    : ThemeMode.light,
            home: const AuthWrapper(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  Future<void>? _restoreFuture;

  @override
  void initState() {
    super.initState();
    _restoreFuture = Future.microtask(() => context.read<AuthProvider>().restoreSession());
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        return FutureBuilder<void>(
          future: _restoreFuture,
          builder: (context, snapshot) {
            if (auth.isRestoring) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return auth.isAuthenticated ? const HomeScreen() : const LoginScreen();
          },
        );
      },
    );
  }
}
