import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'budget_helper.dart';
import 'category_helper.dart';

class AddBudgetPage extends StatefulWidget {
  const AddBudgetPage({super.key});

  @override
  State<AddBudgetPage> createState() => _AddBudgetPageState();
}

class _AddBudgetPageState extends State<AddBudgetPage> {
  bool showNumberPad = false;

  String budgetLimit = '0.00';
  String? selectedCategoryId;
  String selectedDuration = 'Monthly';

  // User's currency
  String _currencySymbol = 'RM';
  String _currencyCode   = 'MYR';

  // Fetched categories
  List<Map<String, dynamic>> expenseCategories = [];
  bool isLoadingCategories = true;

  // Icon/color lookup now comes from category_helper.dart's centralized
  // getCategoryIconColor() instead of this local map.

  @override
  void initState() {
    super.initState();
    _loadUserPreferences();
    _loadCategories();
  }

  Future<void> _loadUserPreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        setState(() {
          _currencyCode   = data['currency'] ?? 'MYR';
          _currencySymbol = _getCurrencySymbol(_currencyCode);
        });
      }
    } catch (e) {
      print('Error loading preferences: $e');
    }
  }

  String _getCurrencySymbol(String code) {
    const symbols = {
      'MYR': 'RM', 'USD': '\$', 'EUR': '€', 'GBP': '£',
      'JPY': '¥', 'AUD': 'A\$', 'CAD': 'C\$', 'SGD': 'S\$', 'INR': '₹',
    };
    return symbols[code] ?? code;
  }

  Future<void> _loadCategories() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final categories = await fetchExpenseCategories(user.uid);

      setState(() {
        expenseCategories = categories;
        isLoadingCategories = false;

        // Set first category as selected
        if (expenseCategories.isNotEmpty) {
          selectedCategoryId = expenseCategories[0]['id'];
        }
      });
    } catch (e) {
      print('Error loading categories: $e');
      setState(() => isLoadingCategories = false);
    }
  }

  Map<String, dynamic> _getIconColor(String name) {
    return getCategoryIconColor(name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EEF1),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'New Budget',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton(
              onPressed: _saveBudget,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A6B7C),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text(
                'Save',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: isLoadingCategories
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _budgetLimitDisplay(),
                        const SizedBox(height: 30),
                        _categoryField(),
                        const SizedBox(height: 24),
                        _durationSelector(),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  alignment: Alignment.bottomCenter,
                  child: showNumberPad
                      ? _numberPad()
                      : const SizedBox(width: double.infinity, height: 0),
                ),
              ],
            ),
    );
  }

  Widget _budgetLimitDisplay() {
    final bool isActive = showNumberPad;
    final bool isEmpty = budgetLimit == '0.00';

    return GestureDetector(
      onTap: () {
        setState(() {
          showNumberPad = true;
          FocusScope.of(context).unfocus();
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? Colors.blue : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              'Budget Limit',
              style: TextStyle(
                fontSize: 13,
                color: isActive ? Colors.blue : Colors.grey[500],
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '$_currencySymbol $budgetLimit',
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.bold,
                color: isEmpty ? Colors.grey[400] : const Color(0xFF4A6B7C),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 2,
              width: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF4A6B7C).withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap to enter amount',
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryField() {
    if (selectedCategoryId == null || expenseCategories.isEmpty) {
      return Container();
    }

    final category = expenseCategories.firstWhere(
      (c) => c['id'] == selectedCategoryId,
      orElse: () => expenseCategories[0],
    );
    final iconColor = _getIconColor(category['name']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Category',
          style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            setState(() => showNumberPad = false);
            _showCategorySelector();
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (iconColor['color'] as Color).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    iconColor['icon'],
                    color: iconColor['color'],
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    category['name'],
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.keyboard_arrow_down, color: Colors.grey[600], size: 20),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showCategorySelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Color(0xFFE8EEF1),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
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
                    'SELECT CATEGORY',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: expenseCategories.length + 1, // +1 for "Add New"
                itemBuilder: (context, index) {
                  // "Add New" tile — last in grid
                  if (index == expenseCategories.length) {
                    return GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        _showAddCategoryDialog();
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.grey[400]!, width: 2, style: BorderStyle.solid),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_outline, size: 40, color: Colors.grey[700]),
                            const SizedBox(height: 8),
                            Text(
                              'Add New',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Regular category tile
                  final category = expenseCategories[index];
                  final iconColor = _getIconColor(category['name']);
                  final isSelected = selectedCategoryId == category['id'];

                  return GestureDetector(
                    onTap: () {
                      setState(() => selectedCategoryId = category['id']);
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (iconColor['color'] as Color).withOpacity(0.2)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? iconColor['color'] as Color : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(iconColor['icon'], size: 40, color: iconColor['color']),
                          const SizedBox(height: 8),
                          Text(
                            category['name'],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCategoryDialog() {
    final TextEditingController categoryNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Add Category',
          style: TextStyle(color: Color(0xFF4A6B7C), fontSize: 16),
        ),
        content: TextField(
          controller: categoryNameController,
          decoration: InputDecoration(
            hintText: 'Enter name',
            hintStyle: TextStyle(color: Colors.grey[400]),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: const Color(0xFF4A6B7C).withOpacity(0.3)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF4A6B7C)),
            ),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A6B7C),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final name = categoryNameController.text.trim();
              if (name.isNotEmpty) {
                await _addNewCategory(name);
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addNewCategory(String name) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final docRef = await FirebaseFirestore.instance
          .collection('expenseCategories')
          .add({
        'userID': user.uid,
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        expenseCategories.add({'id': docRef.id, 'name': name});
        selectedCategoryId = docRef.id; // auto-select new category
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Category "$name" added'),
            backgroundColor: const Color(0xFF4A6B7C),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to add category'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _durationSelector() {
    final durations = ['Weekly', 'Monthly', 'Yearly'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Duration',
          style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: durations.map((duration) {
              final isSelected = selectedDuration == duration;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedDuration = duration;
                      showNumberPad = false;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.all(4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF4A6B7C) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      duration,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _numberPad() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle + tap-to-dismiss row
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => showNumberPad = false),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down, color: Colors.grey[500], size: 20),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                for (int row = 0; row < 4; row++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        for (int col = 0; col < 3; col++) ...[
                          _buildNumberButton(row, col),
                          if (col < 2) const SizedBox(width: 10),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberButton(int row, int col) {
    const List<List<String>> layout = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['00', '0', '⌫'],
    ];

    final String key = layout[row][col];

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            // Cents shift in from the right — same as the transfer-style
            // amount entry in add_transaction_page.dart.
            int cents = ((double.tryParse(budgetLimit) ?? 0.0) * 100).round();

            if (key == '⌫') {
              cents = cents ~/ 10;
            } else if (key == '00') {
              final next = cents * 100;
              if (next <= 99999999) cents = next;
            } else {
              final next = cents * 10 + int.parse(key);
              if (next <= 99999999) cents = next;
            }

            budgetLimit = (cents / 100).toStringAsFixed(2);
          });
        },
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F6F7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            key,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveBudget() async {
    // Dismiss number pad first
    setState(() => showNumberPad = false);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final double limitValue = double.tryParse(budgetLimit) ?? 0.0;

    // Validation
    if (limitValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a budget limit')),
      );
      return;
    }

    if (selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    // Check for duplicate (same category + same duration)
    final existingBudgets = await fetchBudgets(
      userId: user.uid,
      durationType: selectedDuration,
    );

    // Find if budget already exists for this category
    final existingBudget = existingBudgets.firstWhere(
      (b) => b['categoryID'] == selectedCategoryId,
      orElse: () => {},
    );

    if (existingBudget.isNotEmpty) {
      // Budget exists - ask to update
      final categoryName = expenseCategories.firstWhere(
        (c) => c['id'] == selectedCategoryId,
        orElse: () => {'name': 'this category'},
      )['name'];

      final shouldUpdate = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Budget Already Exists'),
          content: Text(
            'You already have a $selectedDuration budget for $categoryName '
            '(${_currencySymbol} ${existingBudget['budgetLimit'].toStringAsFixed(2)}).\n\n'
            'Would you like to update it to ${_currencySymbol} ${limitValue.toStringAsFixed(2)}?\n\n'
            'Note: Your spending history will remain unchanged.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Update'),
            ),
          ],
        ),
      );

      if (shouldUpdate == true) {
        // Update existing budget
        final success = await updateBudget(
          budgetId: existingBudget['id'],
          budgetLimit: limitValue,
        );

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Budget updated successfully!')),
          );
          Navigator.pop(context); // Go back to budget page
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to update budget')),
          );
        }
      }
    } else {
      // No duplicate - create new budget
      final budgetId = await createBudget(
        userId: user.uid,
        categoryId: selectedCategoryId!,
        budgetLimit: limitValue,
        durationType: selectedDuration,
        originalBudgetLimit: limitValue,
        originalCurrency: _currencyCode,
      );

      if (budgetId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Budget created successfully!')),
        );
        Navigator.pop(context); // Go back to budget page
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create budget')),
        );
      }
    }
  }
}