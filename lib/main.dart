import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/quiz_provider.dart';
import 'providers/cloud_provider.dart';
import 'services/security_service.dart';
import 'services/auth_service.dart';
import 'screens/home_screen.dart';
import 'screens/config_screen.dart';
import 'screens/class_management_screen.dart';
import 'screens/quiz_screen.dart';
import 'screens/history_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/cloud/super_admin_dashboard.dart';
import 'screens/cloud/admin_dashboard.dart';
import 'screens/cloud/user_storefront.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase (Requires google-services.json on Android)
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase initialization failed: $e. Ensure google-services.json is present.');
  }

  // Initialize SecurityService (loads/generates AES key)
  final securityService = SecurityService();
  await securityService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => CloudProvider()),
        ChangeNotifierProvider(
          create: (_) => QuizProvider()
            ..loadApiKey()
            ..loadClasses(),
        ),
      ],
      child: const QuizApp(),
    ),
  );
}

class QuizApp extends StatelessWidget {
  const QuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quiz AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      home: const AuthGate(),
      routes: {
        '/home': (context) => const HomeScreen(),
        '/config': (context) => const ConfigScreen(),
        '/classes': (context) => const ClassManagementScreen(),
        '/quiz': (context) => const QuizScreen(),
        '/history': (context) => const HistoryScreen(),
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, child) {
        if (auth.isLoading) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (auth.role == UserRole.guest) {
          return const HomeScreen();
        }

        if (!auth.isAuthenticated) {
          return const AuthScreen();
        }

        // Authenticated users
        switch (auth.role) {
          case UserRole.superAdmin:
            return const SuperAdminDashboard();
          case UserRole.admin:
            return const AdminDashboard();
          case UserRole.user:
            return const UserStorefront();
          case UserRole.guest:
            return const HomeScreen();
        }
      },
    );
  }
}
