import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_page.dart';
import 'home_page.dart';
import 'category_helper.dart'; // NEW: Import the helper file

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  String selectedCurrency = 'MYR'; // default currency code

  final TextEditingController _currencySearchController = TextEditingController();

  final List<Map<String, String>> _currencies = [
    {'name': 'Malaysian Ringgit',              'code': 'MYR'},
    {'name': 'US Dollar',                       'code': 'USD'},
    {'name': 'Euro',                            'code': 'EUR'},
    {'name': 'British Pound',                   'code': 'GBP'},
    {'name': 'Japanese Yen',                    'code': 'JPY'},
    {'name': 'Australian Dollar',               'code': 'AUD'},
    {'name': 'Canadian Dollar',                 'code': 'CAD'},
    {'name': 'Swiss Franc',                     'code': 'CHF'},
    {'name': 'Chinese Yuan',                    'code': 'CNY'},
    {'name': 'Indian Rupee',                    'code': 'INR'},
    {'name': 'Singapore Dollar',                'code': 'SGD'},
    {'name': 'United Arab Emirates Dirham',     'code': 'AED'},
    {'name': 'Afghan Afghani',                  'code': 'AFN'},
  ];

  List<Map<String, String>> get _filteredCurrencies {
    final query = _currencySearchController.text.toLowerCase();
    if (query.isEmpty) return _currencies;
    return _currencies.where((c) =>
      c['name']!.toLowerCase().contains(query) ||
      c['code']!.toLowerCase().contains(query)
    ).toList();
  }

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    _currencySearchController.dispose();
    super.dispose();
  }

  void _showCurrencySheet() {
    _currencySearchController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text(
                      'CURRENCY',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _currencySearchController,
                  decoration: InputDecoration(
                    hintText: 'Search',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                  ),
                  onChanged: (_) => setSheetState(() {}),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _filteredCurrencies.length,
                  itemBuilder: (context, index) {
                    final currency = _filteredCurrencies[index];
                    final isSelected = selectedCurrency == currency['code'];
                    return ListTile(
                      title: Text(
                        currency['name']!,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? const Color(0xFF6378A0) : Colors.black,
                        ),
                      ),
                      subtitle: Text(
                        currency['code']!,
                        style: TextStyle(
                          color: isSelected ? const Color(0xFF6378A0) : Colors.grey,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Color(0xFF6378A0))
                          : null,
                      onTap: () {
                        setState(() => selectedCurrency = currency['code']!);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool isLoading = false;

  // Password validation
  String? validatePassword(String password) {
    if (password.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Password must contain at least 1 uppercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must contain at least 1 number';
    }
    if (!RegExp(r'[!@#\$&*~]').hasMatch(password)) {
      return 'Password must contain at least 1 special character (!@#\$&*~)';
    }
    return null;
  }

  Future<void> signUp() async {
    String username = usernameController.text.trim();
    String email = emailController.text.trim();
    String password = passwordController.text.trim();
    String confirmPassword = confirmPasswordController.text.trim();

    // Basic validation
    if (username.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passwords do not match')));
      return;
    }

    String? passwordError = validatePassword(password);
    if (passwordError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(passwordError)));
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // Create user with email & password
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Store extra data in Firestore
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'username': username,
        'email': email,
        'currency': selectedCurrency,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // NEW: Create default categories and income sources for the new user! 🎉
      await createDefaultCategoriesAndSources(userCredential.user!.uid);

      // Navigate to HomePage
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomePage()));
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Sign Up Failed: ${e.message}')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() {
        isLoading = false;
      });
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
                  'Welcome\nfirst timer to',
                  style: TextStyle(fontSize: 18, color: Colors.black),
                  textAlign: TextAlign.center,
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

                // Blue Box
                Container(
                  width: screenWidth,
                  padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                  decoration: const BoxDecoration(
                    color: Color(0xFF6378A0),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                      bottomLeft: Radius.circular(0),
                      bottomRight: Radius.circular(0),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Logo
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.blueGrey, width: 6),
                          gradient: const SweepGradient(
                            colors: [
                              Color(0xFF4DA8DA),
                              Color(0xFFF497B0),
                              Color(0xFFF9C762),
                            ],
                            stops: [0.35, 0.55, 1.0],
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            '\$',
                            style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFB58D32)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Sign Up',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                      const SizedBox(height: 20),

                      // Username
                      TextField(
                        controller: usernameController,
                        decoration: InputDecoration(
                          hintText: 'Username',
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

                      // Email
                      TextField(
                        controller: emailController,
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
                      const SizedBox(height: 12),

                      // Confirm Password
                      TextField(
                        controller: confirmPasswordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: 'Confirm Password',
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

                      // Choose Currency
                      GestureDetector(
                        onTap: _showCurrencySheet,
                        child: Container(
                          width: double.infinity,
                          height: 55,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFB4D4FF),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                () {
                                  final match = _currencies.firstWhere(
                                    (c) => c['code'] == selectedCurrency,
                                    orElse: () => {'name': selectedCurrency, 'code': selectedCurrency},
                                  );
                                  return '${match['code']} — ${match['name']}';
                                }(),
                                style: const TextStyle(fontSize: 15, color: Colors.black87),
                              ),
                              const Icon(Icons.arrow_drop_down, color: Colors.black54),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Sign Up Button
                      SizedBox(
                        width: screenWidth * 0.5,
                        height: 45,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : signUp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            side: const BorderSide(color: Colors.white, width: 3),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(40)),
                          ),
                          child: isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text(
                                  'Sign Up',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Back to Login link inside blue box
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginPage()),
                          );
                        },
                        child: const Text(
                          'Already have an account? Log In',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
