import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';


class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _showMessage('Please enter your email');
      return;
    }

    // Basic email format check
    if (!email.contains('@') || !email.contains('.')) {
      _showMessage('Please enter a valid email address');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      setState(() => _isLoading = false);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Email Sent'),
          content: const Text(
            'A password reset link has been sent to your email.\n\n'
            'The link is valid for 1 hour. '
            'Please also check your spam or junk folder.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // back to login
              },
              child: const Text('Back to Login'),
            ),
          ],
        ),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      switch (e.code) {
        case 'invalid-email':
          _showMessage('The email address is not valid.');
          break;
        case 'user-not-found':
          // Still show success — don't reveal whether email exists
          _showMessage('If this email is registered, a reset link has been sent.');
          break;
        case 'too-many-requests':
          _showMessage('Too many attempts. Please wait a moment and try again.');
          break;
        case 'network-request-failed':
          _showMessage('No internet connection. Please check your network.');
          break;
        default:
          _showMessage('Something went wrong (${e.code}). Please try again.');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showMessage('Unexpected error. Please try again.');
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9F1F4),
      body: SafeArea(
        child: Column(
          children: [
            // ===== Top Navbar =====
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: const Color(0xFF4B6584),
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            // ===== Content =====
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Enter your email and we will send you a password reset link',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 25),

                      // Email input
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          hintText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Reset button
                      SizedBox(
                        width: 180,
                        height: 42,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _resetPassword,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF778CA3),
                            foregroundColor: Colors.white,
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Reset Password'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ===== Home indicator =====
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              width: 120,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ],
        ),
      ),
    ); 
  }
}