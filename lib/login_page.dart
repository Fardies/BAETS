import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lottie/lottie.dart';
import 'home_page.dart';
import 'signup_page.dart';
import 'forgot_password_page.dart';
import 'admin_dashboard_page.dart';
import 'admin_auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final AdminAuthService _adminAuthService = AdminAuthService();
  bool _isLoading = false;

  Future<void> login() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email and password')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Check if admin email — use AdminAuthService so activity is logged
      if (email.toLowerCase().endsWith('@baets.com')) {
        final user = await _adminAuthService.signInAdmin(email, password);
        if (user != null && mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AdminDashboardPage()),
          );
        }
      } else {
        // Regular user login
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomePage()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String message = 'Login failed. Please check your credentials';
        final err = e.toString();
        if (err.contains('user-not-found'))       message = 'No account found for this email';
        if (err.contains('wrong-password'))        message = 'Incorrect password';
        if (err.contains('invalid-email'))         message = 'Invalid email format';
        if (err.contains('too-many-requests'))     message = 'Too many attempts. Try again later';
        if (err.contains('Only @baets.com'))       message = 'Admin access requires a @baets.com email';

        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFEEF5F6),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text(
                  'Welcome To',
                  style: TextStyle(fontSize: 18, color: Colors.black),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Budget Analyzer And\nExpense Tracker App',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                Stack(
                  alignment: Alignment.topCenter,
                  clipBehavior: Clip.none,
                  children: [
                    // Blue Box
                    Container(
                      width: screenWidth,
                      padding: const EdgeInsets.symmetric(
                          vertical: 20, horizontal: 20),
                      decoration: const BoxDecoration(
                        color: Color(0xFF6378A0),
                      ),
                      child: Column(
                        children: [
                          Lottie.asset(
                            'assets/animations/Wallet animation.json',
                            width: 180,
                            height: 180,
                            fit: BoxFit.contain,
                            repeat: true,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Log in',
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                          const SizedBox(height: 15),

                          // Email
                          TextField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              hintText: 'Email',
                              filled: true,
                              fillColor: const Color(0xFFB4D4FF),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 20),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(50),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Password
                          TextField(
                            controller: passwordController,
                            obscureText: true,
                            decoration: InputDecoration(
                              hintText: 'Password',
                              filled: true,
                              fillColor: const Color(0xFFB4D4FF),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 20),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(50),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Login Button
                          SizedBox(
                            width: screenWidth * 0.5,
                            height: 45,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF6378A0),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(40)),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                            Color(0xFF6378A0)),
                                      ),
                                    )
                                  : const Text(
                                      'Login',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),

                    // Forgot Password Button
                    Positioned(
                      bottom: -20,
                      child: SizedBox(
                        width: screenWidth,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ForgotPasswordPage()),
                            );
                          },
                          borderRadius: BorderRadius.circular(30),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF9ABDBD),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                // Sign Up Button
                SizedBox(
                  width: screenWidth * 0.5,
                  height: 45,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignUpPage()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6378A0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(40),
                      ),
                    ),
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}