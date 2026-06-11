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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  void _refresh() {
    setState(() {
      _banksFuture = _fetchAccessibleBanks();
    });
  }

  Future<List<Map<String, dynamic>>> _fetchAccessibleBanks() async {
    final auth = context.read<AuthService>();
    final cloud = context.read<CloudProvider>();
    
    final doc = await FirebaseFirestore.instance.collection('users').doc(auth.user?.uid).get();
    if (!doc.exists) return [];
    
    final List<String> bankIds = List<String>.from(doc.data()?['accessible_banks'] ?? []);
    return await cloud.getAccessibleBanks(bankIds);
  }

  Future<void> _downloadBank(Map<String, dynamic> bank, {int? existingLocalId}) async {
    final cloud = context.read<CloudProvider>();
    final quiz = context.read<QuizProvider>();
    
    setState(() => _isDownloading = true);
    
    try {
      final cloudQuestions = await cloud.downloadBankQuestions(bank['bank_id']);
      final cloudUpdatedAt = (bank['updated_at'] as Timestamp?)?.toDate().toIso8601String() ?? "";

      if (existingLocalId != null) {
        // Update existing: clear questions first
        await quiz.updateClassSync(existingLocalId, cloudUpdatedAt);
        await quiz.clearQuestionsForClass(existingLocalId);
        await quiz.importManualQuestions(existingLocalId, cloudQuestions);
      } else {
        // New download
        await quiz.addClass(
          bank['name'] + " (Cloud)", 
          cloudBankId: bank['bank_id'], 
          cloudUpdatedAt: cloudUpdatedAt
        );
        await quiz.loadClasses();
        final localClass = quiz.classes.firstWhere((c) => c['cloud_bank_id'] == bank['bank_id']);
        await quiz.importManualQuestions(localClass['id'], cloudQuestions);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Synced ${cloudQuestions.length} questions locally!')));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final quizProvider = context.watch<QuizProvider>();

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
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(auth.user?.uid).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          final userData = snapshot.data?.data() as Map<String, dynamic>?;
          final bool canAccess = userData?['can_access_quizzes'] ?? true;

          if (!canAccess) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_person, size: 80, color: Colors.orange),
                    const SizedBox(height: 24),
                    const Text('Access Restricted', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    const Text(
                      'Your access to the cloud question store has been temporarily suspended by an administrator.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search available banks...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _banksFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                        final allBanks = snapshot.data ?? [];
                        final banks = allBanks.where((b) => b['name'].toString().toLowerCase().contains(_searchQuery)).toList();

                        if (banks.isEmpty) return const Center(child: Text('No matching banks found.'));

                        return ListView.builder(
                          itemCount: banks.length,
                          itemBuilder: (context, index) {
                            final bank = banks[index];
                            
                            // Check sync status
                            final localClass = quizProvider.classes.cast<Map<String, dynamic>?>().firstWhere(
                              (c) => c?['cloud_bank_id'] == bank['bank_id'], 
                              orElse: () => null
                            );

                            bool isDownloaded = localClass != null;
                            bool needsUpdate = false;
                            if (isDownloaded) {
                              final String localTime = localClass['cloud_updated_at'] ?? "";
                              final String cloudTime = (bank['updated_at'] as Timestamp?)?.toDate().toIso8601String() ?? "";
                              if (cloudTime.isNotEmpty && localTime != cloudTime) {
                                needsUpdate = true;
                              }
                            }

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ListTile(
                                title: Text(bank['name']),
                                subtitle: Text(bank['description'] ?? ''),
                                trailing: _buildTrailing(bank, localClass, isDownloaded, needsUpdate),
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
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTrailing(Map<String, dynamic> bank, Map<String, dynamic>? localClass, bool isDownloaded, bool needsUpdate) {
    if (needsUpdate) {
      return ElevatedButton.icon(
        onPressed: _isDownloading ? null : () => _downloadBank(bank, existingLocalId: localClass!['id']),
        icon: const Icon(Icons.sync, size: 18),
        label: const Text('UPDATE'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
      );
    }

    if (isDownloaded) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }

    return IconButton(
      icon: const Icon(Icons.download),
      onPressed: _isDownloading ? null : () => _downloadBank(bank),
      tooltip: 'Download locally',
    );
  }
}
