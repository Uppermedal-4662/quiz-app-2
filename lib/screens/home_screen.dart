import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../providers/cloud_provider.dart';
import '../providers/quiz_provider.dart';
import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import '../services/tutorial_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey _storeKey = GlobalKey();
  final GlobalKey _quizKey = GlobalKey();
  final GlobalKey _classKey = GlobalKey();
  final GlobalKey _supportKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstRun());
  }

  Future<void> _checkFirstRun() async {
    final auth = context.read<AuthService>();
    
    // Wait for auth to finish loading if it hasn't yet
    if (auth.isLoading) {
      Future.delayed(const Duration(milliseconds: 500), _checkFirstRun);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final bool hasSeenTutorial = prefs.getBool('has_seen_tutorial_v2') ?? false;
    
    if (!hasSeenTutorial && mounted) {
      _showTutorial();
    }
  }

  void _showTutorial() {
    final auth = context.read<AuthService>();
    final List<TargetFocus> targets = [
      if (!auth.isGuest)
        TutorialService.createTarget(
          key: _storeKey,
          identify: "store",
          title: "Question Store",
          content: "Tap here to browse and download professional question banks from our cloud store.",
          align: ContentAlign.bottom,
        ),
      TutorialService.createTarget(
        key: _classKey,
        identify: "classes",
        title: "Manage Classes",
        content: "Create your own local categories, rename classes, and upload your personal PDFs for AI extraction.",
        align: ContentAlign.top,
      ),
      TutorialService.createTarget(
        key: _quizKey,
        identify: "quiz",
        title: "Start a Quiz",
        content: "Ready to test yourself? Use our sample data or your own to start a highly adaptive quiz session.",
        align: ContentAlign.top,
      ),
      TutorialService.createTarget(
        key: _supportKey,
        identify: "support",
        title: "Need Help?",
        content: "You can contact the administrator directly from here if you have any questions or find errors.",
        align: ContentAlign.bottom,
      ),
    ];

    TutorialService.showOnboarding(
      context: context,
      targets: targets,
      onFinish: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('has_seen_tutorial_v2', true);
      },
    );
  }

  void _showContactDialog(BuildContext context) {
    final auth = context.read<AuthService>();
    if (auth.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in to contact the admin.')));
      return;
    }

    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact Admin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Send a message to the Super Admin. Limit: 5 per day.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Your message...'),
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              try {
                await context.read<CloudProvider>().sendMessageToAdmin(auth.user!.uid, auth.user!.email!, controller.text.trim());
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message sent!')));
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz AI'),
        actions: [
          IconButton(
            key: _supportKey,
            onPressed: () => _showContactDialog(context),
            icon: const Icon(Icons.contact_support),
            tooltip: 'Contact Admin',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.quiz, size: 100, color: Colors.blue),
              const SizedBox(height: 48),
              Consumer<QuizProvider>(
                builder: (context, provider, child) {
                  if (provider.hasSavedSession) {
                    return ElevatedButton.icon(
                      key: _quizKey,
                      onPressed: () async {
                        final resumed = await provider.resumeSession();
                        if (resumed && context.mounted) {
                          Navigator.pushNamed(context, '/quiz');
                        } else if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to resume session.')));
                        }
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Resume Quiz'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    );
                  } else {
                    return ElevatedButton.icon(
                      key: _quizKey,
                      onPressed: () => Navigator.pushNamed(context, '/quiz'),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Quiz'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 18),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              if (!auth.isGuest)
                OutlinedButton.icon(
                  key: _storeKey,
                  onPressed: () => Navigator.pushNamed(context, '/store'),
                  icon: const Icon(Icons.cloud_download),
                  label: const Text('Question Store'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                ),
              if (!auth.isGuest) const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/history'),
                icon: const Icon(Icons.history),
                label: const Text('Quiz History'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: _classKey,
                onPressed: () => Navigator.pushNamed(context, '/classes'),
                icon: const Icon(Icons.class_),
                label: const Text('Manage Classes'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 32),
              TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/guide'),
                icon: const Icon(Icons.help_outline),
                label: const Text('App Guide & Help'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
