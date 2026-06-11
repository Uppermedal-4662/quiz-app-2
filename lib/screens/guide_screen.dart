import 'package:flutter/material.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Guide')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildHero(),
          const SizedBox(height: 32),
          _buildChapter(
            '🔑 User Roles',
            '• GUEST: Use the app locally. Upload your own PDFs to your device only.\n'
            '• USER: Log in to access the Cloud Store and download official question banks.\n'
            '• ADMIN: Create cloud banks and upload questions for your students.\n'
            '• SUPER ADMIN: Manage all users and grant permissions.',
          ),
          _buildChapter(
            '☁️ Cloud Synchronization',
            'Go to the "Question Store" to find banks shared with you. Tap "Download" to bring them to your device. '
            'If an admin updates a bank, you\'ll see a "Update Available" badge.',
          ),
          _buildChapter(
            '⏱️ Timer Modes',
            '• NONE: Practice at your own pace.\n'
            '• PER QUESTION: A timer for each question. Times out? The question is skipped.\n'
            '• PER QUIZ: A total time for the whole quiz.\n'
            '• SPEEDRUN: Unlimited questions! See how many you can finish before time runs out.',
          ),
          _buildChapter(
            '🎨 Personalizing your Experience',
            'Head to "App Settings" to toggle:\n'
            '• DARK MODE: Better for night studying.\n'
            '• CONFETTI: Celebrate your high scores!\n'
            '• HAPTICS: Feel the response when you answer.\n'
            '• AI VOICE (TTS): Have the app read questions aloud.',
          ),
          _buildChapter(
            '📈 History & Review',
            'Every quiz is saved. In History, you can tap any attempt to see exactly what you marked and what the correct answers were. '
            'You can even fix errors in questions directly from the review screen.',
          ),
          _buildChapter(
            '🛡️ Single Device Login',
            'For security, your account can only be active on one device at a time. Logging in on a new phone will automatically sign you out of the old one.',
          ),
          const SizedBox(height: 48),
          const Center(
            child: Text('Happy Learning!', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.blue)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.auto_awesome, size: 48, color: Colors.blue),
          SizedBox(height: 16),
          Text(
            'Welcome to Quiz AI',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Everything you need to know to master your study sessions.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildChapter(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
          const SizedBox(height: 12),
          Text(body, style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87)),
        ],
      ),
    );
  }
}
