import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';

class UserMessagesScreen extends StatelessWidget {
  const UserMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    if (auth.isGuest) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Messages')),
        body: const Center(child: Text('Please log in to view your messages.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Messages'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('messages')
            .where('sender_uid', isEqualTo: auth.user!.uid)
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final messages = snapshot.data?.docs ?? [];

          if (messages.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.message_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No messages sent yet.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index].data() as Map<String, dynamic>;
              final date = (msg['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
              final reply = msg['reply'] as String?;
              final replyAt = msg['replied_at'] as Timestamp?;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Your Message', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          Text(
                            DateFormat('MMM d, HH:mm').format(date),
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(msg['message'] ?? ''),
                      if (reply != null) ...[
                        const Divider(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Admin Reply', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                            if (replyAt != null)
                              Text(
                                DateFormat('MMM d, HH:mm').format(replyAt.toDate()),
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          reply,
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ] else ...[
                        const Divider(height: 32),
                        const Row(
                          children: [
                            Icon(Icons.hourglass_empty, size: 14, color: Colors.orange),
                            SizedBox(width: 8),
                            Text(
                              'Waiting for admin reply...',
                              style: TextStyle(fontSize: 12, color: Colors.orange, fontStyle: FontStyle.italic),
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
      ),
    );
  }
}
