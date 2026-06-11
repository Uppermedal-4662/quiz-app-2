import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'providers/quiz_provider.dart';
import 'providers/cloud_provider.dart';
import 'providers/settings_provider.dart';
import 'services/security_service.dart';
import 'services/auth_service.dart';
import 'screens/home_screen.dart';
import 'screens/config_screen.dart';
import 'screens/class_management_screen.dart';
import 'screens/quiz_screen.dart';
import 'screens/history_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/email_verification_screen.dart';
import 'screens/cloud/super_admin_dashboard.dart';
import 'screens/cloud/admin_dashboard.dart';
import 'screens/cloud/user_storefront.dart';
import 'screens/settings_screen.dart';
import 'screens/guide_screen.dart';

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
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
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
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return MaterialApp(
          title: 'Quiz AI',
          debugShowCheckedModeBanner: false,
          themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
            useMaterial3: true,
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
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
            '/settings': (context) => const SettingsScreen(),
            '/guide': (context) => const GuideScreen(),
          },
        );
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

        // If explicitly in Guest mode, show HomeScreen
        if (auth.isGuest) {
          return const HomeScreen();
        }

        // If not authenticated, show AuthScreen (Login/Signup)
        if (!auth.isAuthenticated) {
          return const AuthScreen();
        }

        // Email Verification Check (Skip for Super Admin during bootstrap or Guest)
        if (auth.role != UserRole.guest && !auth.user!.emailVerified) {
          return const EmailVerificationScreen();
        }

        // Banned/Disabled Account Check
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(auth.user?.uid).get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            
            final data = snapshot.data?.data() as Map<String, dynamic>?;
            final bool isDisabled = data?['is_disabled'] ?? false;

            if (isDisabled) {
              return const BannedScreen();
            }

            // Authenticated users - route based on role stored in Firestore
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
      },
    );
  }
}

class BannedScreen extends StatelessWidget {
  const BannedScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block, size: 100, color: Colors.red),
              const SizedBox(height: 24),
              const Text('Account Suspended', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text(
                'Your account has been disabled by an administrator. Please contact support for more information.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: () => context.read<AuthService>().signOut(),
                child: const Text('LOG OUT'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
