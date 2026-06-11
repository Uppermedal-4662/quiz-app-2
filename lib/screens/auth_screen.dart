import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/cloud_provider.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  Map<String, dynamic> _config = {};

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await context.read<CloudProvider>().getAppConfig();
      if (mounted) setState(() => _config = config);
    } catch (e) {
      debugPrint('Error loading app config: $e');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final auth = context.read<AuthService>();

    try {
      if (_isLogin) {
        await auth.signIn(_emailController.text.trim(), _passwordController.text.trim());
      } else {
        await auth.signUp(_emailController.text.trim(), _passwordController.text.trim());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    // Show force logout reason if exists
    if (auth.logoutReason != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(auth.logoutReason!),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        auth.clearLogoutReason();
      });
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.quiz, size: 80, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                'Quiz AI Cloud',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              if (_config['greeting_message'] != null && _config['greeting_message'].isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _config['greeting_message'],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.blueGrey, fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 48),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) => value!.contains('@') ? null : 'Invalid email',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                      obscureText: true,
                      validator: (value) => value!.length >= 6 ? null : 'Password too short',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : Text(_isLogin ? 'LOGIN' : 'SIGN UP'),
              ),
              TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(_isLogin ? 'Create an account' : 'Already have an account? Login'),
              ),
              const Divider(height: 48),
              OutlinedButton(
                onPressed: () => context.read<AuthService>().continueAsGuest(),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
                child: const Text('CONTINUE AS GUEST'),
              ),
              if (_config['contact_info'] != null && _config['contact_info'].isNotEmpty) ...[
                const SizedBox(height: 32),
                Text(
                  'Support & Contact:',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600]),
                ),
                Text(
                  _config['contact_info'],
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
