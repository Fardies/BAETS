import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:ui';
import 'budget_helper.dart';
import 'category_helper.dart';
import 'pdf_generator.dart';
import 'currency_service.dart';
import 'tabs/budget_report_tab.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int selectedTab = 0; // 0=Expense, 1=Income, 2=Budget

  // Date range overlay
  bool showDateOverlay = false;
  late AnimationController _overlayController;
  late Animation<Offset> _overlayAnimation;

  String selectedPreset = 'Month';
  DateTime startDate = DateTime.now();
  DateTime endDate = DateTime.now();

  // Enhanced month selection (like home page)
  int selectedMonth = DateTime.now().month;
  int selectedYear = DateTime.now().year;

  // User preferences
  String _currencySymbol = 'RM';
  String _currencyCode   = 'MYR';
  String _weekStartDay   = 'Monday';

  // Transaction data
  double totalIncome = 0.0;
  double totalExpense = 0.0;
  double balance = 0.0;
  bool isLoading = true;

  // Category breakdown data
  List<Map<String, dynamic>> expenseByCategory = [];
  List<Map<String, dynamic>> incomeBySource = [];
  
  // Budget performance data (for Expense tab PDF)
  List<Map<String, dynamic>> budgetPerformance = [];
  
  // Trend data (for line charts)
  List<Map<String, dynamic>> expenseTrendData = [];
  List<Map<String, dynamic>> incomeTrendData = [];

  // Icon/color lookup now comes from category_helper.dart's centralized
  // getCategoryIconColor()/getIncomeIconColor() — matching the same
  // single dark-ink-color, outlined-icon style used in budget_report_tab.dart,
  // instead of this page's own separate (and previously out-of-sync) dict.

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this); // Add lifecycle observer

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
    _loadUserPreferences();
    _loadData(); // Load transaction data
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Remove lifecycle observer
    _overlayController.dispose();
    super.dispose();
  }

  // Auto-reload preferences when app comes to foreground or tab is switched
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came to foreground - refresh preferences and data
      _loadUserPreferences();
      _loadData();
    }
  }

  Future<void> _loadUserPreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
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
            _weekStartDay   = data['weekStartDay'] ?? 'Monday';
          });
        }
      } catch (e) {
        print('Error loading user preferences: $e');
      }
    }
  }

  String _getCurrencySymbol(String code) {
    final Map<String, String> symbols = {
      'MYR': 'RM', 'USD': '\$', 'EUR': '€', 'GBP': '£', 'JPY': '¥',
      'AUD': 'A\$', 'CAD': 'C\$', 'CHF': 'CHF', 'CNY': '¥', 'INR': '₹',
      'SGD': 'S\$', 'AED': 'د.إ', 'AFN': '؋',
    };
    return symbols[code] ?? code;
  }

  void _setPresetDateRange() {
    DateTime now = DateTime.now();
    switch (selectedPreset) {
      case 'Day':
        startDate = DateTime(now.year, now.month, now.day);
        endDate = startDate;
        break;
      case 'Week':
        int weekday = now.weekday;
        int daysToSubtract;
        
        if (_weekStartDay == 'Monday') {
          daysToSubtract = weekday - 1;
        } else {
          daysToSubtract = weekday == 7 ? 0 : weekday;
        }
        
        startDate = now.subtract(Duration(days: daysToSubtract));
        startDate = DateTime(startDate.year, startDate.month, startDate.day);
        endDate = startDate.add(const Duration(days: 6));
        break;
      case 'Month':
        startDate = DateTime(selectedYear, selectedMonth, 1);
        endDate = DateTime(selectedYear, selectedMonth + 1, 0);
        break;
      case 'Year':
        startDate = DateTime(now.year, 1, 1);
        endDate = DateTime(now.year, 12, 31);
        break;
      case 'Date Range':
        // Will be set by date picker
        break;
    }
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
    _loadUserPreferences(); // Reload currency!
    _loadData(); // Reload data with new date range
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
    _loadUserPreferences(); // Reload currency!
    _loadData(); // Reload data with new date range
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

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April',
      'May', 'June', 'July', 'August',
      'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  // Load transaction data
  Future<void> _loadData() async {
    setState(() => isLoading = true);
    await Future.wait([
      _fetchExpenses(),
      _fetchIncome(),
      _fetchCategoryBreakdown(),
      _fetchIncomeSourceBreakdown(),
      _fetchBudgetPerformance(),
      _fetchTrendData(),
    ]);
    setState(() => isLoading = false);
  }

  Future<void> _fetchExpenses() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    DateTime endInclusive = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('expenses')
        .where('userID', isEqualTo: user.uid)
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endInclusive)
        .get();

    final rates = await CurrencyService.getRates();
    double expenseSum = 0.0;
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final origAmount   = ((data['originalAmount']   ?? data['amount']) as num).toDouble();
      final origCurrency = (data['originalCurrency'] as String?) ?? _currencyCode;
      expenseSum += CurrencyService.convertSync(origAmount, origCurrency, _currencyCode, rates);
    }

    setState(() {
      totalExpense = expenseSum;
      balance = totalIncome - totalExpense;
    });
  }

  Future<void> _fetchIncome() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    DateTime endInclusive = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('income')
        .where('userID', isEqualTo: user.uid)
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endInclusive)
        .get();

    final rates = await CurrencyService.getRates();
    double incomeSum = 0.0;
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final origAmount   = ((data['originalAmount']   ?? data['amount']) as num).toDouble();
      final origCurrency = (data['originalCurrency'] as String?) ?? _currencyCode;
      incomeSum += CurrencyService.convertSync(origAmount, origCurrency, _currencyCode, rates);
    }

    setState(() {
      totalIncome = incomeSum;
      balance = totalIncome - totalExpense;
    });
  }

  Future<void> _fetchCategoryBreakdown() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    DateTime endInclusive = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('expenses')
        .where('userID', isEqualTo: user.uid)
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endInclusive)
        .get();

    final rates = await CurrencyService.getRates();
    Map<String, double> categoryTotals = {};
    Map<String, int>    categoryTransactionCounts = {};

    for (var doc in snapshot.docs) {
      final data       = doc.data() as Map<String, dynamic>;
      final categoryId = data['categoryID'];
      final origAmount   = ((data['originalAmount']   ?? data['amount']) as num).toDouble();
      final origCurrency = (data['originalCurrency'] as String?) ?? _currencyCode;
      final amount = CurrencyService.convertSync(origAmount, origCurrency, _currencyCode, rates);

      if (categoryId != null) {
        categoryTotals[categoryId] = (categoryTotals[categoryId] ?? 0) + amount;
        categoryTransactionCounts[categoryId] = (categoryTransactionCounts[categoryId] ?? 0) + 1;
      }
    }

    List<Map<String, dynamic>> breakdown = [];
    for (var categoryId in categoryTotals.keys) {
      String categoryName = await getCategoryNameById(categoryId);
      breakdown.add({
        'categoryId':       categoryId,
        'categoryName':     categoryName,
        'amount':           categoryTotals[categoryId]!,
        'transactionCount': categoryTransactionCounts[categoryId]!,
        'percentage':       totalExpense > 0 ? (categoryTotals[categoryId]! / totalExpense) * 100 : 0,
      });
    }

    breakdown.sort((a, b) => b['amount'].compareTo(a['amount']));
    setState(() => expenseByCategory = breakdown);
  }

  Future<void> _fetchIncomeSourceBreakdown() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    DateTime endInclusive = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('income')
        .where('userID', isEqualTo: user.uid)
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endInclusive)
        .get();

    final rates = await CurrencyService.getRates();
    Map<String, double> sourceTotals = {};
    Map<String, int>    sourceTransactionCounts = {};

    for (var doc in snapshot.docs) {
      final data     = doc.data() as Map<String, dynamic>;
      final sourceId = data['incomeSourceID'];
      final origAmount   = ((data['originalAmount']   ?? data['amount']) as num).toDouble();
      final origCurrency = (data['originalCurrency'] as String?) ?? _currencyCode;
      final amount = CurrencyService.convertSync(origAmount, origCurrency, _currencyCode, rates);

      if (sourceId != null) {
        sourceTotals[sourceId] = (sourceTotals[sourceId] ?? 0) + amount;
        sourceTransactionCounts[sourceId] = (sourceTransactionCounts[sourceId] ?? 0) + 1;
      }
    }

    List<Map<String, dynamic>> breakdown = [];
    for (var sourceId in sourceTotals.keys) {
      String sourceName = await getIncomeSourceNameById(sourceId);
      breakdown.add({
        'sourceId':         sourceId,
        'sourceName':       sourceName,
        'amount':           sourceTotals[sourceId]!,
        'transactionCount': sourceTransactionCounts[sourceId]!,
        'percentage':       totalIncome > 0 ? (sourceTotals[sourceId]! / totalIncome) * 100 : 0,
      });
    }

    breakdown.sort((a, b) => b['amount'].compareTo(a['amount']));
    setState(() => incomeBySource = breakdown);
  }

  Future<void> _fetchBudgetPerformance() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Get all budgets for user
    final allBudgets = await fetchBudgets(userId: user.uid);
    
    // Filter budgets by selected duration
    List<Map<String, dynamic>> relevantBudgets = allBudgets.where((budget) {
      final durationType = budget['durationType'];
      return durationType == selectedPreset || 
             (selectedPreset == 'Date Range' && durationType == 'Month'); // Show monthly for custom range
    }).toList();

    List<Map<String, dynamic>> performance = [];

    for (var budget in relevantBudgets) {
      final categoryId = budget['categoryID'];
      final budgetLimit = (budget['budgetLimit'] ?? 0).toDouble();
      
      // Calculate spent for this category in current period
      final spent = await calculateSpentForCategory(
        userId: user.uid,
        categoryId: categoryId,
        startDate: startDate,
        endDate: endDate,
      );

      String categoryName = await getCategoryNameById(categoryId);
      
      performance.add({
        'categoryId': categoryId,
        'categoryName': categoryName,
        'budgetLimit': budgetLimit,
        'spent': spent,
        'percentage': budgetLimit > 0 ? (spent / budgetLimit) * 100 : 0,
        'remaining': budgetLimit - spent,
        'isOverBudget': spent > budgetLimit,
      });
    }

    // Sort by percentage descending
    performance.sort((a, b) => b['percentage'].compareTo(a['percentage']));

    setState(() {
      budgetPerformance = performance;
    });
  }

  Future<void> _fetchTrendData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Determine trend periods based on selected duration
    List<Map<String, dynamic>> expenseTrend = [];
    List<Map<String, dynamic>> incomeTrend = [];

    if (selectedPreset == 'Day') {
      // Last 7 days
      for (int i = 6; i >= 0; i--) {
        DateTime day = DateTime.now().subtract(Duration(days: i));
        DateTime dayStart = DateTime(day.year, day.month, day.day);
        DateTime dayEnd = DateTime(day.year, day.month, day.day, 23, 59, 59);
        
        double dayExpense = await _fetchTotalForPeriod('expenses', dayStart, dayEnd);
        double dayIncome = await _fetchTotalForPeriod('income', dayStart, dayEnd);
        
        expenseTrend.add({'label': '${day.day}/${day.month}', 'value': dayExpense});
        incomeTrend.add({'label': '${day.day}/${day.month}', 'value': dayIncome});
      }
    } else if (selectedPreset == 'Week') {
      // Last 4 weeks
      for (int i = 3; i >= 0; i--) {
        DateTime weekEnd = DateTime.now().subtract(Duration(days: i * 7));
        DateTime weekStart = weekEnd.subtract(const Duration(days: 6));
        
        double weekExpense = await _fetchTotalForPeriod('expenses', weekStart, weekEnd);
        double weekIncome = await _fetchTotalForPeriod('income', weekStart, weekEnd);
        
        expenseTrend.add({'label': 'W${4-i}', 'value': weekExpense});
        incomeTrend.add({'label': 'W${4-i}', 'value': weekIncome});
      }
    } else if (selectedPreset == 'Month') {
      // Last 6 months
      for (int i = 5; i >= 0; i--) {
        DateTime month = DateTime(DateTime.now().year, DateTime.now().month - i, 1);
        DateTime monthStart = DateTime(month.year, month.month, 1);
        DateTime monthEnd = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
        
        double monthExpense = await _fetchTotalForPeriod('expenses', monthStart, monthEnd);
        double monthIncome = await _fetchTotalForPeriod('income', monthStart, monthEnd);
        
        expenseTrend.add({'label': _monthName(month.month).substring(0, 3), 'value': monthExpense});
        incomeTrend.add({'label': _monthName(month.month).substring(0, 3), 'value': monthIncome});
      }
    } else if (selectedPreset == 'Year') {
      // Last 3 years
      for (int i = 2; i >= 0; i--) {
        int year = DateTime.now().year - i;
        DateTime yearStart = DateTime(year, 1, 1);
        DateTime yearEnd = DateTime(year, 12, 31, 23, 59, 59);
        
        double yearExpense = await _fetchTotalForPeriod('expenses', yearStart, yearEnd);
        double yearIncome = await _fetchTotalForPeriod('income', yearStart, yearEnd);
        
        expenseTrend.add({'label': year.toString(), 'value': yearExpense});
        incomeTrend.add({'label': year.toString(), 'value': yearIncome});
      }
    }

    setState(() {
      expenseTrendData = expenseTrend;
      incomeTrendData = incomeTrend;
    });
  }

  Future<double> _fetchTotalForPeriod(
      String collection, DateTime start, DateTime end) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0.0;

    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection(collection)
        .where('userID', isEqualTo: user.uid)
        .where('date', isGreaterThanOrEqualTo: start)
        .where('date', isLessThanOrEqualTo: end)
        .get();

    final rates = await CurrencyService.getRates();
    double total = 0.0;
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final origAmount   = ((data['originalAmount']   ?? data['amount']) as num).toDouble();
      final origCurrency = (data['originalCurrency'] as String?) ?? _currencyCode;
      total += CurrencyService.convertSync(origAmount, origCurrency, _currencyCode, rates);
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EEF1),
      appBar: AppBar(
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
              const Icon(Icons.arrow_drop_down, color: Colors.black, size: 20),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Tab selector and Download button
              _buildTopControls(),
              
              // Content area
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Transaction Summary Card
                      if (isLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else ...[
                        _summaryCard(
                          totalIncome > 0
                              ? (totalExpense / totalIncome).clamp(0.0, 1.0)
                              : 0.0,
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Content based on selected tab
                        if (selectedTab == 0) ...[
                          // EXPENSE TAB
                          if (expenseByCategory.isNotEmpty)
                            _buildExpensePieChart(),
                          
                          const SizedBox(height: 16),
                          
                          if (expenseTrendData.isNotEmpty)
                            _buildTrendChart('Spending Trend', expenseTrendData),
                          
                          const SizedBox(height: 16),
                          
                          if (expenseByCategory.isNotEmpty)
                            _buildCategoryList(),
                          
                          const SizedBox(height: 16),
                          
                          _buildInsights(),
                        ] else if (selectedTab == 1) ...[
                          // INCOME TAB
                          if (incomeBySource.isNotEmpty)
                            _buildIncomePieChart(),
                          
                          const SizedBox(height: 16),
                          
                          if (incomeTrendData.isNotEmpty)
                            _buildTrendChart('Income Trend', incomeTrendData),
                          
                          const SizedBox(height: 16),
                          
                          if (incomeBySource.isNotEmpty)
                            _buildSourceList(),
                          
                          const SizedBox(height: 16),
                          
                          _buildInsights(),
                        ] else ...[
                          // BUDGET TAB - Using separated widget
                          BudgetReportTab(
                            currencySymbol: _currencySymbol,
                            currencyCode:   _currencyCode,
                            weekStartDay:   _weekStartDay,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (showDateOverlay) _buildDateOverlay(),
        ],
      ),
    );
  }

  Widget _buildTopControls() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          // Tab selector (3 tabs)
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedTab = 0; // Expense
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: selectedTab == 0
                          ? const Color(0xFF4A6B7C)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selectedTab == 0
                            ? const Color(0xFF4A6B7C)
                            : Colors.grey[300]!,
                      ),
                    ),
                    child: Text(
                      'Expense',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: selectedTab == 0 ? Colors.white : Colors.grey[700],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedTab = 1; // Income
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: selectedTab == 1
                          ? const Color(0xFF4A6B7C)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selectedTab == 1
                            ? const Color(0xFF4A6B7C)
                            : Colors.grey[300]!,
                      ),
                    ),
                    child: Text(
                      'Income',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: selectedTab == 1 ? Colors.white : Colors.grey[700],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedTab = 2; // Budget
                    });
                    // Budget tab widget handles its own data loading
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: selectedTab == 2
                          ? const Color(0xFF4A6B7C)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selectedTab == 2
                            ? const Color(0xFF4A6B7C)
                            : Colors.grey[300]!,
                      ),
                    ),
                    child: Text(
                      'Analysis',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: selectedTab == 2 ? Colors.white : Colors.grey[700],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Download PDF button (shown for all tabs: Expense, Income, Analysis)
          ElevatedButton.icon(
            onPressed: isLoading ? null : () async {
              try {
                // Show loading
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Generating PDF...')),
                );

                // Generate PDF
                await ReportPDFGenerator.generateAndDownloadPDF(
                  startDate: startDate,
                  endDate: endDate,
                  isExpense: selectedTab == 0,
                  isAnalysis: selectedTab == 2,   // NEW
                  selectedPreset: selectedPreset,
                  currencySymbol: _currencySymbol,
                  currencyCode: _currencyCode,
                  weekStartDay: _weekStartDay,     // NEW
                  totalIncome: totalIncome,
                  totalExpense: totalExpense,
                  balance: balance,
                  categoryBreakdown: selectedTab == 0
                      ? expenseByCategory
                      : selectedTab == 1
                          ? incomeBySource
                          : [],
                  budgetPerformance: budgetPerformance,
                );

                // Success message
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('PDF generated successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                print('Error generating PDF: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error generating PDF: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.download, size: 16),
            label: const Text('PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A6B7C),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
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
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'DATE RANGE',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
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
                      
                      // Month Picker for Month preset (matching home page design)
                      if (selectedPreset == 'Month') ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Select Month:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        // Compact month grid (4 rows x 3 columns) - same as home page
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 2.3,
                            crossAxisSpacing: 6,
                            mainAxisSpacing: 8,
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
                                  _loadData();
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF4A6B7C) : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFF4A6B7C) : Colors.grey[300]!,
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
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
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
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
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
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
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
              'Transaction Summary',
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

  // Budget Performance Widget
  Widget _buildBudgetPerformance() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Budget Performance',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...budgetPerformance.map((budget) {
            final percentage = budget['percentage'] as double;
            final isOver = budget['isOverBudget'] as bool;
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        budget['categoryName'],
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isOver ? Colors.red : Colors.black87,
                        ),
                      ),
                      Text(
                        '${percentage.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isOver ? Colors.red : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '$_currencySymbol ${budget['spent'].toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        ' / $_currencySymbol ${budget['budgetLimit'].toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (percentage / 100).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: Colors.grey[200],
                      color: isOver ? Colors.red : const Color(0xFF4A6B7C),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // Expense Pie Chart
  Widget _buildExpensePieChart() {
    List<PieChartSectionData> sections = expenseByCategory.take(5).map((category) {
      final index = expenseByCategory.indexOf(category);
      final colors = [
        const Color(0xFFFF6B9D), // Pink
        const Color(0xFF26C6DA), // Light Blue
        const Color(0xFFFFB74D), // Orange
        const Color(0xFFAB47BC), // Purple
        const Color(0xFF66BB6A), // Green
      ];
      
      return PieChartSectionData(
        color: colors[index % colors.length],
        value: category['amount'],
        title: '${category['percentage'].toStringAsFixed(1)}%',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Expenses Breakdown',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 40,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...expenseByCategory.take(5).map((category) {
            final index = expenseByCategory.indexOf(category);
            final colors = [
              const Color(0xFFFF6B9D), // Pink - matches pie chart
              const Color(0xFF26C6DA), // Light Blue - matches pie chart
              const Color(0xFFFFB74D), // Orange - matches pie chart
              const Color(0xFFAB47BC), // Purple - matches pie chart
              const Color(0xFF66BB6A), // Green - matches pie chart
            ];
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors[index % colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(category['categoryName']),
                  const Spacer(),
                  Text(
                    '$_currencySymbol ${category['amount'].toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // Income Pie Chart
  Widget _buildIncomePieChart() {
    List<PieChartSectionData> sections = incomeBySource.take(5).map((source) {
      final index = incomeBySource.indexOf(source);
      final colors = [
        const Color(0xFF66BB6A), // Green
        const Color(0xFFFFB74D), // Orange  
        const Color(0xFF42A5F5), // Blue
        const Color(0xFFFF6B9D), // Pink
        const Color(0xFF26C6DA), // Light Blue
      ];
      
      return PieChartSectionData(
        color: colors[index % colors.length],
        value: source['amount'],
        title: '${source['percentage'].toStringAsFixed(1)}%',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Income Sources Breakdown',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 40,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...incomeBySource.take(5).map((source) {
            final index = incomeBySource.indexOf(source);
            final colors = [
              const Color(0xFF66BB6A), // Green - matches pie chart
              const Color(0xFFFFB74D), // Orange - matches pie chart
              const Color(0xFF42A5F5), // Blue - matches pie chart
              const Color(0xFFFF6B9D), // Pink - matches pie chart
              const Color(0xFF26C6DA), // Light Blue - matches pie chart
            ];
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors[index % colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(source['sourceName']),
                  const Spacer(),
                  Text(
                    '$_currencySymbol ${source['amount'].toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // Trend Line Chart
  Widget _buildTrendChart(String title, List<Map<String, dynamic>> trendData) {
    if (trendData.isEmpty) return const SizedBox();

    double maxValue = trendData.map((e) => e['value'] as double).reduce((a, b) => a > b ? a : b);
    if (maxValue == 0) maxValue = 1;

    List<FlSpot> spots = [];
    for (int i = 0; i < trendData.length; i++) {
      spots.add(FlSpot(i.toDouble(), trendData[i]['value']));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: const TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        int index = value.toInt();
                        if (index >= 0 && index < trendData.length) {
                          return Text(
                            trendData[index]['label'],
                            style: const TextStyle(fontSize: 10),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: const Color(0xFF4A6B7C),
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF4A6B7C).withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Category List
  Widget _buildCategoryList() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Expenses by Category',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...expenseByCategory.map((category) {
            final iconColor = getCategoryIconColor(category['categoryName']);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: iconColor['color'].withOpacity(0.2),
                    radius: 20,
                    child: Icon(
                      iconColor['icon'],
                      color: iconColor['color'],
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category['categoryName'],
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${category['transactionCount']} transactions',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '-$_currencySymbol ${category['amount'].toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // Source List
  Widget _buildSourceList() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Income by Source',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...incomeBySource.map((source) {
            final iconColor = getIncomeIconColor(source['sourceName']);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: iconColor['color'].withOpacity(0.2),
                    radius: 20,
                    child: Icon(
                      iconColor['icon'],
                      color: iconColor['color'],
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          source['sourceName'],
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${source['transactionCount']} transactions',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '+$_currencySymbol ${source['amount'].toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF66BB6A),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // Insights Widget
  Widget _buildInsights() {
    List<Widget> insights = [];

    // Transaction count insight — simple, tab-aware, no budget framing
    if (selectedTab == 0 && expenseByCategory.isNotEmpty) {
      final totalTransactions = expenseByCategory.fold<int>(
        0, (sum, cat) => sum + (cat['transactionCount'] as int? ?? 0));
      insights.add(_buildInsightItem(
        '▲', Colors.blueGrey,
        'You made $totalTransactions expense transaction${totalTransactions == 1 ? '' : 's'} this period'
      ));
    } else if (selectedTab == 1 && incomeBySource.isNotEmpty) {
      final totalTransactions = incomeBySource.fold<int>(
        0, (sum, src) => sum + (src['transactionCount'] as int? ?? 0));
      insights.add(_buildInsightItem(
        '▲', Colors.blueGrey,
        'You made $totalTransactions income transaction${totalTransactions == 1 ? '' : 's'} this period'
      ));
    }

    // Top category insight
    if (selectedTab == 0 && expenseByCategory.isNotEmpty) {
      final topCategory = expenseByCategory.first;
      insights.add(_buildInsightItem(
        '■', Colors.red, 
        '${topCategory['categoryName']} is your top expense'
      ));
    } else if (selectedTab == 1 && incomeBySource.isNotEmpty) {
      final topSource = incomeBySource.first;
      insights.add(_buildInsightItem(
        '♦', Colors.blue, 
        '${topSource['sourceName']} is your main income source'
      ));
    }

    if (insights.isEmpty) {
      insights.add(_buildInsightItem(
        '◆', Colors.grey, 
        'Start tracking to see insights!'
      ));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Insights',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...insights,
        ],
      ),
    );
  }

  Widget _buildInsightItem(String shape, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            child: Text(
              shape,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}