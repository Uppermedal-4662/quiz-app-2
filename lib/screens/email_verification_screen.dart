import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class EmailVerificationScreen extends StatelessWidget {
  const EmailVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Your Email')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.mark_email_unread, size: 80, color: Colors.orange),
            const SizedBox(height: 24),
            const Text(
              'A verification email has been sent to your inbox. Please click the link to continue.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: () => context.read<AuthService>().reloadUser(),
              child: const Text('I HAVE VERIFIED'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.read<AuthService>().sendVerificationEmail(),
              child: const Text('Resend Verification Email'),
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () => context.read<AuthService>().signOut(),
              child: const Text('Log Out'),
            ),
          ],
        ),
      ),
    );
  }
}
