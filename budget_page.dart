import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'add_budget_page.dart';
import 'edit_budget_page.dart';
import 'budget_helper.dart';
import 'category_helper.dart';
import 'currency_service.dart';

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});

  @override
  State<BudgetPage> createState() => BudgetPageState();
}

class BudgetPageState extends State<BudgetPage> with WidgetsBindingObserver {
  String selectedDuration = 'Monthly';
  final List<String> durations = ['Weekly', 'Monthly', 'Yearly'];

  List<Map<String, dynamic>> budgets = [];
  bool isLoading = true;

  // User preferences
  String _currencySymbol = 'RM';
  String _currencyCode   = 'MYR';
  String _weekStartDay   = 'Monday';

  // Stream subscription for user prefs — updates instantly when settings change
  StreamSubscription? _userPrefsSubscription;

  // Totals for summary card
  double totalBudgetLimit = 0.0;
  double totalSpent = 0.0;

  // Icon/color lookup now comes from category_helper.dart's centralized
  // getCategoryIconColor() instead of this local map.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToUserPrefs(); // reactive stream — no manual reload needed
    _loadBudgets();
  }

  @override
  void dispose() {
    _userPrefsSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadBudgets();
    }
  }

  // Public method that parent can call to refresh
  void refresh() {
    if (mounted) _loadBudgets();
  }

  // Stream listener — fires immediately when Firestore user doc changes
  // (e.g. user updates currency in Settings)
  void _listenToUserPrefs() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _userPrefsSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || doc.data() == null || !mounted) return;
      final data         = doc.data()!;
      final newCode      = data['currency']    ?? 'MYR';
      final newSymbol    = _getCurrencySymbol(newCode);
      final newWeekStart = data['weekStartDay'] ?? 'Monday';
      final weekChanged  = newWeekStart != _weekStartDay;
      final codeChanged  = newCode != _currencyCode;
      setState(() {
        _currencyCode   = newCode;
        _currencySymbol = newSymbol;
        _weekStartDay   = newWeekStart;
      });
      if (weekChanged || codeChanged) _loadBudgets();
    });
  }

  String _getCurrencySymbol(String code) {
    final Map<String, String> symbols = {
      'MYR': 'RM',
      'USD': '\$',
      'EUR': '€',
      'GBP': '£',
      'JPY': '¥',
      'AUD': 'A\$',
      'CAD': 'C\$',
      'SGD': 'S\$',
      'INR': '₹',
    };
    return symbols[code] ?? code;
  }

  Future<void> _loadBudgets() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => isLoading = false);
      return;
    }

    setState(() => isLoading = true);

    try {
      final fetchedBudgets = await fetchBudgets(
        userId: user.uid,
        durationType: selectedDuration,
      );

      final dateRange = getDateRangeForDuration(selectedDuration, _weekStartDay);
      final startDate = dateRange['start']!;
      final endDate   = dateRange['end']!;

      // Fetch rates once for all conversions
      final rates = await CurrencyService.getRates();

      // Convert and sum budget limits
      double limitSum = 0.0;
      for (var b in fetchedBudgets) {
        final origLimit    = (b['originalBudgetLimit'] ?? b['budgetLimit'] as num).toDouble();
        final origCurrency = (b['originalCurrency'] as String?) ?? _currencyCode;
        limitSum += CurrencyService.convertSync(origLimit, origCurrency, _currencyCode, rates);
      }
      totalBudgetLimit = limitSum;

      // Total spent — converted
      double spentSum = 0.0;
      for (var b in fetchedBudgets) {
        spentSum += await calculateSpentForCategory(
          userId: user.uid,
          categoryId: b['categoryID'],
          startDate: startDate,
          endDate: endDate,
          targetCurrency: _currencyCode,
          rates: rates,
        );
      }
      totalSpent = spentSum;

      // Per-budget details
      List<Map<String, dynamic>> budgetsWithDetails = [];
      for (var budget in fetchedBudgets) {
        final categoryName = await getCategoryNameById(budget['categoryID']);

        final origLimit    = (budget['originalBudgetLimit'] ?? budget['budgetLimit'] as num).toDouble();
        final origCurrency = (budget['originalCurrency'] as String?) ?? _currencyCode;
        final displayLimit = CurrencyService.convertSync(origLimit, origCurrency, _currencyCode, rates);

        final spent = await calculateSpentForCategory(
          userId: user.uid,
          categoryId: budget['categoryID'],
          startDate: startDate,
          endDate: endDate,
          targetCurrency: _currencyCode,
          rates: rates,
        );

        budgetsWithDetails.add({
          'id':                  budget['id'],
          'userID':              budget['userID'],
          'categoryID':          budget['categoryID'],
          'budgetLimit':         displayLimit,
          'originalBudgetLimit': origLimit,
          'originalCurrency':    origCurrency,
          'durationType':        budget['durationType'],
          'createdAt':           budget['createdAt'],
          'categoryName':        categoryName,
          'spent':               spent.toDouble(),
        });
      }

      setState(() {
        budgets   = budgetsWithDetails;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading budgets: $e');
      setState(() => isLoading = false);
    }
  }

  Map<String, dynamic> _getIconColor(String categoryName) {
    return getCategoryIconColor(categoryName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EEF1),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Budgets',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddBudgetPage()),
          );
          _loadBudgets();
        },
        backgroundColor: const Color(0xFF4A6B7C),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Budget',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Top bar — duration chips only
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: durations.map((duration) {
                final isSelected = selectedDuration == duration;
                return GestureDetector(
                  onTap: () {
                    setState(() => selectedDuration = duration);
                    _loadBudgets();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF4A6B7C) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF4A6B7C) : Colors.grey[300]!,
                      ),
                    ),
                    child: Text(
                      duration,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : Colors.grey[700],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Content
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : budgets.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadBudgets, // Pull down to refresh!
                        child: _buildBudgetList(),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No $selectedDuration Budgets',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Add Budget" below to get started',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetList() {
    return SingleChildScrollView(
      // Extra bottom padding so the last card can scroll clear of the
      // floating "Add Budget" button instead of sitting underneath it.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total budget summary card
          _buildTotalBudgetCard(),
          const SizedBox(height: 20),

          // Category label
          const Text(
            'Category',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 12),

          // Category budget cards
          ...budgets.map((budget) => _buildCategoryBudgetCard(budget)),
        ],
      ),
    );
  }

  Widget _buildTotalBudgetCard() {
    final spentDouble = totalSpent.toDouble();
    final limitDouble = totalBudgetLimit.toDouble();
    final remaining = limitDouble - spentDouble;
    final isOverBudget = spentDouble > limitDouble;

    final percentage = limitDouble > 0
        ? ((spentDouble / limitDouble) * 100).clamp(0, 999)
        : 0.0;

    final progressColor = isOverBudget ? Colors.red[400]! : const Color(0xFF4A6B7C);
    final cardColor = isOverBudget
        ? const Color(0xFFFFEBEE)
        : const Color(0xFFDCEAEE);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$selectedDuration Budget Overview',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              if (isOverBudget)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Over Budget',
                    style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Spent', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 2),
                  Text(
                    '$_currencySymbol ${spentDouble.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isOverBudget ? Colors.red[700] : Colors.black87,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Total Limit', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 2),
                  Text(
                    '$_currencySymbol ${limitDouble.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: limitDouble > 0 ? (spentDouble / limitDouble).clamp(0.0, 1.0) : 0.0,
              minHeight: 10,
              backgroundColor: Colors.white.withOpacity(0.6),
              color: progressColor,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${percentage.toStringAsFixed(0)}% used',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isOverBudget ? Colors.red[700] : Colors.black54,
                ),
              ),
              Text(
                isOverBudget
                    ? '$_currencySymbol ${(-remaining).toStringAsFixed(2)} over'
                    : '$_currencySymbol ${remaining.toStringAsFixed(2)} left',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isOverBudget ? Colors.red[700] : const Color(0xFF4A6B7C),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBudgetCard(Map<String, dynamic> budget) {
    final categoryName = budget['categoryName'] ?? 'Unknown';
    final spent = (budget['spent'] ?? 0).toDouble();
    final budgetLimit = (budget['budgetLimit'] ?? 0).toDouble();
    final remaining = budgetLimit - spent;
    final isOverBudget = spent > budgetLimit;
    final isNearLimit = !isOverBudget && budgetLimit > 0 && (spent / budgetLimit) >= 0.8;

    final iconData = _getIconColor(categoryName);
    final percentage = budgetLimit > 0 ? ((spent / budgetLimit) * 100).clamp(0, 999) : 0.0;
    final progressColor = isOverBudget
        ? Colors.red[400]!
        : isNearLimit
            ? Colors.orange[400]!
            : const Color(0xFF4A6B7C);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EditBudgetPage(budget: budget)),
          );
          _loadBudgets();
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (iconData['color'] as Color).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(iconData['icon'], color: iconData['color'], size: 24),
                  ),
                  const SizedBox(width: 12),
                  // Name + spent/limit
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              categoryName,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            // Status badge
                            if (isOverBudget)
                              _statusBadge('Over', Colors.red)
                            else if (isNearLimit)
                              _statusBadge('Near limit', Colors.orange),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$_currencySymbol ${spent.toStringAsFixed(2)} spent',
                              style: TextStyle(
                                fontSize: 13,
                                color: isOverBudget ? Colors.red[600] : Colors.grey[600],
                                fontWeight: isOverBudget ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                            Text(
                              'of $_currencySymbol ${budgetLimit.toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: budgetLimit > 0 ? (spent / budgetLimit).clamp(0.0, 1.0) : 0.0,
                  minHeight: 7,
                  backgroundColor: Colors.grey[100],
                  color: progressColor,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${percentage.toStringAsFixed(0)}% used',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  Text(
                    isOverBudget
                        ? '$_currencySymbol ${(-remaining).toStringAsFixed(2)} over'
                        : '$_currencySymbol ${remaining.toStringAsFixed(2)} left',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isOverBudget ? Colors.red[600] : const Color(0xFF4A6B7C),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}