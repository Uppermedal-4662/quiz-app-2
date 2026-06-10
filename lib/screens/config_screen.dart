import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _apiKeyController = TextEditingController();
  String? _selectedModel;
  bool _isFetchingModels = false;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<QuizProvider>(context, listen: false);
    _apiKeyController.text = provider.apiKey ?? '';
    _selectedModel = provider.modelName;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _fetchModels() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an API key first')),
      );
      return;
    }

    setState(() {
      _isFetchingModels = true;
    });

    final provider = Provider.of<QuizProvider>(context, listen: false);
    await provider.saveApiKey(apiKey);
    await provider.fetchAvailableModels();

    if (mounted) {
      setState(() {
        _isFetchingModels = false;
        _selectedModel = provider.modelName;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Models fetched successfully')),
      );
    }
  }

  Future<void> _saveSettings() async {
    final provider = Provider.of<QuizProvider>(context, listen: false);
    await provider.saveApiKey(_apiKeyController.text.trim());
    if (_selectedModel != null) {
      await provider.saveModelName(_selectedModel!);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuration'),
      ),
      body: Consumer<QuizProvider>(
        builder: (context, provider, child) {
          // Sync selected model if it's not set yet or provider changed it
          if (_selectedModel == null || (!provider.availableModels.contains(_selectedModel) && provider.availableModels.isNotEmpty)) {
             _selectedModel = provider.modelName;
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Gemini API Key',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _apiKeyController,
                        decoration: const InputDecoration(
                          hintText: 'Enter your Gemini API key',
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: _isFetchingModels
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      onPressed: _isFetchingModels ? null : _fetchModels,
                      tooltip: 'Fetch Available Models',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Gemini Model',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_isFetchingModels)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Fetching models...', style: TextStyle(color: Colors.blue)),
                        ],
                      ),
                    ),
                  )
                else if (provider.availableModels.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: const Text(
                      'No models available. Please enter a valid API key and tap the refresh icon.',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: provider.availableModels.contains(_selectedModel) ? _selectedModel : provider.availableModels.first,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    isExpanded: true,
                    items: provider.availableModels.map((String model) {
                      return DropdownMenuItem<String>(
                        value: model,
                        child: Text(
                          model.replaceFirst('models/', ''),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedModel = newValue;
                        });
                      }
                    },
                  ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _saveSettings,
                  child: const Text('Save Settings'),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Your settings are stored securely.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
