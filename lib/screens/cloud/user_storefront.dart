import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/cloud_provider.dart';
import '../../providers/quiz_provider.dart';
import '../../services/auth_service.dart';

class UserStorefront extends StatefulWidget {
  const UserStorefront({super.key});

  @override
  State<UserStorefront> createState() => _UserStorefrontState();
}

class _UserStorefrontState extends State<UserStorefront> {
  late Future<List<Map<String, dynamic>>> _banksFuture;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _banksFuture = _fetchAccessibleBanks();
    });
  }

  Future<List<Map<String, dynamic>>> _fetchAccessibleBanks() async {
    final auth = context.read<AuthService>();
    final cloud = context.read<CloudProvider>();
    
    // Efficiently fetch only the current user's document
    final doc = await FirebaseFirestore.instance.collection('users').doc(auth.user?.uid).get();
    if (!doc.exists) return [];
    
    final List<String> bankIds = List<String>.from(doc.data()?['accessible_banks'] ?? []);
    return await cloud.getAccessibleBanks(bankIds);
  }

  Future<void> _downloadBank(Map<String, dynamic> bank) async {
    final cloud = context.read<CloudProvider>();
    final quiz = context.read<QuizProvider>();
    
    setState(() => _isDownloading = true);
    
    try {
      final cloudQuestions = await cloud.downloadBankQuestions(bank['bank_id']);
      await quiz.addClass(bank['name'] + " (Cloud)");
      await quiz.loadClasses();
      final localClass = quiz.classes.firstWhere((c) => c['name'] == bank['name'] + " (Cloud)");
      await quiz.importManualQuestions(localClass['id'], cloudQuestions);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloaded ${cloudQuestions.length} questions locally!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Question Store'),
        actions: [
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/home'),
            icon: const Icon(Icons.quiz),
            tooltip: 'Go to Local Quiz',
          ),
          IconButton(onPressed: () => context.read<AuthService>().signOut(), icon: const Icon(Icons.logout)),
        ],
      ),
      body: Stack(
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _banksFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              final banks = snapshot.data ?? [];

              if (banks.isEmpty) return const Center(child: Text('No banks shared with you yet.'));

              return ListView.builder(
                itemCount: banks.length,
                itemBuilder: (context, index) {
                  final bank = banks[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      title: Text(bank['name']),
                      subtitle: Text(bank['description'] ?? ''),
                      trailing: IconButton(
                        icon: const Icon(Icons.download),
                        onPressed: _isDownloading ? null : () => _downloadBank(bank),
                        tooltip: 'Download locally',
                      ),
                    ),
                  );
                },
              );
            },
          ),
          if (_isDownloading)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
