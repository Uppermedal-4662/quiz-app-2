import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../providers/cloud_provider.dart';
import '../../providers/quiz_provider.dart';
import '../../services/auth_service.dart';
import 'cloud_manual_import_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late Future<List<Map<String, dynamic>>> _banksFuture;
  String _uploadStatus = "";
  bool _isProcessing = false;
  bool _canViewInbox = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthService>();
    final uid = auth.user?.uid;
    if (uid != null) {
      setState(() {
        _banksFuture = context.read<CloudProvider>().getMyBanks(uid);
      });

      // Check if this admin has inbox permission
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (mounted) {
        setState(() => _canViewInbox = doc.data()?['can_view_inbox'] ?? false);
      }
    }
  }

  Future<void> _createBank() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Question Bank'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Bank Name')),
            TextField(controller: descController, decoration: const InputDecoration(labelText: 'Description')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      final cloud = context.read<CloudProvider>();
      final auth = context.read<AuthService>();
      await cloud.createQuestionBank(nameController.text, descController.text, auth.user!.uid);
      _refresh();
    }
  }

  Future<void> _pickAndUploadPdf(String bankId) async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result != null) {
      Uint8List bytes;
      if (result.files.single.bytes != null) {
        bytes = result.files.single.bytes!;
      } else {
        final file = File(result.files.single.path!);
        bytes = await file.readAsBytes();
      }
      
      final quizProvider = context.read<QuizProvider>();
      final cloud = context.read<CloudProvider>();

      setState(() {
        _isProcessing = true;
        _uploadStatus = "Preparing file...";
      });

      try {
        final questions = await quizProvider.geminiExtractQuestions(
          bytes,
          onProgress: (status) => setState(() => _uploadStatus = status),
        );
        
        setState(() => _uploadStatus = "Uploading ${questions.length} questions to cloud...");
        await cloud.uploadQuestionsToCloud(bankId, questions);
        
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Questions uploaded to Cloud!')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      } finally {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _uploadStatus = "";
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canViewInbox) {
      return _buildStandardDashboard();
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          actions: [
            IconButton(
              onPressed: () => Navigator.pushNamed(context, '/home'),
              icon: const Icon(Icons.quiz),
              tooltip: 'Go to Local Quiz',
            ),
            IconButton(onPressed: () => context.read<AuthService>().signOut(), icon: const Icon(Icons.logout)),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.account_balance), text: 'My Banks'),
              Tab(icon: Icon(Icons.inbox), text: 'Inbox'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildBanksView(),
            _buildInboxView(),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isProcessing ? null : _createBank,
          icon: const Icon(Icons.add),
          label: const Text('New Bank'),
        ),
      ),
    );
  }

  Widget _buildStandardDashboard() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/home'),
            icon: const Icon(Icons.quiz),
            tooltip: 'Go to Local Quiz',
          ),
          IconButton(onPressed: () => context.read<AuthService>().signOut(), icon: const Icon(Icons.logout)),
        ],
      ),
      body: _buildBanksView(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isProcessing ? null : _createBank,
        icon: const Icon(Icons.add),
        label: const Text('New Bank'),
      ),
    );
  }

  Widget _buildBanksView() {
    return Stack(
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _banksFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            final banks = snapshot.data ?? [];

            if (banks.isEmpty) return const Center(child: Text('You haven\'t created any banks yet.'));

            return ListView.builder(
              itemCount: banks.length,
              itemBuilder: (context, index) {
                final bank = banks[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Text(bank['name']),
                    subtitle: Text(bank['description'] ?? ''),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_note),
                          onPressed: _isProcessing
                              ? null
                              : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CloudManualImportScreen(
                                        bankId: bank['bank_id'],
                                        bankName: bank['name'],
                                      ),
                                    ),
                                  ).then((_) => _refresh()),
                          tooltip: 'Direct JSON Import',
                        ),
                        IconButton(
                          icon: const Icon(Icons.cloud_upload),
                          onPressed: _isProcessing ? null : () => _pickAndUploadPdf(bank['bank_id']),
                          tooltip: 'AI PDF Upload',
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
        if (_isProcessing)
          Container(
            color: Colors.black45,
            child: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      const Text('Cloud AI Upload', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 8),
                      Text(_uploadStatus, style: const TextStyle(color: Colors.blue)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInboxView() {
    final cloud = context.read<CloudProvider>();
    final auth = context.read<AuthService>();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: cloud.getAdminInbox(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final messages = snapshot.data ?? [];

        if (messages.isEmpty) return const Center(child: Text('No messages yet.'));

        return ListView.builder(
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final msg = messages[index];
            final date = (msg['timestamp'] as dynamic)?.toDate() ?? DateTime.now();
            final reply = msg['reply'] as String?;
            final replyController = TextEditingController();

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(msg['sender_email'] ?? 'Anonymous', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(DateFormat('MMM d, HH:mm').format(date), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(msg['message'] ?? ''),
                    const Divider(height: 24),
                    if (reply != null) ...[
                      const Text('Admin Reply:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 12)),
                      Text(reply, style: const TextStyle(fontStyle: FontStyle.italic)),
                      const SizedBox(height: 4),
                      Text('By ${msg['replied_by']} on ${DateFormat('MMM d, HH:mm').format((msg['replied_at'] as dynamic).toDate())}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(child: TextField(controller: replyController, decoration: const InputDecoration(hintText: 'Type reply...', isDense: true))),
                          IconButton(
                            onPressed: () async {
                              if (replyController.text.trim().isEmpty) return;
                              await cloud.replyToMessage(msg['id'], auth.user!.email!, replyController.text.trim());
                              setState(() {});
                            },
                            icon: const Icon(Icons.send, color: Colors.blue),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
