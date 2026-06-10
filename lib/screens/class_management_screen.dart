import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/quiz_provider.dart';
import '../services/auth_service.dart';
import 'manual_import_screen.dart';
import 'content_management_screen.dart';

class ClassManagementScreen extends StatefulWidget {
  const ClassManagementScreen({super.key});

  @override
  State<ClassManagementScreen> createState() => _ClassManagementScreenState();
}

class _ClassManagementScreenState extends State<ClassManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<QuizProvider>(context, listen: false).loadClasses();
    });
  }

  Future<void> _addClass() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Class'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Class Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      if (mounted) {
        await Provider.of<QuizProvider>(context, listen: false).addClass(name);
      }
    }
  }

  Future<void> _pickAndUploadPdf(int classId) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      final fileName = result.files.single.name;
      final Uint8List bytes = result.files.single.bytes ?? await File(result.files.single.path!).readAsBytes();
      
      if (mounted) {
        try {
          await Provider.of<QuizProvider>(context, listen: false)
              .uploadPdf(classId, bytes, fileName);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PDF uploaded and processed successfully')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userRole = context.watch<AuthService>().role;
    final bool isGuest = userRole == UserRole.guest;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Classes'),
      ),
      body: Consumer<QuizProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.classes.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.classes.isEmpty) {
            return const Center(child: Text('No classes found. Add one!'));
          }

          return Stack(
            children: [
              ListView.builder(
                itemCount: provider.classes.length,
                itemBuilder: (context, index) {
                  final cls = provider.classes[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ContentManagementScreen(
                              classId: cls['id'],
                              className: cls['name'],
                            ),
                          ),
                        );
                      },
                      title: Text(cls['name']),
                      subtitle: Text('Created: ${cls['created_at'].toString().split('T')[0]}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.list_alt),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ContentManagementScreen(
                                    classId: cls['id'],
                                    className: cls['name'],
                                  ),
                                ),
                              );
                            },
                            tooltip: 'View Questions / Answer Key',
                          ),
                          if (!isGuest)
                            IconButton(
                              icon: const Icon(Icons.upload_file),
                              onPressed: () => _pickAndUploadPdf(cls['id']),
                              tooltip: 'Upload PDF (AI Auto)',
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit_note),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ManualImportScreen(
                                    classId: cls['id'],
                                    className: cls['name'],
                                  ),
                                ),
                              );
                            },
                            tooltip: isGuest ? 'Import Questions (Manual)' : 'Manual Import',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => provider.removeClass(cls['id']),
                            tooltip: 'Delete Class',
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              if (provider.isLoading)
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
                            const Text('AI Processing PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            const SizedBox(height: 8),
                            Text(provider.loadingStatus, style: const TextStyle(color: Colors.blue)),
                            const SizedBox(height: 16),
                            const Text('Please wait, this may take a minute...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addClass,
        child: const Icon(Icons.add),
      ),
    );
  }
}
