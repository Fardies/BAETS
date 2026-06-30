import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'category_helper.dart';
import 'budget_helper.dart';
import 'dart:io';
import 'gemini_receipt_scanner.dart';
import 'scan_receipt_button.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'currency_service.dart';

class AddTransactionPage extends StatefulWidget {
  const AddTransactionPage({super.key}); 

  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  bool showNumberPad = false;
  bool isExpense = true;

  // Cap for the bank-transfer-style cents entry below (999,999.99 max).
  static const int _maxAmountCents = 99999999;

  String amount = '0.00';
  String? selectedCategoryId;
  String? selectedSourceId;
  DateTime selectedDate = DateTime.now();

  String _currencyCode = 'MYR';
  String _currencySymbol = 'RM';

  final TextEditingController descriptionController = TextEditingController();

  List<Map<String, dynamic>> expenseCategories = [];
  List<Map<String, dynamic>> incomeSources = [];
  bool isLoadingCategories = true;

  // AI Receipt scanning
  final GeminiReceiptScanner _receiptScanner = GeminiReceiptScanner();
  bool _isScanning = false;

  // Track the TRUE original — pre-conversion amount from the receipt
  // If no conversion happened, these stay null and we use amount/_currencyCode
  String? _preConversionAmount;
  String? _preConversionCurrency;
  
  // AI extraction flags (invisible to user unless scanning)
  bool _hasScanned = false;
  bool _amountExtracted = false;
  bool _categoryExtracted = false;
  bool _dateExtracted = false;
  bool _descriptionExtracted = false;

  // Icon/color lookup now comes from category_helper.dart's centralized
  // getCategoryIconColor()/getIncomeIconColor() instead of this local map
  // (which mixed expense categories and income sources together, and had
  // drifted out of sync — 'Healthcare' vs 'Health & Medical', 'Others' vs
  // 'Other' — from the version used elsewhere in the app).


  @override
  void initState() {
    super.initState();
    _loadUserCurrency();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final categories = await fetchExpenseCategories(user.uid);
      final sources = await fetchIncomeSources(user.uid);

      setState(() {
        expenseCategories = categories;
        incomeSources = sources;
        isLoadingCategories = false;

        if (expenseCategories.isNotEmpty) {
          selectedCategoryId = expenseCategories[0]['id'];
        }
        if (incomeSources.isNotEmpty) {
          selectedSourceId = incomeSources[0]['id'];
        }
      });
    } catch (e) {
      print('Error loading categories: $e');
      setState(() => isLoadingCategories = false);
    }
  }

  Future<void> _loadUserCurrency() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (doc.exists && doc.data() != null) {
          final currency = doc.data()!['currency'] ?? 'MYR';
          setState(() {
            _currencyCode = currency;
            _currencySymbol = _getCurrencySymbol(currency);
          });
        }
      } catch (e) {
        print('Error loading currency: $e');
      }
    }
  }

  String _getCurrencySymbol(String code) {
    final Map<String, String> currencySymbols = {
      'MYR': 'RM',
      'USD': '\$',
      'EUR': '€',
      'GBP': '£',
      'JPY': '¥',
      'AUD': 'A\$',
      'CAD': 'C\$',
      'CHF': 'CHF',
      'CNY': '¥',
      'INR': '₹',
      'SGD': 'S\$',
      'AED': 'AED',
    };
    
    return currencySymbols[code] ?? code;
  }

  @override
  void dispose() {
    descriptionController.dispose();
    _receiptScanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EEF1),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.blue),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'New Transaction',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saveTransaction,
            child: const Text(
              'Save',
              style: TextStyle(
                color: Colors.blue,
                fontSize: 16,
                fontWeight: FontWeight.bold,
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
                      children: [
                        _transactionTypeToggle(),
                        const SizedBox(height: 30),
                        _amountDisplay(),
                        const SizedBox(height: 30),
                        isExpense ? _categoryField() : _typeField(),
                        const SizedBox(height: 24),
                        _dateField(),
                        const SizedBox(height: 24),
                        _descriptionField(),
                        const SizedBox(height: 24),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 0),
                          child: Divider(color: Colors.grey),
                        ),
                        // Scan Receipt - Only for Expenses
                        if (isExpense) ...[
                          const SizedBox(height: 16),
                          ScanReceiptButton(
                            onPressed: _showScanSourcePicker,
                            isLoading: _isScanning,
                          ),
                        ],
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

  Widget _transactionTypeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _typeButton('Expense', true),
          _typeButton('Income', false),
        ],
      ),
    );
  }

  Widget _typeButton(String text, bool isExpenseButton) {
    bool isSelected = isExpenseButton == isExpense;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => isExpense = isExpenseButton),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 4)]
                : [],
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.blue : Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _amountDisplay() {
    final bool isActive = showNumberPad;
    final bool isEmpty = amount == '0.00';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Text(
            'Amount',
            style: TextStyle(
              color: isActive ? Colors.blue : Colors.grey,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              // Dismiss the system keyboard first (e.g. if the description
              // field was focused) — otherwise both the OS keyboard and the
              // custom numpad end up stacked on top of each other.
              FocusScope.of(context).unfocus();
              setState(() {
                showNumberPad = !showNumberPad;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? Colors.blue : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _currencySymbol,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: isEmpty ? Colors.grey[400] : Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    amount,
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: isEmpty ? Colors.grey[400] : Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // AI indicator (only shows after scanning)
                  if (_hasScanned && _amountExtracted)
                    const Icon(Icons.check_circle, color: Colors.green, size: 20)
                  else if (_hasScanned && !_amountExtracted && amount != '0.00')
                    const Icon(Icons.warning, color: Colors.orange, size: 20),
                ],
              ),
            ),
          ),
        ],
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
    final iconColor = getCategoryIconColor(category['name']);

    return GestureDetector(
      onTap: () {
        setState(() => showNumberPad = false);
        _showCategorySelector();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF4A6B7C).withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                iconColor['icon'],
                color: iconColor['color'],
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                category['name'],
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: Colors.grey[600]),
            // AI indicator (only shows after scanning)
            if (_hasScanned && _categoryExtracted)
              Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.check_circle, color: Colors.green, size: 16),
              )
            else if (_hasScanned && !_categoryExtracted)
              Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.warning, color: Colors.orange, size: 16),
              ),
          ],
        ),
      ),
    );
  }

  Widget _typeField() {
    if (selectedSourceId == null || incomeSources.isEmpty) {
      return Container();
    }

    final selectedSource = incomeSources.firstWhere(
      (source) => source['id'] == selectedSourceId,
      orElse: () => incomeSources[0],
    );
    final iconColor = getIncomeIconColor(selectedSource['name']);

    return GestureDetector(
      onTap: () {
        setState(() => showNumberPad = false);
        _showIncomeSourceSelector();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF4A6B7C).withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                iconColor['icon'],
                color: iconColor['color'],
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                selectedSource['name'],
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }

  void _showIncomeSourceSelector() {
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
                    'INCOME SOURCE',
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
                itemCount: incomeSources.length + 1, // +1 for "Add New"
                itemBuilder: (context, index) {
                  // "+ Add New" tile
                  if (index == incomeSources.length) {
                    return GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        _showAddIncomeSourceDialog();
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[400]!, width: 2, style: BorderStyle.solid),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_outline, size: 40, color: Colors.grey[700]),
                            const SizedBox(height: 8),
                            Text(
                              'Add New',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Regular income source tile
                  final source = incomeSources[index];
                  final iconColor = getIncomeIconColor(source['name']);
                  final isSelected = selectedSourceId == source['id'];
                  
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedSourceId = source['id'];
                      });
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? iconColor['color'].withOpacity(0.2) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? iconColor['color'] : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            iconColor['icon'],
                            size: 40,
                            color: iconColor['color'],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            source['name'],
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

  Future<void> _addNewCategory(String name) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final docRef = await FirebaseFirestore.instance.collection('expenseCategories').add({
        'userID': user.uid,
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Add to local list
      setState(() {
        expenseCategories.add({
          'id': docRef.id,
          'name': name,
        });
        selectedCategoryId = docRef.id; // Auto-select the new category
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
            content: Text('Failed to add category'),
            backgroundColor: Colors.red[400],
          ),
        );
      }
    }
  }

  void _showAddCategoryDialog() {
    final TextEditingController categoryNameController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          'Add Category',
          style: TextStyle(color: const Color(0xFF4A6B7C), fontSize: 16),
        ),
        content: TextField(
          controller: categoryNameController,
          decoration: InputDecoration(
            hintText: 'Enter name',
            hintStyle: TextStyle(color: Colors.grey[400]),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: const Color(0xFF4A6B7C).withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: const Color(0xFF4A6B7C)),
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
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showAddIncomeSourceDialog() {
    final TextEditingController sourceNameController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          'Add Income Source',
          style: TextStyle(color: const Color(0xFF4A6B7C), fontSize: 16),
        ),
        content: TextField(
          controller: sourceNameController,
          decoration: InputDecoration(
            hintText: 'Enter name',
            hintStyle: TextStyle(color: Colors.grey[400]),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: const Color(0xFF4A6B7C).withOpacity(0.3)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: const Color(0xFF4A6B7C)),
            ),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          TextButton(
            onPressed: () async {
              final name = sourceNameController.text.trim();
              if (name.isNotEmpty) {
                await _addNewIncomeSource(name);
                Navigator.pop(context);
              }
            },
            child: Text('Add', style: TextStyle(color: const Color(0xFF4A6B7C))),
          ),
        ],
      ),
    );
  }

  Future<void> _addNewIncomeSource(String name) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Try 'income_sources' first, if that fails try 'incomeSources'
      final docRef = await FirebaseFirestore.instance.collection('incomeSources').add({
        'userID': user.uid,
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Add to local list
      setState(() {
        incomeSources.add({
          'id': docRef.id,
          'name': name,
        });
        selectedSourceId = docRef.id; // Auto-select the new source
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Income source "$name" added successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Try alternative collection name
      try {
        final docRef = await FirebaseFirestore.instance.collection('income_sources').add({
          'userID': user.uid,
          'name': name,
          'createdAt': FieldValue.serverTimestamp(),
        });

        setState(() {
          incomeSources.add({
            'id': docRef.id,
            'name': name,
          });
          selectedSourceId = docRef.id;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Income source "$name" added successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to add income source'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _dateField() {
    return GestureDetector(
      onTap: () async {
        setState(() => showNumberPad = false);
        DateTime? pickedDate = await showDatePicker(
          context: context,
          initialDate: selectedDate,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (pickedDate != null) {
          setState(() {
            selectedDate    = pickedDate;
            _dateExtracted  = false; // mark as manually overridden
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[400]!),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${selectedDate.day} ${_monthName(selectedDate.month)} ${selectedDate.year}',
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ),
            // Always show edit icon so user knows it's tappable
            // Green check only shows briefly after scan (before they edit)
            if (_hasScanned && _dateExtracted)
              const Icon(Icons.check_circle, color: Colors.green, size: 18)
            else
              Icon(Icons.edit, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _descriptionField() {
    return TextField(
      controller: descriptionController,
      onTap: () {
        setState(() {
          showNumberPad = false;
        });
      },
      decoration: _inputDecoration('Description'),
      onChanged: (value) {
        setState(() {
          if (_hasScanned) {
            _descriptionExtracted = false; // Mark as manually changed
          }
        });
      },
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
                    'CATEGORY',
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
                  // "+ Add New" tile
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
                          border: Border.all(color: Colors.grey[400]!, width: 2, style: BorderStyle.solid),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_outline, size: 40, color: Colors.grey[700]),
                            const SizedBox(height: 8),
                            Text(
                              'Add New',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Regular category tile
                  final category = expenseCategories[index];
                  final iconColor = getCategoryIconColor(category['name']);
                  final isSelected = selectedCategoryId == category['id'];
                  
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedCategoryId = category['id'];
                        if (_hasScanned) {
                          _categoryExtracted = false; // Mark as manually changed
                        }
                      });
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? iconColor['color'].withOpacity(0.2) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? iconColor['color'] : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            iconColor['icon'],
                            size: 40,
                            color: iconColor['color'],
                          ),
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

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April',
      'May', 'June', 'July', 'August',
      'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.grey[100],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
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
          // Drag handle + tap-to-dismiss row — closes the numpad when
          // the user is done typing and doesn't want it open anymore.
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
    final List<List<String>> layout = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['00', '0', '⌫'],
    ];

    final String text = layout[row][col];

    return Expanded(
      child: GestureDetector(
        onTap: () => _onNumberTap(text),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F6F7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            text,
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

  void _onNumberTap(String value) {
    setState(() {
      // Cents shift in from the right — the same way bank-transfer amount
      // fields work. Typing 1, 2, 5, 0 in sequence produces:
      // 0.01 -> 0.12 -> 1.25 -> 12.50
      int cents = ((double.tryParse(amount) ?? 0.0) * 100).round();

      if (value == '⌫') {
        cents = cents ~/ 10;
      } else if (value == '00') {
        final next = cents * 100;
        if (next <= _maxAmountCents) cents = next;
      } else {
        final next = cents * 10 + int.parse(value);
        if (next <= _maxAmountCents) cents = next;
      }

      amount = (cents / 100).toStringAsFixed(2);

      if (_hasScanned) _amountExtracted = false; // mark as manually changed
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
        if (_hasScanned) {
          _dateExtracted = false; // Mark as manually changed
        }
      });
    }
  }

  void _showScanSourcePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 4),
              child: Text(
                'Scan Receipt',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF4A6B7C)),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _scanReceipt(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF4A6B7C)),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _scanReceipt(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _scanReceipt(ImageSource source) async {
    try {
      setState(() => _isScanning = true);
      
      final File? imageFile = await _receiptScanner.captureReceipt(source: source);
      
      if (imageFile == null) {
        setState(() => _isScanning = false);
        return;
      }
      
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Processing receipt...',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.CENTER,
          backgroundColor: Colors.grey[700],
          textColor: Colors.white,
          fontSize: 14.0,
        );
      }
      
      final result = await _receiptScanner.scanReceipt(imageFile);
      
      setState(() => _isScanning = false);
      
      setState(() {
        // Amount — auto-convert if detected currency differs from user's currency
        if (result.amountExtracted && result.amount != null) {
          _amountExtracted = true;
          // Currency conversion is handled async below
        } else {
          amount = '0.00';
          _amountExtracted = false;
        }
        
        // Category
        if (result.categoryExtracted && result.category != null) {
          final matchingCategory = expenseCategories.firstWhere(
            (cat) => cat['name'].toString().toLowerCase() == result.category!.toLowerCase(),
            orElse: () => {},
          );
          
          if (matchingCategory.isNotEmpty) {
            selectedCategoryId = matchingCategory['id'];
            _categoryExtracted = true;
          } else {
            final othersCategory = expenseCategories.firstWhere(
              (cat) => cat['name'].toString().toLowerCase() == 'others',
              orElse: () => {},
            );
            if (othersCategory.isNotEmpty) selectedCategoryId = othersCategory['id'];
            _categoryExtracted = false;
          }
        } else {
          _categoryExtracted = false;
        }
        
        // Date
        if (result.dateExtracted && result.date != null) {
          selectedDate = result.date!;
          _dateExtracted = true;
        } else {
          selectedDate = DateTime.now();
          _dateExtracted = false;
        }
        
        // Description
        if (result.merchantExtracted && result.merchantName != null) {
          descriptionController.text = result.merchantName!;
          _descriptionExtracted = true;
        } else {
          descriptionController.text = '';
          _descriptionExtracted = false;
        }
        
        isExpense = true;
        _hasScanned = true;
      });

      // Handle amount + currency conversion (async, after setState)
      if (result.amountExtracted && result.amount != null) {
        final detectedCurrency = result.detectedCurrency;
        if (detectedCurrency != null &&
            detectedCurrency.isNotEmpty &&
            detectedCurrency != _currencyCode) {
          // Receipt currency differs from user's — auto convert
          try {
            final converted = await CurrencyService.convert(
              amount: result.amount!,
              from: detectedCurrency,
              to: _currencyCode,
            );
            if (mounted) {
              setState(() {
                amount = converted.toStringAsFixed(2);
                // Lock in the TRUE original — pre-conversion values
                _preConversionAmount   = result.amount!.toStringAsFixed(2);
                _preConversionCurrency = detectedCurrency;
              });
              Fluttertoast.showToast(
                msg: 'Converted ${CurrencyService.getSymbol(detectedCurrency)}'
                    '${result.amount!.toStringAsFixed(2)} → '
                    '$_currencySymbol${converted.toStringAsFixed(2)}',
                toastLength: Toast.LENGTH_LONG,
                gravity: ToastGravity.TOP,
                backgroundColor: const Color(0xFF4A6B7C),
                textColor: Colors.white,
                fontSize: 14.0,
              );
            }
          } catch (e) {
            if (mounted) {
              setState(() {
                amount = result.amount!.toStringAsFixed(2);
                // Conversion failed — original is the scanned amount in detected currency
                _preConversionAmount   = result.amount!.toStringAsFixed(2);
                _preConversionCurrency = detectedCurrency;
              });
            }
          }
        } else {
          // Same currency or unknown — use as-is, no pre-conversion tracking needed
          if (mounted) {
            setState(() {
              amount = result.amount!.toStringAsFixed(2);
              _preConversionAmount   = null;
              _preConversionCurrency = null;
            });
          }
        }
      }
      
      _showScanResultToast(result);
      
    } catch (e) {
      setState(() => _isScanning = false);
      
      if (mounted) {
        String errorMsg;
        Color errorColor;
        
        // Check for API overload/quota exceeded
        if (e.toString().toLowerCase().contains('quota') || 
            e.toString().toLowerCase().contains('limit') ||
            e.toString().toLowerCase().contains('overload') ||
            e.toString().toLowerCase().contains('rate')) {
          errorMsg = 'AI service temporarily unavailable. Please try again later.';
          errorColor = Colors.orange;
        } else {
          errorMsg = 'Failed to scan receipt. Please try again.';
          errorColor = Colors.red;
        }
        
        Fluttertoast.showToast(
          msg: errorMsg,
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: errorColor,
          textColor: Colors.white,
          fontSize: 14.0,
        );
      }
    }
  }
  
  void _showScanResultToast(result) {
    List<String> missing = [];
    
    if (!result.amountExtracted) missing.add('amount');
    if (!result.categoryExtracted) missing.add('category');
    if (!result.dateExtracted) missing.add('date');
    if (!result.merchantExtracted) missing.add('description');
    
    String message;
    Color backgroundColor;
    
    if (missing.isEmpty) {
      message = 'Receipt processed successfully';
      backgroundColor = Colors.green;
    } else if (missing.length == 1) {
      message = '${_capitalize(missing[0])} not detected';
      backgroundColor = Colors.orange;
    } else if (missing.length == 2) {
      message = '${_capitalize(missing[0])} and ${_capitalize(missing[1])} not detected';
      backgroundColor = Colors.orange;
    } else {
      message = 'Please verify extracted details';
      backgroundColor = Colors.orange;
    }
    
    if (mounted) {
      Fluttertoast.showToast(
        msg: message,
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.TOP,
        backgroundColor: backgroundColor,
        textColor: Colors.white,
        fontSize: 14.0,
      );
    }
  }
  
  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  // Budget warning functions
  Future<void> _checkBudgetWarnings(
    String categoryId,
    String userId,
    double newTransactionAmount,
  ) async {
    try {
      String weekStartDay = 'Monday';
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        if (userDoc.exists && userDoc.data() != null) {
          weekStartDay = userDoc.data()!['weekStartDay'] ?? 'Monday';
        }
      } catch (e) {
        print('Error loading weekStartDay: $e');
      }

      // Fetch conversion rates once — needed so expenses logged in a
      // different currency than the budget don't get summed as raw,
      // unconverted numbers (which is what was inflating the percentage).
      final rates = await CurrencyService.getRates();

      final allBudgets = await fetchBudgets(userId: userId);
      final categoryBudgets = allBudgets.where((b) => b['categoryID'] == categoryId).toList();

      if (categoryBudgets.isEmpty) return;

      for (var budget in categoryBudgets) {
        final durationType = budget['durationType'] ?? 'Monthly';

        // Convert the limit from its ORIGINAL currency to the user's
        // current display currency — same approach as the report tab —
        // instead of trusting the raw 'budgetLimit' field as-is.
        final origLimit = (budget['originalBudgetLimit'] ?? budget['budgetLimit'] as num).toDouble();
        final origCurrency = (budget['originalCurrency'] as String?) ?? _currencyCode;
        final budgetLimit = CurrencyService.convertSync(origLimit, origCurrency, _currencyCode, rates);

        if (budgetLimit <= 0) continue;

        final dateRange = getDateRangeForDuration(durationType, weekStartDay);
        final periodStart = dateRange['start']!;
        final periodEnd = dateRange['end']!;

        // Live total AFTER the transaction that was just saved — this
        // already reflects any prior deletions/edits, since it's a fresh
        // query against current Firestore data, not a cached value.
        final spentAfter = await calculateSpentForCategory(
          userId: userId,
          categoryId: categoryId,
          startDate: periodStart,
          endDate: periodEnd,
          targetCurrency: _currencyCode,
          rates: rates,
        );

        // "Before" is derived by subtracting just this transaction's own
        // amount from the live total — not from a stored record — so it
        // can never go stale relative to deletions made in between. If
        // spending was deleted down below 80% and then crosses it again,
        // this naturally reflects that, since spentAfter already dropped.
        final spentBefore = (spentAfter - newTransactionAmount).clamp(0.0, double.infinity);

        final tierBefore = _tierForPercentage((spentBefore / budgetLimit) * 100);
        final tierAfter = _tierForPercentage((spentAfter / budgetLimit) * 100);

        // Only notify on an actual upward crossing caused by THIS
        // transaction — not a repeat while already sitting in the same
        // tier, but always re-armed if a real drop happened first.
        if (tierAfter > tierBefore) {
          await _showBudgetWarning(
            durationType: durationType,
            categoryId: categoryId,
            percentage: (spentAfter / budgetLimit) * 100,
          );
        }
      }
    } catch (e) {
      print('Error checking budget warnings: $e');
    }
  }

  // Maps a percentage to a warning tier: 0 = under 80%, 80 = approaching,
  // 100 = exceeded. Comparing tiers (not raw percentages) is what lets
  // 80% and 100% each notify independently within the same period.
  int _tierForPercentage(double percentage) {
    if (percentage >= 100) return 100;
    if (percentage >= 80) return 80;
    return 0;
  }

  Future<void> _showBudgetWarning({
    required String durationType,
    required String categoryId,
    required double percentage,
  }) async {
    String categoryName = 'your';
    try {
      final name = await getCategoryNameById(categoryId);
      categoryName = name;
    } catch (e) {
      print('Error getting category name: $e');
    }

    // Exceeded the limit (100%+) -> red. Still just approaching it (80-99%) -> orange.
    // White, semi-bold text is set explicitly on both so it stays readable
    // even against the brighter red background.
    final bool isExceeded = percentage >= 100;
    final Color warningColor = isExceeded ? Colors.red : Colors.orange;
    final String message = isExceeded
        ? '🚨 You\'ve exceeded your $durationType $categoryName budget! (${percentage.toStringAsFixed(0)}%)'
        : '⚠️ You\'ve used ${percentage.toStringAsFixed(0)}% of your $durationType $categoryName budget!';

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: warningColor,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _saveTransaction() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('❌ Save failed: No user logged in');
      return;
    }

    final double amountValue = double.tryParse(amount) ?? 0.0;
    print('💾 Saving transaction: amount=$amount, parsed=$amountValue');

    if (amountValue <= 0) {
      print('❌ Save failed: Invalid amount');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please Enter The Amount'),
          backgroundColor: Color(0xFFE8EEF1),
        ),
      );
      return;
    }

    try {
      if (isExpense) {
        if (selectedCategoryId == null) {
          print('❌ Save failed: No category selected');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a category')),
          );
          return;
        }

        print('💾 Saving expense: categoryID=$selectedCategoryId, amount=$amountValue');
        
        await FirebaseFirestore.instance.collection('expenses').add({
          'userID': user.uid,
          'categoryID': selectedCategoryId,
          'amount': amountValue,
          'baseCurrency': _currencyCode,
          // If receipt was auto-converted, lock in the PRE-conversion values as original
          // so converting back always gives the exact original receipt amount
          'originalAmount':   _preConversionAmount != null
              ? double.parse(_preConversionAmount!)
              : amountValue,
          'originalCurrency': _preConversionCurrency ?? _currencyCode,
          'description': descriptionController.text,
          'date': selectedDate,
        });

        print('✅ Expense saved successfully!');
        await _checkBudgetWarnings(selectedCategoryId!, user.uid, amountValue);
      } else {
        if (selectedSourceId == null) {
          print('❌ Save failed: No income source selected');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select an income source')),
          );
          return;
        }

        print('💾 Saving income: sourceID=$selectedSourceId, amount=$amountValue');

        await FirebaseFirestore.instance.collection('income').add({
          'userID': user.uid,
          'incomeSourceID': selectedSourceId,
          'amount': amountValue,
          'baseCurrency': _currencyCode,
          'originalAmount':   _preConversionAmount != null
              ? double.parse(_preConversionAmount!)
              : amountValue,
          'originalCurrency': _preConversionCurrency ?? _currencyCode,
          'description': descriptionController.text,
          'date': selectedDate,
        });

        print('✅ Income saved successfully!');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Transaction saved successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Reset pre-conversion tracking for next transaction
      _preConversionAmount   = null;
      _preConversionCurrency = null;

      Navigator.pop(context);
      
    } catch (e) {
      print('❌❌❌ Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error saving transaction: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
}