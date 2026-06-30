import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'category_helper.dart';
import 'currency_service.dart';

class EditTransactionPage extends StatefulWidget {
  final Map<String, dynamic> transaction;
  final bool isIncome; // true if income, false if expense

  const EditTransactionPage({
    super.key,
    required this.transaction,
    required this.isIncome,
  });

  @override
  State<EditTransactionPage> createState() => _EditTransactionPageState();
}

class _EditTransactionPageState extends State<EditTransactionPage> {
  bool showNumberPad = false;

  late String amount;
  String? selectedCategoryId;
  String? selectedSourceId;
  late DateTime selectedDate;
  late TextEditingController descriptionController;

  // User's currency
  String _currencyCode   = 'MYR';
  String _currencySymbol = 'RM';

  // Track original so we only update it if user actually changes the amount
  late double  _originalAmount;
  late String  _originalCurrency;
  bool         _amountChanged = false;

  // NEW: Fetched categories/sources from Firestore
  List<Map<String, dynamic>> expenseCategories = [];
  List<Map<String, dynamic>> incomeSources = [];
  bool isLoadingCategories = true;

  // Icon/color lookup now comes from category_helper.dart's centralized
  // getCategoryIconColor()/getIncomeIconColor() instead of this local map.

  @override
  void initState() {
    super.initState();

    // Store the true originals
    _originalAmount   = ((widget.transaction['originalAmount']   ??
                          widget.transaction['amount'])          as num).toDouble();
    _originalCurrency = (widget.transaction['originalCurrency'] as String?) ?? 'MYR';

    // Start with raw stored amount — will be replaced with converted value
    // once _initData completes
    amount = _originalAmount.toStringAsFixed(2);

    selectedCategoryId = widget.transaction['categoryID'];
    selectedSourceId   = widget.transaction['incomeSourceID'];
    selectedDate       = (widget.transaction['date'] as Timestamp).toDate();
    descriptionController =
        TextEditingController(text: widget.transaction['description'] ?? '');

    _initData();
  }

  Future<void> _initData() async {
    await _loadUserCurrency();
    // Now convert originalAmount → user's current display currency
    final displayAmount = await CurrencyService.convert(
      amount: _originalAmount,
      from:   _originalCurrency,
      to:     _currencyCode,
    );
    if (mounted) {
      setState(() => amount = displayAmount.toStringAsFixed(2));
    }
    await _loadCategories();
  }

  @override
  void dispose() {
    descriptionController.dispose();
    super.dispose();
  }

  // NEW: Load categories from Firestore
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

        // If no category selected yet, set first one
        if (selectedCategoryId == null && expenseCategories.isNotEmpty) {
          selectedCategoryId = expenseCategories[0]['id'];
        }
        if (selectedSourceId == null && incomeSources.isNotEmpty) {
          selectedSourceId = incomeSources[0]['id'];
        }
      });
    } catch (e) {
      print('Error loading categories: $e');
      setState(() => isLoadingCategories = false);
    }
  }


  // Load user's currency from Firestore
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

  // Convert currency code to symbol
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
      'AFN': 'Af',
      'ALL': 'Lek',
      'AMD': '֏',
      'ANG': 'ƒ',
      'AOA': 'Kz',
      'ARS': '\$',
      'AWG': 'ƒ',
      'AZN': '₼',
      'HKD': 'HK\$',
      'NOK': 'kr',
      'KRW': '₩',
      'TRY': '₺',
      'BRL': 'R\$',
      'ZAR': 'R',
      'SEK': 'kr',
      'NZD': 'NZ\$',
      'ADP': 'ADP',
    };
    
    return currencySymbols[code] ?? code;
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
          'Edit Transaction',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _updateTransaction,
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
                        widget.isIncome ? _typeField() : _categoryField(),
                        const SizedBox(height: 24),
                        _dateField(),
                        const SizedBox(height: 24),
                        _descriptionField(),
                        const SizedBox(height: 30),
                        _deleteButton(),
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
          _typeButton('Expense', false, const Color.fromARGB(255, 142, 187, 202)),
          _typeButton('Income', true, const Color.fromARGB(255, 142, 187, 202)),
        ],
      ),
    );
  }

  Widget _typeButton(String text, bool isIncomeButton, Color color) {
    final bool active = widget.isIncome == isIncomeButton;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                  )
                ]
              : [],
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: active ? color : Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _amountDisplay() {
    final bool isActive = showNumberPad;
    final bool isEmpty = amount == '0.00';

    return GestureDetector(
      onTap: () {
        setState(() {
          showNumberPad = !showNumberPad;
          FocusScope.of(context).unfocus();
        });
      },
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isActive ? Colors.blue : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              '$_currencySymbol $amount',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: isEmpty ? Colors.grey[400] : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Category field with preview
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
                color: const Color(0xFFF5F5F5),
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
          ],
        ),
      ),
    );
  }

  // Income type field with preview
  Widget _typeField() {
    if (selectedSourceId == null || incomeSources.isEmpty) {
      return Container();
    }

    final source = incomeSources.firstWhere(
      (s) => s['id'] == selectedSourceId,
      orElse: () => incomeSources[0],
    );
    final iconColor = getIncomeIconColor(source['name']);

    return GestureDetector(
      onTap: () {
        setState(() => showNumberPad = false);
        _showIncomeTypeSelector();
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
                color: const Color(0xFFF5F5F5),
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
                source['name'],
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }

  // Show category selector with "+ Add New" tile
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
                itemCount: expenseCategories.length + 1,
                itemBuilder: (context, index) {
                  // "+ Add New" tile
                  if (index == expenseCategories.length) {
                    return GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        await _showAddCategoryDialog(isExpense: true);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[400]!, width: 2),
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
                      setState(() => selectedCategoryId = category['id']);
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

  // Show income type selector with "+ Add New" tile
  void _showIncomeTypeSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.5,
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
                    'INCOME TYPE',
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
                itemCount: incomeSources.length + 1,
                itemBuilder: (context, index) {
                  // "+ Add New" tile
                  if (index == incomeSources.length) {
                    return GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        await _showAddCategoryDialog(isExpense: false);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[400]!, width: 2),
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

                  // Regular source tile
                  final source = incomeSources[index];
                  final iconColor = getIncomeIconColor(source['name']);
                  final isSelected = selectedSourceId == source['id'];
                  
                  return GestureDetector(
                    onTap: () {
                      setState(() => selectedSourceId = source['id']);
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

  // Dialog to add custom category/source
  Future<void> _showAddCategoryDialog({required bool isExpense}) async {
    final controller = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isExpense ? 'Add New Category' : 'Add New Income Source'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: isExpense ? 'Enter category name' : 'Enter source name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a name')),
                );
                return;
              }

              Navigator.pop(context);

              // Add to Firestore
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                String? newId;
                if (isExpense) {
                  newId = await addCustomExpenseCategory(user.uid, name);
                } else {
                  newId = await addCustomIncomeSource(user.uid, name);
                }

                // Reload categories
                await _loadCategories();

                // Set as selected
                if (newId != null) {
                  setState(() {
                    if (isExpense) {
                      selectedCategoryId = newId;
                    } else {
                      selectedSourceId = newId;
                    }
                  });
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$name added successfully!')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _dateField() {
    return GestureDetector(
      onTap: () async {
        setState(() {
          showNumberPad = false;
        });
        DateTime? pickedDate = await showDatePicker(
          context: context,
          initialDate: selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (pickedDate != null) {
          setState(() { 
            selectedDate = pickedDate;
          });
        }
      },
      child: AbsorbPointer(
        child: TextField(
          controller: TextEditingController(
            text:
                '${selectedDate.day} ${_monthName(selectedDate.month)} ${selectedDate.year}',
          ),
          decoration: _inputDecoration('Date'),
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
    );
  }

  Widget _deleteButton() {
    return Center(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color.fromARGB(255, 96, 138, 156),
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
        ),
        onPressed: _confirmDelete,
        child: const Text(
          'Delete',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text(
          'Are you sure you want to delete this transaction?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _deleteTransaction();
    }
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

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return months[month - 1];
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
                          _numberKey(row, col),
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

  Widget _numberKey(int row, int col) {
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
            _amountChanged = true; // user is actively editing the amount

            // Cents shift in from the right — same as add_transaction_page.dart.
            int cents = ((double.tryParse(amount) ?? 0.0) * 100).round();

            if (key == '⌫') {
              cents = cents ~/ 10;
            } else if (key == '00') {
              final next = cents * 100;
              if (next <= 99999999) cents = next;
            } else {
              final next = cents * 10 + int.parse(key);
              if (next <= 99999999) cents = next;
            }

            amount = (cents / 100).toStringAsFixed(2);
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

  Future<void> _updateTransaction() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final double amountValue = double.tryParse(amount) ?? 0.0;
    final docId = widget.transaction['docId'];

    // If user changed the amount, new original = what they entered in current currency
    // If unchanged, keep the original as-is to preserve lossless conversion
    final saveOriginalAmount   = _amountChanged ? amountValue   : _originalAmount;
    final saveOriginalCurrency = _amountChanged ? _currencyCode : _originalCurrency;

    if (widget.isIncome) {
      if (selectedSourceId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an income source')),
        );
        return;
      }
      await FirebaseFirestore.instance.collection('income').doc(docId).update({
        'amount':           amountValue,
        'baseCurrency':     _currencyCode,
        'originalAmount':   saveOriginalAmount,
        'originalCurrency': saveOriginalCurrency,
        'incomeSourceID':   selectedSourceId,
        'description':      descriptionController.text,
        'date':             selectedDate,
      });
    } else {
      if (selectedCategoryId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a category')),
        );
        return;
      }
      await FirebaseFirestore.instance.collection('expenses').doc(docId).update({
        'amount':           amountValue,
        'baseCurrency':     _currencyCode,
        'originalAmount':   saveOriginalAmount,
        'originalCurrency': saveOriginalCurrency,
        'categoryID':       selectedCategoryId,
        'description':      descriptionController.text,
        'date':             selectedDate,
      });
    }

    Navigator.pop(context);
  }

  Future<void> _deleteTransaction() async {
    final docId = widget.transaction['docId'];

    if (widget.isIncome) {
      await FirebaseFirestore.instance.collection('income').doc(docId).delete();
    } else {
      await FirebaseFirestore.instance.collection('expenses').doc(docId).delete();
    }

    Navigator.pop(context);
  }
}