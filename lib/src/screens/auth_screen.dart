import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  bool _showCodeInput = false;

  late final AuthService _authService;

  @override
  void initState() {
    super.initState();
    _authService = AuthService(
      apiPublicKey:
          '02c9dd668f35e75bb4959b7fdd639705323062d902d3e8b9e9cf89ad4df8fa7e58',
      apiPrivateKey:
          '20df957b14684ba0ae2053b5d829903f9fbd39eeb3722d150806c46f21af651c',
      organizationId: 'your_organization_id', // Replace with your org ID
    );
  }

  Future<void> _startEmailAuth() async {
    if (_emailController.text.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.startEmailAuth(_emailController.text);
      setState(() {
        _showCodeInput = true;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _completeAuth() async {
    if (_codeController.text.isEmpty || _nameController.text.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _authService.completeEmailAuthAndCreateSubOrg(
        email: _emailController.text,
        code: _codeController.text,
        userName: _nameController.text,
      );

      // Handle successful authentication and sub-org creation
      print('Authentication successful: $result');

      // Navigate to next screen or show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully authenticated!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    _authService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Email Authentication'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'Enter your email',
              ),
              keyboardType: TextInputType.emailAddress,
              enabled: !_showCodeInput && !_isLoading,
            ),
            const SizedBox(height: 16),
            if (!_showCodeInput)
              ElevatedButton(
                onPressed: _isLoading ? null : _startEmailAuth,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Send Code'),
              ),
            if (_showCodeInput) ...[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Enter your name',
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'Verification Code',
                  hintText: 'Enter the code sent to your email',
                ),
                keyboardType: TextInputType.number,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _completeAuth,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Verify & Create Organization'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
