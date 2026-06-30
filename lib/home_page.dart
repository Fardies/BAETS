import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_transaction_page.dart';
import 'edit_transaction.dart';
import 'login_page.dart';
import 'report_page.dart';
import 'budget_page.dart';
import 'settings_page.dart';
import 'category_helper.dart';
import 'currency_service.dart';
import 'dart:ui';
import 'dart:math' as math;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  int _budgetRefreshKey = 0;  // Increment when budget needs refresh
  int _reportRefreshKey = 0;  // Increment when report needs refresh

  List<Map<String, dynamic>> expenseList = [];
  List<Map<String, dynamic>> incomeList = [];

  double totalExpense = 0.0;
  double totalIncome = 0.0;
  double balance = 0.0;

  // User's currency
  String _currencyCode = 'MYR';
  String _currencySymbol = 'RM';
  
  // NEW: Week start day preference
  String _weekStartDay = 'Monday';

  // Date range overlay
  bool showDateOverlay = false;
  late AnimationController _overlayController;
  late Animation<Offset> _overlayAnimation;

  String selectedPreset = 'Day';
  DateTime startDate = DateTime.now();
  DateTime endDate = DateTime.now();
  
  // NEW: Selected month for monthly view (1-12, default to current month)
  int selectedMonth = DateTime.now().month;
  int selectedYear = DateTime.now().year;

  // Icon/color lookup now comes from category_helper.dart's centralized
  // getCategoryIconColor()/getIncomeIconColor() — matching the same
  // style used in report_page.dart and budget_report_tab.dart, instead
  // of this page's own separate bright-color maps.

  @override
  void initState() {
    super.initState();

    _overlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _overlayAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _overlayController, curve: Curves.easeOut),
    );

    _setPresetDateRange();
    _loadUserCurrency();
    fetchExpenses();
    fetchIncome();
  }

  @override
  void dispose() {
    _overlayController.dispose();
    super.dispose();
  }

  // NEW: Build current page dynamically - creates fresh BudgetPage each time!
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
          final weekStart = doc.data()!['weekStartDay'] ?? 'Monday'; // NEW: Load week start day
          setState(() {
            _currencyCode = currency;
            _currencySymbol = _getCurrencySymbol(currency);
            _weekStartDay = weekStart; // NEW: Set week start day
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

  // Get icon and color for category/type — now delegates to the
  // centralized lookup in category_helper.dart instead of a local map.
  Map<String, dynamic> _getCategoryInfo(String categoryOrType, bool isIncome) {
    return isIncome
        ? getIncomeIconColor(categoryOrType)
        : getCategoryIconColor(categoryOrType);
  }

  void _setPresetDateRange() {
    DateTime now = DateTime.now();
    switch (selectedPreset) {
      case 'Day':
        startDate = DateTime(now.year, now.month, now.day);
        endDate = startDate;
        break;
      case 'Week':
        // Use weekStartDay preference
        int weekday = now.weekday; // 1 = Monday, 7 = Sunday
        int daysToSubtract;
        
        if (_weekStartDay == 'Monday') {
          // Week starts Monday (weekday 1)
          daysToSubtract = weekday - 1; // Mon=0, Tue=1, ... Sun=6
        } else {
          // Week starts Sunday (weekday 7)
          daysToSubtract = weekday == 7 ? 0 : weekday; // Sun=0, Mon=1, ... Sat=6
        }
        
        startDate = now.subtract(Duration(days: daysToSubtract));
        startDate = DateTime(startDate.year, startDate.month, startDate.day); // Remove time
        endDate = startDate.add(const Duration(days: 6));
        break;
      case 'Month':
        // Use selected month and year instead of current month
        startDate = DateTime(selectedYear, selectedMonth, 1);
        endDate = DateTime(selectedYear, selectedMonth + 1, 0); // Last day of selected month
        break;
      case 'Year':
        startDate = DateTime(now.year, 1, 1);
        endDate = DateTime(now.year, 12, 31);
        break;
      case 'Date Range':
        break;
    }
  }

  Future<void> fetchExpenses() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    DateTime endInclusive = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('expenses')
        .where('userID', isEqualTo: user.uid)
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endInclusive)
        .get();

    // Fetch rates once for the whole loop
    final rates = await CurrencyService.getRates();

    List<Map<String, dynamic>> temp = [];
    double expenseSum = 0.0;

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;

      // Use originalAmount/originalCurrency if available, else fall back to amount
      final originalAmount   = ((data['originalAmount']   ?? data['amount'])  as num).toDouble();
      final originalCurrency = (data['originalCurrency'] as String?) ?? _currencyCode;

      // Convert to user's current currency on the fly
      final displayAmount = CurrencyService.convertSync(
          originalAmount, originalCurrency, _currencyCode, rates);

      final categoryId = data['categoryID'];
      String categoryName = 'Unknown';
      if (categoryId != null) {
        categoryName = await getCategoryNameById(categoryId);
      }

      temp.add({
        'category':         categoryName,
        'categoryID':       categoryId,
        'amount':           displayAmount,
        'originalAmount':   originalAmount,
        'originalCurrency': originalCurrency,
        'description':      data['description'] ?? '',
        'date':             data['date'],
        'docId':            doc.id,
      });

      expenseSum += displayAmount;
    }

    setState(() {
      expenseList  = temp;
      totalExpense = expenseSum;
      balance      = totalIncome - totalExpense;
    });
  }

  Future<void> fetchIncome() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    DateTime endInclusive = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('income')
        .where('userID', isEqualTo: user.uid)
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endInclusive)
        .get();

    // Fetch rates once for the whole loop
    final rates = await CurrencyService.getRates();

    List<Map<String, dynamic>> temp = [];
    double incomeSum = 0.0;

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;

      final originalAmount   = ((data['originalAmount']   ?? data['amount'])  as num).toDouble();
      final originalCurrency = (data['originalCurrency'] as String?) ?? _currencyCode;

      final displayAmount = CurrencyService.convertSync(
          originalAmount, originalCurrency, _currencyCode, rates);

      final sourceId = data['incomeSourceID'];
      String sourceName = 'Unknown';
      if (sourceId != null) {
        sourceName = await getIncomeSourceNameById(sourceId);
      }

      temp.add({
        'type':             sourceName,
        'incomeSourceID':   sourceId,
        'amount':           displayAmount,
        'originalAmount':   originalAmount,
        'originalCurrency': originalCurrency,
        'description':      data['description'] ?? '',
        'date':             data['date'],
        'docId':            doc.id,
      });

      incomeSum += displayAmount;
    }

    setState(() {
      incomeList  = temp;
      totalIncome = incomeSum;
      balance     = totalIncome - totalExpense;
    });
  }

  void _toggleDateOverlay() {
    setState(() => showDateOverlay = !showDateOverlay);
    if (showDateOverlay) _overlayController.forward();
    else _overlayController.reverse();
  }

  void _selectPreset(String preset) {
    setState(() {
      selectedPreset = preset;
      _setPresetDateRange();
    });
    fetchExpenses();
    fetchIncome();
  }

  Future<void> _pickDate({required bool isStart}) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? startDate : endDate,
      firstDate: DateTime(1900), // Allow far past dates
      lastDate: DateTime(2100),  // Allow far future dates
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          startDate = picked;
          if (endDate.isBefore(startDate)) endDate = startDate;
        } else {
          endDate = picked;
          if (endDate.isBefore(startDate)) startDate = endDate;
        }
      });
    }
  }

  void _saveDateRange() {
    _toggleDateOverlay();
    fetchExpenses();
    fetchIncome();
  }

  String get _dateText {
    switch (selectedPreset) {
      case 'Day':
        return "${startDate.day} ${_monthName(startDate.month)} ${startDate.year}";
      case 'Week':
        String startStr = "${startDate.day} ${_monthName(startDate.month)}";
        String endStr = "${endDate.day} ${_monthName(endDate.month)}";
        return "$startStr - $endStr";
      case 'Month':
        return "${_monthName(selectedMonth)} $selectedYear";
      case 'Year':
        return "${startDate.year}";
      case 'Date Range':
        String startStr = "${startDate.day} ${_monthName(startDate.month)}";
        String endStr = "${endDate.day} ${_monthName(endDate.month)}";
        return "$startStr - $endStr";
      default:
        return "${_monthName(startDate.month)} ${startDate.year}";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EEF1),

      appBar: _currentIndex == 0
          ? AppBar(
              elevation: 0,
              backgroundColor: Colors.white,
              centerTitle: true,
              title: GestureDetector(
                onTap: _toggleDateOverlay,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _dateText,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down,
                        color: Colors.black, size: 20),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.black),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Log Out'),
                        content: const Text('Are you sure you want to log out?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('Log Out'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await FirebaseAuth.instance.signOut();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      );
                    }
                  },
                ),
              ],
            )
          : null,

      // ⚡ OPTIMIZATION: IndexedStack keeps all pages alive in memory
      // Budget and Report use refresh keys - only rebuild when data changes!
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeContent(),                                      // Index 0: Home
          ReportPage(key: ValueKey('report_$_reportRefreshKey')),  // Index 1: Report
          BudgetPage(key: ValueKey('budget_$_budgetRefreshKey')),  // Index 2: Budget
          const SettingsPage(),                                     // Index 3: Settings
        ],
      ),

      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: () async {
                final warningMessage = await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AddTransactionPage()),
                );
                
                // Reload home page data
                fetchExpenses();
                fetchIncome();
                _loadUserCurrency();
                
                // Trigger Budget and Report refresh since data changed!
                setState(() {
                  _budgetRefreshKey++;
                  _reportRefreshKey++;
                });
                
                // Show budget warning if there is one
                if (warningMessage != null && warningMessage is String && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(warningMessage),
                      backgroundColor: Colors.orange,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              },
              backgroundColor: const Color(0xFF6B8FA3),
              child: const Icon(Icons.add, size: 30),
            )
          : null,

      floatingActionButtonLocation:
          FloatingActionButtonLocation.endFloat,

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF4A6B7C),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
            
            // Refresh Report page when navigating to it
            if (index == 1) {
              _reportRefreshKey++;
            }
          });
          
          if (index == 0) {
            _loadUserCurrency().then((_) {
              fetchExpenses();
              fetchIncome();
            });
          }
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart), label: 'Report'),
          BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet),
              label: 'Budget'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: 'Setting'),
        ],
      ),
    );
  }

  Widget _buildHomeContent() {
    double progress =
        totalIncome > 0 ? (totalExpense / totalIncome).clamp(0.0, 1.0) : 0.0;

    return Stack(
      children: [
        // Scattered doodle background — sits behind everything, fixed to
        // the viewport so it doesn't move around as the list scrolls.
        const Positioned.fill(
          child: CustomPaint(painter: _DoodleBackgroundPainter()),
        ),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryCard(progress),
                const SizedBox(height: 24),
                _incomeSection(),
                const SizedBox(height: 24),
                _expenseSection(),
              ],
            ),
          ),
        ),
        if (showDateOverlay) _buildDateOverlay(),
      ],
    );
  }

  Widget _buildDateOverlay() {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: GestureDetector(
          onTap: _toggleDateOverlay,
          child: Container(
            color: Colors.black38,
            child: SlideTransition(
              position: _overlayAnimation,
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.7,
                  ),
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: TextButton(
                          onPressed: _saveDateRange,
                          child: const Text(
                            'Save',
                            style: TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'DATE RANGE',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: ['Day', 'Week', 'Month', 'Year', 'Date Range']
                            .map((preset) => ChoiceChip(
                                  label: Text(preset),
                                  selected: selectedPreset == preset,
                                  onSelected: (_) => _selectPreset(preset),
                                  selectedColor: const Color.fromARGB(255, 242, 190, 208),
                                ))
                            .toList(),
                      ),
                      
                      // NEW: Month Picker for Month preset
                      if (selectedPreset == 'Month') ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Select Month:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        // Compact month grid (4 rows x 3 columns)
                        GridView.builder(
                          shrinkWrap: true,
                          physics: NeverScrollableScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 2.3, // Slightly reduced for better fit
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 8, // Increased spacing for better visibility
                            ),
                            itemCount: 12,
                            itemBuilder: (context, index) {
                              final month = index + 1;
                              final monthName = _monthName(month);
                              final isSelected = month == selectedMonth;
                              
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    selectedMonth = month;
                                    _setPresetDateRange();
                                    fetchExpenses();
                                    fetchIncome();
                                  });
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected ? Color(0xFF4A6B7C) : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected ? Color(0xFF4A6B7C) : Colors.grey[300]!,
                                      width: 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      monthName.substring(0, 3), // Jan, Feb, etc.
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : Colors.black87,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                      
                      if (selectedPreset == 'Date Range') ...[
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _pickDate(isStart: true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Start: ${startDate.day} ${_monthName(startDate.month)} ${startDate.year}',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _pickDate(isStart: false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'End: ${endDate.day} ${_monthName(endDate.month)} ${endDate.year}',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      ]
                    ],
                  ),
                ), // Close SingleChildScrollView
              ), // Close Container
              ),
            ),
          ),
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

  Widget _summaryCard(double progress) {
    return Card(
      color: const Color.fromARGB(255, 159, 192, 192),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Summary',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _summaryItem('Income', totalIncome),
                _verticalDivider(),
                _summaryItem('Expense', totalExpense),
                _verticalDivider(),
                _summaryItem('Balance', balance),
              ],
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white,
                color: const Color(0xFF4A6B7C),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(String label, double value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Color.fromARGB(255, 0, 0, 0))),
        const SizedBox(height: 6),
        SizedBox(
          width: 90,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$_currencySymbol ${value.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _verticalDivider() {
    return Container(
      height: 40,
      width: 1,
      color: const Color.fromARGB(255, 0, 0, 0),
    );
  }

  Widget _incomeSection() {
    return _transactionSection(
      title: 'Income',
      items: incomeList,
      isIncome: true,
    );
  }

  Widget _expenseSection() {
    return _transactionSection(
      title: 'Expense',
      items: expenseList,
      isIncome: false,
    );
  }

  Widget _transactionSection({
    required String title,
    required List<Map<String, dynamic>> items,
    required bool isIncome,
  }) {
    // Same two colors the original Card used — just changing the
    // shape, not introducing a new palette.
    final Color blobColor = isIncome ? const Color(0xFFD5E3E8) : Colors.white;
    final Color dividerColor = Colors.black.withOpacity(0.08);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  isIncome
                      ? '$_currencySymbol ${totalIncome.toStringAsFixed(2)}'
                      : '$_currencySymbol ${totalExpense.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // The blob's CustomPaint uses Positioned.fill, so it always
        // stretches to match whatever height the rows underneath need —
        // 1 transaction or 20, the shape just resizes with it.
        Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _OrganicBlobPainter(color: blobColor)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'No ${isIncome ? "income" : "expense"} transaction made for this period',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ),
                    )
                  else
                    for (int i = 0; i < items.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: CustomPaint(
                            size: const Size(double.infinity, 1),
                            painter: _DashedLinePainter(color: dividerColor),
                          ),
                        ),
                      _transactionTile(items[i], isIncome),
                    ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _transactionTile(Map<String, dynamic> item, bool isIncome) {
    final categoryOrType = isIncome
        ? (item['type'] ?? 'Other')
        : (item['category'] ?? 'Other');
    final categoryInfo = _getCategoryInfo(categoryOrType, isIncome);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EditTransactionPage(
              transaction: item,
              isIncome: isIncome,
            ),
          ),
        ).then((_) {
          // Reload home data
          if (isIncome) fetchIncome();
          else fetchExpenses();

          // Trigger Budget and Report refresh since data changed!
          setState(() {
            _budgetRefreshKey++;
            _reportRefreshKey++;
          });
        });
      },
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        // Reverted back to the original soft-tint circle style.
        leading: CircleAvatar(
          backgroundColor: categoryInfo['color'].withOpacity(0.2),
          child: Icon(
            categoryInfo['icon'],
            color: categoryInfo['color'],
          ),
        ),
        title: Text(categoryOrType),
        subtitle: item['description'] != null && item['description'].toString().isNotEmpty
            ? Text(
                item['description'],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              )
            : null,
        trailing: Text(
          '$_currencySymbol ${(item['amount'] ?? 0).toDouble().toStringAsFixed(2)}',
          style: TextStyle(
            color: categoryInfo['color'],
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// Scattered decorative background — stars, sparkle crosses, leaves,
// flower clusters, and dots — drawn directly with Canvas so no SVG/asset
// package is needed. Positions are fractions of the canvas size, so it
// scales sensibly across different screen sizes instead of using fixed
// pixel coordinates.
class _DoodleBackgroundPainter extends CustomPainter {
  const _DoodleBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final starPaint = Paint()..color = const Color(0xFF8ABCBC).withOpacity(0.4);
    final crossPaint = Paint()
      ..color = const Color(0xFF7AAAB0).withOpacity(0.45)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final leafFill = Paint()..color = const Color(0xFF7AB8A0).withOpacity(0.3);
    final leafStroke = Paint()
      ..color = const Color(0xFF5A9880).withOpacity(0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final petalPaint = Paint()..color = const Color(0xFFA8C8C0).withOpacity(0.5);
    final flowerCenterPaint = Paint()..color = const Color(0xFFC8E4DC).withOpacity(0.75);
    final dotPaint = Paint()..color = const Color(0xFF8AB4B8).withOpacity(0.3);

    void drawStar(Offset c, double r) {
      final path = Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx + r * 0.25, c.dy - r * 0.25, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx + r * 0.25, c.dy + r * 0.25, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx - r * 0.25, c.dy + r * 0.25, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx - r * 0.25, c.dy - r * 0.25, c.dx, c.dy - r)
        ..close();
      canvas.drawPath(path, starPaint);
    }

    void drawCross(Offset c, double r) {
      canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), crossPaint);
      canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), crossPaint);
      final d = r * 0.7;
      canvas.drawLine(Offset(c.dx - d, c.dy - d), Offset(c.dx + d, c.dy + d), crossPaint);
      canvas.drawLine(Offset(c.dx + d, c.dy - d), Offset(c.dx - d, c.dy + d), crossPaint);
    }

    void drawLeaf(Offset tip, double leafSize, double angle) {
      canvas.save();
      canvas.translate(tip.dx, tip.dy);
      canvas.rotate(angle);
      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(leafSize * 0.8, -leafSize * 0.6, leafSize, 0)
        ..quadraticBezierTo(leafSize * 0.8, leafSize * 0.5, 0, 0)
        ..close();
      canvas.drawPath(path, leafFill);
      canvas.drawLine(Offset.zero, Offset(leafSize, 0), leafStroke);
      canvas.restore();
    }

    void drawFlower(Offset c, double r) {
      for (final angleDeg in [0.0, 72.0, 144.0, 216.0, 288.0]) {
        final rad = angleDeg * math.pi / 180;
        canvas.drawCircle(
          Offset(c.dx + r * 0.6 * math.cos(rad), c.dy + r * 0.6 * math.sin(rad)),
          r * 0.5,
          petalPaint,
        );
      }
      canvas.drawCircle(c, r * 0.35, flowerCenterPaint);
    }

    void drawDot(Offset c, double r) => canvas.drawCircle(c, r, dotPaint);

    // Concentrated toward the edges so they don't clash with the
    // content in the middle of the screen.
    drawStar(Offset(w * 0.08, h * 0.035), 6);
    drawStar(Offset(w * 0.93, h * 0.10), 5);
    drawStar(Offset(w * 0.06, h * 0.30), 6);
    drawStar(Offset(w * 0.92, h * 0.58), 5);

    drawCross(Offset(w * 0.90, h * 0.02), 7);
    drawCross(Offset(w * 0.05, h * 0.18), 7);
    drawCross(Offset(w * 0.94, h * 0.40), 6);

    drawLeaf(Offset(w * 0.88, h * 0.16), 18, -0.5);
    drawLeaf(Offset(w * 0.05, h * 0.26), 18, 2.6);
    drawLeaf(Offset(w * 0.90, h * 0.48), 16, -0.4);

    drawFlower(Offset(w * 0.90, h * 0.24), 10);
    drawFlower(Offset(w * 0.06, h * 0.44), 10);

    drawDot(Offset(w * 0.16, h * 0.10), 4);
    drawDot(Offset(w * 0.86, h * 0.30), 3.5);
    drawDot(Offset(w * 0.12, h * 0.52), 4);
  }

  @override
  bool shouldRepaint(covariant _DoodleBackgroundPainter oldDelegate) => false;
}

// A gently wobbly rounded-rect "blob" — drawn with relative (fraction of
// width/height) coordinates rather than fixed pixels, so it stretches to
// fit any content height. Used behind the Income/Expense transaction
// lists instead of the mockup's fixed hand-drawn shape, which wouldn't
// adapt to however many transactions actually exist.
class _OrganicBlobPainter extends CustomPainter {
  final Color color;
  const _OrganicBlobPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()..color = color;

    final path = Path();
    path.moveTo(w * 0.04, h * 0.10);
    path.quadraticBezierTo(w * 0.02, h * 0.02, w * 0.12, h * 0.015);
    path.quadraticBezierTo(w * 0.45, h * 0.00, w * 0.78, h * 0.02);
    path.quadraticBezierTo(w * 0.96, h * 0.03, w * 0.985, h * 0.12);
    path.quadraticBezierTo(w * 0.97, h * 0.5, w * 0.99, h * 0.85);
    path.quadraticBezierTo(w * 0.99, h * 0.97, w * 0.85, h * 0.985);
    path.quadraticBezierTo(w * 0.5, h * 1.0, w * 0.18, h * 0.98);
    path.quadraticBezierTo(w * 0.02, h * 0.97, w * 0.015, h * 0.84);
    path.quadraticBezierTo(w * 0.01, h * 0.5, w * 0.04, h * 0.10);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OrganicBlobPainter oldDelegate) =>
      oldDelegate.color != color;
}

// Simple dashed horizontal divider, used between transaction rows inside
// the blob boxes (matches the mockup's dashed row separators).
class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    final y = size.height / 2;

    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, y), Offset(startX + dashWidth, y), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}