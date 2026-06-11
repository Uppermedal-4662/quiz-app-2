import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Settings')),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _SectionHeader('Visuals'),
              SwitchListTile(
                title: const Text('Dark Mode'),
                subtitle: const Text('Switch to a dark color theme'),
                value: settings.isDarkMode,
                onChanged: (v) => settings.setDarkMode(v),
              ),
              const Divider(),
              const _SectionHeader('Gamification'),
              SwitchListTile(
                title: const Text('Confetti Effects'),
                subtitle: const Text('Show confetti on high quiz scores'),
                value: settings.enableGamification,
                onChanged: (v) => settings.setGamification(v),
              ),
              const Divider(),
              const _SectionHeader('Feedback'),
              SwitchListTile(
                title: const Text('Haptic Feedback'),
                subtitle: const Text('Vibrate on correct/wrong answers'),
                value: settings.enableHaptics,
                onChanged: (v) => settings.setHaptics(v),
              ),
              const Divider(),
              const _SectionHeader('Accessibility'),
              SwitchListTile(
                title: const Text('Text-to-Speech (AI Voice)'),
                subtitle: const Text('Enable reading questions aloud'),
                value: settings.enableTTS,
                onChanged: (v) => settings.setTTS(v),
              ),
              const Divider(),
              const _SectionHeader('AI & Models'),
              ListTile(
                title: const Text('Gemini AI Configuration'),
                subtitle: const Text('Set API Key and Model preferences'),
                leading: const Icon(Icons.psychology),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(context, '/config'),
              ),
              const Divider(height: 48),
              Center(
                child: TextButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/guide'),
                  icon: const Icon(Icons.help_outline),
                  label: const Text('View User Guide'),
                ),
              ),
              const Center(
                child: Text(
                  'Version 2.0.0 (UX Overhaul)',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
