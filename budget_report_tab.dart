import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import '../budget_helper.dart';
import '../category_helper.dart';
import '../currency_service.dart';

class BudgetReportTab extends StatefulWidget {
  final String currencySymbol;
  final String currencyCode;
  final String weekStartDay;

  const BudgetReportTab({
    super.key,
    required this.currencySymbol,
    required this.currencyCode,
    required this.weekStartDay,
  });

  @override
  State<BudgetReportTab> createState() => _BudgetReportTabState();
}

class _BudgetReportTabState extends State<BudgetReportTab> {
  // Budget tab data
  List<Map<String, dynamic>> allBudgets = [];
  bool isBudgetLoading = true;
  
  // Phase 2: Historical and savings data
  Map<String, List<Map<String, dynamic>>> budgetHistory = {};
  double totalBudgetSavings = 0.0;
  double totalBudgeted = 0.0;
  double totalSpent = 0.0;
  double savingsRate = 0.0;
  
  // Phase 3: Insights and comparisons
  // Each already includes its duration (e.g. "Food & Dining (Monthly)")
  // since the same category name can exist across Weekly/Monthly/Yearly
  // budgets — and may join multiple categories with '&' on a genuine tie.
  String? bestPerformer;
  String? needsAttention;
  // Budget health is calculated PER duration category (Weekly / Monthly / Yearly)
  // instead of one blended number — mixing periods of different lengths together
  // hides real problems (e.g. a steady yearly budget can mask a struggling weekly one).
  Map<String, Map<String, dynamic>> budgetHealthByCategory = {};
  List<String> recommendations = [];
  Map<String, Map<String, dynamic>> periodComparisons = {};

  // User preferences (passed from parent)
  String get _currencySymbol => widget.currencySymbol;
  String get _currencyCode   => widget.currencyCode;
  String get _weekStartDay   => widget.weekStartDay;

  @override
  void initState() {
    super.initState();
    _loadBudgetsForTab();
  }

  Future<void> _loadBudgetsForTab() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => isBudgetLoading = false);
      return;
    }

    setState(() => isBudgetLoading = true);

    try {
      // Fetch all budgets
      final fetchedBudgets = await fetchBudgets(userId: user.uid);

      // Fetch rates once for all conversions
      final rates = await CurrencyService.getRates();

      // For each budget, calculate current spending
      List<Map<String, dynamic>> budgetsWithDetails = await Future.wait(
        fetchedBudgets.map((budget) async {
          final categoryName = await getCategoryNameById(budget['categoryID']);
          final durationType = budget['durationType'] ?? 'Monthly';
          
          final dateRange = getDateRangeForDuration(durationType, _weekStartDay);
          final startDate = dateRange['start']!;
          final endDate   = dateRange['end']!;
          
          // Convert budget limit from original currency
          final origLimit    = (budget['originalBudgetLimit'] ?? budget['budgetLimit'] as num).toDouble();
          final origCurrency = (budget['originalCurrency'] as String?) ?? _currencyCode;
          final displayLimit = CurrencyService.convertSync(origLimit, origCurrency, _currencyCode, rates);

          // Spent amount converted to user's currency
          final spent = await calculateSpentForCategory(
            userId: user.uid,
            categoryId: budget['categoryID'],
            startDate: startDate,
            endDate: endDate,
            targetCurrency: _currencyCode,
            rates: rates,
          );

          return {
            'id':           budget['id'],
            'categoryID':   budget['categoryID'],
            'categoryName': categoryName,
            'budgetLimit':  displayLimit,
            'durationType': durationType,
            'spent':        spent.toDouble(),
            'createdAt':    budget['createdAt'],
          };
        }).toList(),
      );

      setState(() {
        allBudgets = budgetsWithDetails;
        isBudgetLoading = false;
      });
      
      // Phase 2: Load historical data and calculate savings
      await _loadHistoricalDataForBudgets();
      _calculateSavingsRate();
      
      // Phase 3: Generate insights and comparisons
      await _calculatePeriodComparisons();
      _generateSmartInsights();
      _calculateHealthByCategory();
      _generateRecommendations();
      
    } catch (e) {
      print('Error loading budgets: $e');
      setState(() => isBudgetLoading = false);
    }
  }

  Future<void> _loadHistoricalDataForBudgets() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Fetch rates once for all period calculations
    final rates = await CurrencyService.getRates();

    Map<String, List<Map<String, dynamic>>> historyData = {};

    for (var budget in allBudgets) {
      final budgetId   = budget['id'];
      final categoryId = budget['categoryID'];
      final durationType = budget['durationType'];
      final createdAt  = budget['createdAt'];
      final limit      = budget['budgetLimit'] as double; // already converted

      int periodsToAnalyze = _getPeriodsToAnalyze(durationType, createdAt);
      List<Map<String, dynamic>> periods = [];

      for (int i = 0; i < periodsToAnalyze; i++) {
        final periodRange = _getPeriodRange(durationType, i);

        final spent = await calculateSpentForCategory(
          userId: user.uid,
          categoryId: categoryId,
          startDate: periodRange['start']!,
          endDate: periodRange['end']!,
          targetCurrency: _currencyCode,
          rates: rates,
        );

        final percentage = limit > 0 ? (spent / limit) * 100 : 0;

        periods.add({
          'periodLabel': periodRange['label'],
          'spent':       spent,
          'limit':       limit,
          'percentage':  percentage,
          'isUnder':     percentage < 100,
        });
      }

      historyData[budgetId] = periods.reversed.toList();
    }

    setState(() => budgetHistory = historyData);
  }

  // Always show full window — 6 months / 4 weeks / 3 years
  // Periods before budget creation will simply show 0 spent
  int _getPeriodsToAnalyze(String durationType, dynamic createdAt) {
    if (durationType == 'Monthly') return 6;
    if (durationType == 'Weekly')  return 4;
    return 3; // Yearly
  }

  // Get date range for a specific period (0 = current, 1 = last period, etc.)
  Map<String, dynamic> _getPeriodRange(String durationType, int periodsAgo) {
    final now = DateTime.now();

    if (durationType == 'Monthly') {
      final targetMonth = DateTime(now.year, now.month - periodsAgo, 1);
      final start = DateTime(targetMonth.year, targetMonth.month, 1);
      final end = DateTime(targetMonth.year, targetMonth.month + 1, 0);
      
      return {
        'start': start,
        'end': end,
        'label': '${_getMonthName(targetMonth.month)} ${targetMonth.year}',
      };
    } else if (durationType == 'Weekly') {
      final daysToSubtract = periodsAgo * 7;
      final targetDate = now.subtract(Duration(days: daysToSubtract));
      final dateRange = getDateRangeForDuration('Weekly', _weekStartDay);
      
      // Adjust for the specific week
      final weekStart = dateRange['start']!.subtract(Duration(days: daysToSubtract));
      final weekEnd = dateRange['end']!.subtract(Duration(days: daysToSubtract));
      
      return {
        'start': weekStart,
        'end': weekEnd,
        'label': 'Week ${periodsAgo == 0 ? "Now" : "$periodsAgo ago"}',
      };
    } else { // Yearly
      final targetYear = now.year - periodsAgo;
      return {
        'start': DateTime(targetYear, 1, 1),
        'end': DateTime(targetYear, 12, 31),
        'label': targetYear.toString(),
      };
    }
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                   'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  // Phase 2: Calculate total savings rate
  void _calculateSavingsRate() {
    double budgeted = 0.0;
    double spent = 0.0;

    for (var budget in allBudgets) {
      budgeted += budget['budgetLimit'] as double;
      spent += budget['spent'] as double;
    }

    final savings = budgeted - spent;
    final rate = budgeted > 0 ? (savings / budgeted) * 100 : 0.0;

    setState(() {
      totalBudgeted = budgeted;
      totalSpent = spent;
      totalBudgetSavings = savings;
      savingsRate = rate;
    });
  }

  // Phase 3: Calculate period comparisons (current vs previous)
  Future<void> _calculatePeriodComparisons() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final rates = await CurrencyService.getRates();
    Map<String, Map<String, dynamic>> comparisons = {};

    for (var budget in allBudgets) {
      final budgetId    = budget['id'];
      final categoryId  = budget['categoryID'];
      final durationType = budget['durationType'];
      final currentSpent = budget['spent'] as double;
      final limit        = budget['budgetLimit'] as double;
      
      final prevPeriod = _getPeriodRange(durationType, 1);
      
      final prevSpent = await calculateSpentForCategory(
        userId: user.uid,
        categoryId: categoryId,
        startDate: prevPeriod['start']!,
        endDate: prevPeriod['end']!,
        targetCurrency: _currencyCode,
        rates: rates,
      );

      final currentPercentage = limit > 0 ? (currentSpent / limit) * 100 : 0;
      final prevPercentage    = limit > 0 ? (prevSpent   / limit) * 100 : 0;
      final change            = currentPercentage - prevPercentage;
      final isImprovement     = change < 0;

      comparisons[budgetId] = {
        'previousSpent':      prevSpent,
        'previousPercentage': prevPercentage,
        'change':             change,
        'isImprovement':      isImprovement,
        'periodLabel':        prevPeriod['label'],
      };
    }

    setState(() => periodComparisons = comparisons);
  }

  // Phase 3: Generate smart insights
  void _generateSmartInsights() {
    if (allBudgets.isEmpty || budgetHistory.isEmpty) return;

    // Require at least 3 tracked periods before a category is eligible to
    // be named "best" or "needs attention" — a single lucky/unlucky period
    // isn't a reliable enough signal to call out by name.
    const minPeriodsForInsight = 3;

    // Score every eligible budget first, then pick ALL budgets tied at
    // the top (or bottom) score — instead of just the first one
    // encountered, which would be an arbitrary pick on a genuine tie.
    List<Map<String, dynamic>> scored = [];

    for (var budget in allBudgets) {
      final budgetId = budget['id'];
      final categoryName = budget['categoryName'];
      final durationType = budget['durationType'];
      final history = budgetHistory[budgetId];

      if (history == null || history.length < minPeriodsForInsight) continue;

      final underBudgetCount = history.where((p) => p['isUnder']).length;
      final avgPercentage = history.map((p) => p['percentage'] as double).reduce((a, b) => a + b) / history.length;

      // Reward a high success rate AND low average usage — staying safely
      // under budget is "best", not landing close to 50% usage.
      final successRate = (underBudgetCount / history.length) * 100;
      final score = successRate - (avgPercentage * 0.3);

      scored.add({
        'label': '$categoryName ($durationType)',
        'score': score,
        'underBudgetCount': underBudgetCount,
        'periodCount': history.length,
        'avgPercentage': avgPercentage,
      });
    }

    // Best performers: highest score — ties all get named, joined together.
    List<String> bestList = [];
    if (scored.isNotEmpty) {
      final maxScore = scored.map((s) => s['score'] as double).reduce((a, b) => a > b ? a : b);
      bestList = scored
          .where((s) => (s['score'] as double) >= maxScore - 0.0001)
          .map((s) => s['label'] as String)
          .toList();
    }

    // "Needs attention": failed to stay under budget more than half the
    // time, and among those struggling, the highest average usage —
    // ties all get named too.
    final struggling = scored
        .where((s) => (s['underBudgetCount'] as int) < (s['periodCount'] as int) * 0.5)
        .toList();
    List<String> worstList = [];
    if (struggling.isNotEmpty) {
      final maxAvg = struggling.map((s) => s['avgPercentage'] as double).reduce((a, b) => a > b ? a : b);
      worstList = struggling
          .where((s) => (s['avgPercentage'] as double) >= maxAvg - 0.0001)
          .map((s) => s['label'] as String)
          .toList();
    }

    setState(() {
      bestPerformer = bestList.isEmpty ? null : bestList.join(' & ');
      needsAttention = worstList.isEmpty ? null : worstList.join(' & ');
    });
  }

  // Phase 3: Calculate budget health PER DURATION CATEGORY.
  //
  // Why per-category instead of one number: a weekly budget resets 52x/year,
  // a yearly budget resets once. Blending their periods into one success rate
  // means a perfectly steady yearly budget can hide a genuinely struggling
  // weekly one (or the reverse) — the result stops meaning anything concrete.
  //
  // "Healthy" here means: adherence (% of past periods spent within limit) is
  // high AND the category isn't chronically running over. Thresholds are based
  // on the common budget-variance tolerance convention (~5–10% over/under is
  // treated as "on track" in management accounting) translated into adherence
  // terms — they are a starting point, not a final answer; calibrate with real
  // user data if you can before defending the exact cutoffs.
  void _calculateHealthByCategory() {
    const categories = ['Weekly', 'Monthly', 'Yearly'];
    Map<String, Map<String, dynamic>> result = {};

    for (final category in categories) {
      final budgetsInCategory =
          allBudgets.where((b) => b['durationType'] == category).toList();

      if (budgetsInCategory.isEmpty) {
        result[category] = {
          'status': 'No Data',
          'score': null,
          'successRate': null,
          'savingsRate': null,
          'periodCount': 0,
          'budgetCount': 0,
        };
        continue;
      }

      int totalPeriods = 0;
      int successfulPeriods = 0;
      double categoryBudgeted = 0.0;
      double categorySpent = 0.0;

      for (final budget in budgetsInCategory) {
        categoryBudgeted += budget['budgetLimit'] as double;
        categorySpent += budget['spent'] as double;

        final history = budgetHistory[budget['id']];
        if (history != null && history.isNotEmpty) {
          totalPeriods += history.length;
          successfulPeriods += history.where((p) => p['isUnder']).length;
        }
      }

      final successRate =
          totalPeriods > 0 ? (successfulPeriods / totalPeriods) * 100 : 0.0;

      final categorySavingsRate = categoryBudgeted > 0
          ? ((categoryBudgeted - categorySpent) / categoryBudgeted) * 100
          : 0.0;

      final savingsScore = categorySavingsRate.clamp(-50, 50);
      final combinedScore = (successRate * 0.7) + (savingsScore * 0.3);

      String status;
      if (combinedScore >= 80) {
        status = 'Healthy';
      } else if (combinedScore >= 65) {
        status = 'Caution';
      } else if (combinedScore >= 50) {
        status = 'At Risk';
      } else {
        status = 'Overspending';
      }

      result[category] = {
        'status': status,
        'score': combinedScore,
        'successRate': successRate,
        'savingsRate': categorySavingsRate,
        'periodCount': totalPeriods,
        'budgetCount': budgetsInCategory.length,
      };
    }

    setState(() => budgetHealthByCategory = result);
  }

  // Phase 3: Generate recommendations
  void _generateRecommendations() {
    List<String> tips = [];

    // Health status per category — computed once here, used both for the
    // general advice below and the specific category callout further down.
    final overspendingCategories = budgetHealthByCategory.entries
        .where((e) => e.value['status'] == 'Overspending' || e.value['status'] == 'At Risk')
        .map((e) => e.key)
        .toList();
    final healthyCategories = budgetHealthByCategory.entries
        .where((e) => e.value['status'] == 'Healthy')
        .map((e) => e.key)
        .toList();

    // General, actionable advice — this is the "what to do." The specific
    // category callout further down is the "where" (which category) — kept
    // separate on purpose so the two tips don't just repeat each other.
    if (overspendingCategories.isNotEmpty) {
      final isPlural = overspendingCategories.length > 1;
      tips.add(
        'Review your at-risk budget ${isPlural ? "categories" : "category"} '
        'to get ${isPlural ? "them" : "it"} back on track.'
      );
    } else if (healthyCategories.isNotEmpty && healthyCategories.length == budgetHealthByCategory.length) {
      tips.add('Keep checking in regularly — that consistency is what\'s keeping your budgets healthy.');
    }

    // Based on best/worst performers
    if (needsAttention != null) {
      tips.add('$needsAttention needs attention - try to reduce spending here.');
    }

    // Categories with a budget but zero recorded activity — flagged
    // directly instead of letting them get silently skipped by the
    // best/worst search above, which only compares categories that
    // already have tracked history (so a flawless, untouched category
    // never had a chance to be named either way).
    //
    // Note: history is never actually null/empty here — the history
    // loader always fills a fixed window of periods (6 months / 4 weeks /
    // 3 years) with $0 entries when there's no real spending. So "unused"
    // means every period in that window shows zero spent, not that the
    // list itself is empty.
    final unusedCategories = allBudgets
        .where((b) {
          final history = budgetHistory[b['id']];
          if (history == null || history.isEmpty) return true;
          return history.every((p) => (p['spent'] as double) == 0);
        })
        .map((b) => b['categoryName'] as String)
        .toSet()
        .toList();

    if (unusedCategories.isNotEmpty) {
      tips.add(
        'Don\'t forget to log any ${unusedCategories.join(" & ")} spending you\'ve made this period.'
      );
    } else if (bestPerformer != null) {
      tips.add('Keep up the good work on $bestPerformer!');
    }

    // Specific category callout
    if (overspendingCategories.isNotEmpty) {
      tips.add('${overspendingCategories.join(" & ")} budgets need attention — review and adjust them.');
    }

    // Based on trends
    int improvingCount = 0;
    for (var comparison in periodComparisons.values) {
      if (comparison['isImprovement']) improvingCount++;
    }
    
    if (improvingCount > periodComparisons.length * 0.5) {
      tips.add('You\'re improving! Keep up the positive trend.');
    }

    setState(() {
      recommendations = tips.take(3).toList(); // Limit to 3 recommendations
    });
  }

  // Budget Tab Content
  @override
  Widget build(BuildContext context) {
    if (isBudgetLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (allBudgets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance_wallet_outlined, 
                   size: 80, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No Budgets Yet',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                'Go to Budget page to create your first budget',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Group budgets by duration type
    final weeklyBudgets = allBudgets.where((b) => b['durationType'] == 'Weekly').toList();
    final monthlyBudgets = allBudgets.where((b) => b['durationType'] == 'Monthly').toList();
    final yearlyBudgets = allBudgets.where((b) => b['durationType'] == 'Yearly').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary Card
        _buildBudgetSummaryCard(),
        
        const SizedBox(height: 16),
        
        // Phase 2: Savings Rate Card
        _buildSavingsRateCard(),
        
        const SizedBox(height: 16),
        
        // Phase 3: Budget Health & Insights Card
        _buildBudgetHealthCard(),
        
        const SizedBox(height: 16),
        
        // Monthly Budgets
        if (monthlyBudgets.isNotEmpty) ...[
          _buildBudgetSection('Monthly Budgets', monthlyBudgets, 'Month'),
          const SizedBox(height: 16),
        ],
        
        // Weekly Budgets
        if (weeklyBudgets.isNotEmpty) ...[
          _buildBudgetSection('Weekly Budgets', weeklyBudgets, 'Week'),
          const SizedBox(height: 16),
        ],
        
        // Yearly Budgets
        if (yearlyBudgets.isNotEmpty) ...[
          _buildBudgetSection('Yearly Budgets', yearlyBudgets, 'Year'),
          const SizedBox(height: 16),
        ],
        
        // Phase 3: Recommendations
        if (recommendations.isNotEmpty)
          _buildRecommendationsCard(),
      ],
    );
  }

  Widget _buildBudgetSummaryCard() {
    int underBudgetCount = 0;
    int nearLimitCount = 0;
    int overBudgetCount = 0;

    for (var budget in allBudgets) {
      final spent = budget['spent'] as double;
      final limit = budget['budgetLimit'] as double;
      final percentage = limit > 0 ? (spent / limit) * 100 : 0;

      if (percentage >= 100) {
        overBudgetCount++;
      } else if (percentage >= 80) {
        nearLimitCount++;
      } else {
        underBudgetCount++;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Budget Overview',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatusChip('✅ Under Budget', underBudgetCount, Colors.green),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatusChip('⚠️ Near Limit', nearLimitCount, Colors.orange),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatusChip('❌ Over Budget', overBudgetCount, Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.split(' ').skip(1).join(' '),
            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetSection(String title, List<Map<String, dynamic>> budgets, String period) {
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
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...budgets.map((budget) {
            final categoryName = budget['categoryName'] as String;
            final spent = budget['spent'] as double;
            final limit = budget['budgetLimit'] as double;
            final percentage = limit > 0 ? (spent / limit) * 100 : 0;
            
            final iconData = getCategoryIconColor(categoryName);

            Color statusColor = Colors.green;
            String statusIcon = '✅';
            if (percentage >= 100) {
              statusColor = Colors.red;
              statusIcon = '❌';
            } else if (percentage >= 80) {
              statusColor = Colors.orange;
              statusIcon = '⚠️';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: iconData['color'].withOpacity(0.2),
                        radius: 20,
                        child: Icon(
                          iconData['icon'],
                          color: iconData['color'],
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              categoryName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'This $period',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        statusIcon,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$_currencySymbol ${spent.toStringAsFixed(2)} / $_currencySymbol ${limit.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${percentage.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 14,
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (percentage / 100).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    ),
                  ),
                  
                  // Period Comparison
                  if (periodComparisons.containsKey(budget['id'])) ...[
                    const SizedBox(height: 12),
                    _buildPeriodComparison(budget['id']),
                  ],

                  // Per-budget performance chart
                  if (budgetHistory.containsKey(budget['id'])) ...[
                    const SizedBox(height: 16),
                    _buildBudgetChart(budget),
                  ],
                ],
              ),
            );
          }).toList(),
          
        ],
      ),
    );
  }

  // Phase 2: Savings Rate Card
  Widget _buildSavingsRateCard() {
    final savingsColor = totalBudgetSavings >= 0 ? Colors.green : Colors.red;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: totalBudgetSavings >= 0 
            ? [Color(0xFF66BB6A), Color(0xFF4CAF50)]
            : [Color(0xFFEF5350), Color(0xFFE53935)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                totalBudgetSavings >= 0 ? Icons.savings : Icons.warning,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 8),
              const Text(
                'Budget Savings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
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
                  Text(
                    'Total Budgeted',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_currencySymbol ${totalBudgeted.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Spent',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_currencySymbol ${totalSpent.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      totalBudgetSavings >= 0 ? 'Amount Saved' : 'Over Budget',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_currencySymbol ${totalBudgetSavings.abs().toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Savings Rate',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${savingsRate.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Per-budget performance chart — amount spent Y-axis, limit dashed line
  Widget _buildBudgetChart(Map<String, dynamic> budget) {
    final history  = budgetHistory[budget['id']]!;
    final limit    = budget['budgetLimit'] as double;
    final catName  = budget['categoryName'] as String;

    if (history.isEmpty) return const SizedBox.shrink();

    final underCount = history.where((p) => p['isUnder']).length;
    final successRate = (underCount / history.length * 100).toStringAsFixed(0);
    final successColor = underCount > history.length / 2 ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Spending Trend',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[800]),
              ),
              Text(
                'Success: $successRate%',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: successColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: _buildLineChart(history, limit),
          ),
        ],
      ),
    );
  }

  // Line chart with amount Y-axis and budget limit reference line
  Widget _buildLineChart(List<Map<String, dynamic>> history, double limit) {
    if (history.isEmpty) return const SizedBox.shrink();

    // Y-axis max: highest of (max spent, limit) + 20% headroom
    final maxSpent = history
        .map((p) => (p['spent'] as double))
        .fold(0.0, (a, b) => a > b ? a : b);
    final yMax = (maxSpent > limit ? maxSpent : limit) * 1.25;
    final yMaxSafe = yMax > 0 ? yMax : 100.0;

    // Smart Y-axis interval
    final rawInterval = yMaxSafe / 4;
    final interval = rawInterval < 10 ? 10.0
        : rawInterval < 50 ? (rawInterval / 10).ceil() * 10.0
        : rawInterval < 500 ? (rawInterval / 50).ceil() * 50.0
        : (rawInterval / 100).ceil() * 100.0;

    // Format Y-axis labels
    String _formatAmount(double v) {
      if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
      return v.toStringAsFixed(0);
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.15), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              interval: interval,
              getTitlesWidget: (value, meta) {
                if (value == meta.max) return const Text('');
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '$_currencySymbol${_formatAmount(value)}',
                    style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                    textAlign: TextAlign.right,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= history.length) return const Text('');
                // Show short label: "Apr", "2026", "W1" etc.
                final label = history[index]['periodLabel'].toString();
                final short = label.split(' ').first;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(short, style: TextStyle(fontSize: 9, color: Colors.grey[600])),
                );
              },
            ),
          ),
          topTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: Colors.grey.withOpacity(0.3)),
            left:   BorderSide(color: Colors.grey.withOpacity(0.3)),
          ),
        ),
        minY: 0,
        maxY: yMaxSafe,
        lineBarsData: [
          // Spent amount line
          LineChartBarData(
            spots: history.asMap().entries.map((e) {
              return FlSpot(e.key.toDouble(), (e.value['spent'] as double));
            }).toList(),
            isCurved: true,
            color: const Color(0xFF4A6B7C),
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                final pct = history[index]['percentage'] as double;
                final dotColor = pct >= 100 ? Colors.red
                    : pct >= 80 ? Colors.orange : Colors.green;
                return FlDotCirclePainter(
                  radius: 4,
                  color: dotColor,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF4A6B7C).withOpacity(0.08),
            ),
          ),
          // Budget limit dashed reference line
          if (limit > 0)
            LineChartBarData(
              spots: List.generate(history.length, (i) => FlSpot(i.toDouble(), limit)),
              isCurved: false,
              color: Colors.red.withOpacity(0.5),
              barWidth: 1.5,
              dashArray: [6, 4],
              dotData: FlDotData(show: false),
            ),
        ],
      ),
    );
  }

  // Phase 3: Budget Health & Insights Card — one row per duration category
  Widget _buildBudgetHealthCard() {
    Color _statusColor(String status) {
      switch (status) {
        case 'Healthy':
          return Colors.green;
        case 'Caution':
          return Colors.orange;
        case 'At Risk':
          return Colors.deepOrange;
        case 'Overspending':
          return Colors.red;
        default:
          return Colors.grey;
      }
    }

    const categories = ['Weekly', 'Monthly', 'Yearly'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Budget Health',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...categories.map((category) {
            final data = budgetHealthByCategory[category];
            if (data == null || data['status'] == 'No Data') {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(width: 80, child: Text(category, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text('No budgets in this category', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  ],
                ),
              );
            }

            final status = data['status'] as String;
            final color = _statusColor(status);
            final successRate = data['successRate'] as double;
            final catSavingsRate = data['savingsRate'] as double;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(category, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                  Expanded(
                    child: Text(
                      '${successRate.toStringAsFixed(0)}% of periods on budget · ${catSavingsRate >= 0 ? "+" : ""}${catSavingsRate.toStringAsFixed(0)}% saved',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      status,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
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

  // Phase 3: Recommendations Card
  Widget _buildRecommendationsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb, color: Colors.blue[700], size: 24),
              const SizedBox(width: 8),
              const Text(
                'Recommendations',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...recommendations.map((tip) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle, color: Colors.blue[700], size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tip,
                      style: const TextStyle(fontSize: 14, height: 1.5),
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

  // Phase 3: Period Comparison Widget
  Widget _buildPeriodComparison(String budgetId) {
    final comparison = periodComparisons[budgetId];
    if (comparison == null) return const SizedBox.shrink();

    final change = comparison['change'] as double;
    final isImprovement = comparison['isImprovement'] as bool;
    final prevLabel = comparison['periodLabel'] as String;

    final changeText = change.abs().toStringAsFixed(1);
    final icon = isImprovement ? Icons.trending_down : Icons.trending_up;
    final color = isImprovement ? Colors.green : Colors.red;
    final label = isImprovement ? 'Improved' : 'Increased';

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            '$label ${changeText}% vs $prevLabel',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}