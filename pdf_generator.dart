import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'budget_helper.dart';
import 'category_helper.dart';
import 'currency_service.dart';

class ReportPDFGenerator {
  static Future<void> generateAndDownloadPDF({
    required DateTime startDate,
    required DateTime endDate,
    required bool isExpense,
    required bool isAnalysis,
    required String selectedPreset,
    required String currencySymbol,
    required String currencyCode,
    required String weekStartDay,
    required double totalIncome,
    required double totalExpense,
    required double balance,
    required List<Map<String, dynamic>> categoryBreakdown,
    required List<Map<String, dynamic>> budgetPerformance,
  }) async {
    final pdf = pw.Document();

    // Get username
    String username = 'User';
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists && doc.data() != null) {
          username = doc.data()!['username'] ?? 'User';
        }
      }
    } catch (e) {
      print('Error fetching username: $e');
    }

    String dateRangeText = _formatDateRange(startDate, endDate, selectedPreset);

    // For Analysis tab: fetch full budget data fresh from Firestore
    Map<String, dynamic> analysisData = {};
    if (isAnalysis) {
      analysisData = await _fetchAnalysisData(weekStartDay, currencyCode);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          if (isAnalysis) {
            return _buildAnalysisPages(
              username, dateRangeText, currencySymbol, analysisData,
              totalIncome, totalExpense, balance,
            );
          }

          return [
            _buildHeader(username, dateRangeText, isExpense),
            pw.SizedBox(height: 20),
            _buildTransactionSummary(currencySymbol, totalIncome, totalExpense, balance),
            pw.SizedBox(height: 20),
            if (isExpense && budgetPerformance.isNotEmpty) ...[
              _buildBudgetPerformance(currencySymbol, budgetPerformance),
              pw.SizedBox(height: 20),
            ],
            _buildBreakdownTable(isExpense, currencySymbol, categoryBreakdown),
            pw.SizedBox(height: 20),
            _buildInsights(isExpense, currencySymbol, balance, categoryBreakdown, budgetPerformance),
            pw.SizedBox(height: 30),
            _buildFooter(),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  ANALYSIS DATA FETCHER
  // ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _fetchAnalysisData(
    String weekStartDay,
    String currencyCode,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};

    try {
      // Fetch rates once — needed so a budget set in one currency and
      // expenses logged in another don't get compared as raw numbers
      // (this mirrors the same fix applied to the live app).
      final rates = await CurrencyService.getRates();

      final fetchedBudgets = await fetchBudgets(userId: user.uid);

      List<Map<String, dynamic>> budgetsWithDetails = await Future.wait(
        fetchedBudgets.map((budget) async {
          final categoryName = await getCategoryNameById(budget['categoryID']);
          final durationType = budget['durationType'] ?? 'Monthly';

          // Convert the limit from its ORIGINAL currency to the report's
          // display currency — same approach as the in-app report tab —
          // instead of trusting the raw 'budgetLimit' field as-is.
          final origLimit = (budget['originalBudgetLimit'] ?? budget['budgetLimit'] as num).toDouble();
          final origCurrency = (budget['originalCurrency'] as String?) ?? currencyCode;
          final limit = CurrencyService.convertSync(origLimit, origCurrency, currencyCode, rates);

          // Current period
          final dateRange   = getDateRangeForDuration(durationType, weekStartDay);
          final periodStart = dateRange['start']!;
          final periodEnd   = dateRange['end']!;

          final spent = await calculateSpentForCategory(
            userId: user.uid,
            categoryId: budget['categoryID'],
            startDate: periodStart,
            endDate: periodEnd,
            targetCurrency: currencyCode,
            rates: rates,
          );

          // Previous period comparison
          final prevRange = _getPeriodRangeForIndex(durationType, 1, weekStartDay);
          final prevSpent = await calculateSpentForCategory(
            userId: user.uid,
            categoryId: budget['categoryID'],
            startDate: prevRange['start']!,
            endDate: prevRange['end']!,
            targetCurrency: currencyCode,
            rates: rates,
          );

          final percentage     = limit > 0 ? (spent / limit) * 100 : 0.0;
          final prevPercentage = limit > 0 ? (prevSpent / limit) * 100 : 0.0;
          final change         = percentage - prevPercentage;

          return {
            'id':              budget['id'],
            'categoryID':      budget['categoryID'],
            'categoryName':    categoryName,
            'budgetLimit':     limit,
            'durationType':    durationType,
            'createdAt':       budget['createdAt'],
            'spent':           spent.toDouble(),
            'percentage':      percentage,
            'isOverBudget':    spent > limit,
            'isNearLimit':     percentage >= 80 && percentage < 100,
            'prevSpent':       prevSpent.toDouble(),
            'prevPercentage':  prevPercentage,
            'change':          change,
            'isImprovement':   change < 0,
            'prevPeriodLabel': prevRange['label'] as String,
          };
        }).toList(),
      );

      // Totals & overview counts
      double totalBudgeted = 0;
      double totalSpent    = 0;
      int underCount = 0, nearCount = 0, overCount = 0;

      for (var b in budgetsWithDetails) {
        totalBudgeted += b['budgetLimit'] as double;
        totalSpent    += b['spent'] as double;
        final pct = b['percentage'] as double;
        if (pct >= 100) overCount++;
        else if (pct >= 80) nearCount++;
        else underCount++;
      }

      final savings     = totalBudgeted - totalSpent;
      final savingsRate = totalBudgeted > 0 ? (savings / totalBudgeted) * 100 : 0.0;

      // ── Per-budget history (6 months / 4 weeks / 3 years window) ──
      // Mirrors BudgetReportTab._loadHistoricalDataForBudgets() — used
      // for both the per-duration health status and the best/worst
      // performer scoring below, instead of one blended grade.
      Map<String, List<Map<String, dynamic>>> budgetHistory = {};
      for (var budget in budgetsWithDetails) {
        final durationType = budget['durationType'] as String;
        final limit = budget['budgetLimit'] as double;
        final periodsToAnalyze = durationType == 'Monthly' ? 6 : durationType == 'Weekly' ? 4 : 3;

        List<Map<String, dynamic>> periods = [];
        for (int i = 0; i < periodsToAnalyze; i++) {
          final range = _getPeriodRangeForIndex(durationType, i, weekStartDay);
          final histSpent = await calculateSpentForCategory(
            userId: user.uid,
            categoryId: budget['categoryID'],
            startDate: range['start']!,
            endDate: range['end']!,
            targetCurrency: currencyCode,
            rates: rates,
          );
          final histPercentage = limit > 0 ? (histSpent / limit) * 100 : 0.0;
          periods.add({
            'spent': histSpent.toDouble(),
            'percentage': histPercentage,
            'isUnder': histPercentage < 100,
          });
        }
        budgetHistory[budget['id']] = periods;
      }

      // ── Per-duration health status ──────────────────────────────
      // Mirrors BudgetReportTab._calculateHealthByCategory() exactly —
      // Weekly/Monthly/Yearly are scored separately instead of blended
      // into one grade, since mixing them hides real problems.
      const durations = ['Weekly', 'Monthly', 'Yearly'];
      Map<String, Map<String, dynamic>> healthByCategory = {};

      for (final duration in durations) {
        final budgetsInDuration =
            budgetsWithDetails.where((b) => b['durationType'] == duration).toList();

        if (budgetsInDuration.isEmpty) {
          healthByCategory[duration] = {'status': 'No Data'};
          continue;
        }

        int totalPeriods = 0;
        int successfulPeriods = 0;
        double durationBudgeted = 0.0;
        double durationSpent = 0.0;

        for (final budget in budgetsInDuration) {
          durationBudgeted += budget['budgetLimit'] as double;
          durationSpent += budget['spent'] as double;

          final history = budgetHistory[budget['id']];
          if (history != null && history.isNotEmpty) {
            totalPeriods += history.length;
            successfulPeriods += history.where((p) => p['isUnder']).length;
          }
        }

        final successRate = totalPeriods > 0 ? (successfulPeriods / totalPeriods) * 100 : 0.0;
        final durationSavingsRate = durationBudgeted > 0
            ? ((durationBudgeted - durationSpent) / durationBudgeted) * 100
            : 0.0;
        final savingsScore = durationSavingsRate.clamp(-50, 50);
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

        healthByCategory[duration] = {
          'status': status,
          'successRate': successRate,
          'savingsRate': durationSavingsRate,
        };
      }

      // ── Best/worst performer (with duration, to disambiguate the same
      // category name appearing across Weekly/Monthly/Yearly, and including
      // ALL categories tied at the top/bottom score — not just the first
      // one encountered) ──────────────────────────────────────────────
      // Mirrors BudgetReportTab._generateSmartInsights() exactly.
      const minPeriodsForInsight = 3;
      List<Map<String, dynamic>> scored = [];

      for (var budget in budgetsWithDetails) {
        final history = budgetHistory[budget['id']];
        if (history == null || history.length < minPeriodsForInsight) continue;

        final underBudgetCount = history.where((p) => p['isUnder']).length;
        final avgPercentage =
            history.map((p) => p['percentage'] as double).reduce((a, b) => a + b) / history.length;
        final successRate = (underBudgetCount / history.length) * 100;
        final score = successRate - (avgPercentage * 0.3);

        scored.add({
          'label': '${budget['categoryName']} (${budget['durationType']})',
          'score': score,
          'underBudgetCount': underBudgetCount,
          'periodCount': history.length,
          'avgPercentage': avgPercentage,
        });
      }

      String? bestPerformer;
      if (scored.isNotEmpty) {
        final maxScore = scored.map((s) => s['score'] as double).reduce((a, b) => a > b ? a : b);
        bestPerformer = scored
            .where((s) => (s['score'] as double) >= maxScore - 0.0001)
            .map((s) => s['label'] as String)
            .join(' & ');
      }

      final struggling = scored
          .where((s) => (s['underBudgetCount'] as int) < (s['periodCount'] as int) * 0.5)
          .toList();
      String? needsAttention;
      if (struggling.isNotEmpty) {
        final maxAvg = struggling.map((s) => s['avgPercentage'] as double).reduce((a, b) => a > b ? a : b);
        needsAttention = struggling
            .where((s) => (s['avgPercentage'] as double) >= maxAvg - 0.0001)
            .map((s) => s['label'] as String)
            .join(' & ');
      }

      // ── Categories with a budget but zero recorded activity ───────
      final unusedCategories = budgetsWithDetails
          .where((b) {
            final history = budgetHistory[b['id']];
            if (history == null || history.isEmpty) return true;
            return history.every((p) => (p['spent'] as double) == 0);
          })
          .map((b) => b['categoryName'] as String)
          .toSet()
          .toList();

      // ── Recommendations — mirrors BudgetReportTab._generateRecommendations() ──
      final overspendingCategories = healthByCategory.entries
          .where((e) => e.value['status'] == 'Overspending' || e.value['status'] == 'At Risk')
          .map((e) => e.key)
          .toList();
      final healthyCategories = healthByCategory.entries
          .where((e) => e.value['status'] == 'Healthy')
          .map((e) => e.key)
          .toList();

      List<String> recommendations = [];

      if (overspendingCategories.isNotEmpty) {
        final isPlural = overspendingCategories.length > 1;
        recommendations.add(
          'Review your at-risk budget ${isPlural ? "categories" : "category"} '
          'to get ${isPlural ? "them" : "it"} back on track.'
        );
      } else if (healthyCategories.isNotEmpty && healthyCategories.length == healthByCategory.length) {
        recommendations.add('Keep checking in regularly — that consistency is what\'s keeping your budgets healthy.');
      }

      if (needsAttention != null) {
        recommendations.add('$needsAttention needs attention - try to reduce spending here.');
      }

      if (unusedCategories.isNotEmpty) {
        recommendations.add(
          'Don\'t forget to log any ${unusedCategories.join(" & ")} spending you\'ve made this period.'
        );
      } else if (bestPerformer != null) {
        recommendations.add('Keep up the good work on $bestPerformer!');
      }

      if (overspendingCategories.isNotEmpty) {
        recommendations.add('${overspendingCategories.join(" & ")} budgets need attention — review and adjust them.');
      }

      return {
        'budgets':         budgetsWithDetails,
        'totalBudgeted':   totalBudgeted,
        'totalSpent':      totalSpent,
        'savings':         savings,
        'savingsRate':     savingsRate,
        'underCount':      underCount,
        'nearCount':       nearCount,
        'overCount':       overCount,
        'healthByCategory': healthByCategory,
        'recommendations': recommendations.take(3).toList(),
      };
    } catch (e) {
      print('Error fetching analysis data for PDF: $e');
      return {};
    }
  }

  /// Returns the date range for a period `index` periods ago (0 = current).
  /// Mirrors BudgetReportTab._getPeriodRange().
  static Map<String, dynamic> _getPeriodRangeForIndex(
    String durationType, int periodsAgo, String weekStartDay,
  ) {
    final now = DateTime.now();
    if (durationType == 'Monthly') {
      final target = DateTime(now.year, now.month - periodsAgo, 1);
      return {
        'start': DateTime(target.year, target.month, 1),
        'end':   DateTime(target.year, target.month + 1, 0, 23, 59, 59),
        'label': '${_shortMonth(target.month)} ${target.year}',
      };
    } else if (durationType == 'Weekly') {
      final cur = getDateRangeForDuration('Weekly', weekStartDay);
      final offset = Duration(days: periodsAgo * 7);
      return {
        'start': cur['start']!.subtract(offset),
        'end':   cur['end']!.subtract(offset),
        'label': periodsAgo == 0 ? 'This Week' : '$periodsAgo week(s) ago',
      };
    } else {
      final year = now.year - periodsAgo;
      return {
        'start': DateTime(year, 1, 1),
        'end':   DateTime(year, 12, 31, 23, 59, 59),
        'label': year.toString(),
      };
    }
  }

  static String _shortMonth(int month) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return m[month - 1];
  }

  // ─────────────────────────────────────────────────────────────
  //  ANALYSIS PDF PAGE BUILDER
  // ─────────────────────────────────────────────────────────────

  static List<pw.Widget> _buildAnalysisPages(
    String username,
    String dateRange,
    String currencySymbol,
    Map<String, dynamic> data,
    double totalIncome,
    double totalExpense,
    double balance,
  ) {
    if (data.isEmpty) {
      return [
        _buildAnalysisHeader(username, dateRange),
        pw.SizedBox(height: 20),
        pw.Text('No budget data available.',
            style: const pw.TextStyle(color: PdfColors.grey600)),
        pw.SizedBox(height: 30),
        _buildFooter(),
      ];
    }

    final budgets          = data['budgets'] as List<Map<String, dynamic>>;
    final totalBudgeted    = data['totalBudgeted'] as double;
    final totalSpent       = data['totalSpent'] as double;
    final savings          = data['savings'] as double;
    final savingsRate      = data['savingsRate'] as double;
    final underCount       = data['underCount'] as int;
    final nearCount        = data['nearCount'] as int;
    final overCount        = data['overCount'] as int;
    final healthByCategory = data['healthByCategory'] as Map<String, Map<String, dynamic>>;
    final recommendations  = (data['recommendations'] as List).cast<String>();

    final weeklyBudgets  = budgets.where((b) => b['durationType'] == 'Weekly').toList();
    final monthlyBudgets = budgets.where((b) => b['durationType'] == 'Monthly').toList();
    final yearlyBudgets  = budgets.where((b) => b['durationType'] == 'Yearly').toList();

    return [
      // 1. Header
      _buildAnalysisHeader(username, dateRange),
      pw.SizedBox(height: 20),

      // 2. Transaction Summary (income / expense / balance)
      _buildTransactionSummary(currencySymbol, totalIncome, totalExpense, balance),
      pw.SizedBox(height: 20),

      // 3. Budget Overview (status chips) + Savings Summary
      _buildAnalysisOverview(
        underCount, nearCount, overCount,
        currencySymbol, totalBudgeted, totalSpent, savings, savingsRate,
      ),
      pw.SizedBox(height: 20),

      // 4. Budget Health — per duration (Weekly/Monthly/Yearly), matching
      // the in-app report instead of one blended letter grade.
      _buildBudgetHealthSection(healthByCategory),
      pw.SizedBox(height: 20),

      // 5. Per-duration budget detail tables
      if (monthlyBudgets.isNotEmpty) ...[
        _buildBudgetDetailSection('Monthly Budgets', monthlyBudgets, currencySymbol),
        pw.SizedBox(height: 20),
      ],
      if (weeklyBudgets.isNotEmpty) ...[
        _buildBudgetDetailSection('Weekly Budgets', weeklyBudgets, currencySymbol),
        pw.SizedBox(height: 20),
      ],
      if (yearlyBudgets.isNotEmpty) ...[
        _buildBudgetDetailSection('Yearly Budgets', yearlyBudgets, currencySymbol),
        pw.SizedBox(height: 20),
      ],

      // 6. Recommendations
      if (recommendations.isNotEmpty) ...[
        _buildRecommendationsSection(recommendations),
        pw.SizedBox(height: 20),
      ],

      pw.SizedBox(height: 10),
      _buildFooter(),
    ];
  }

  static pw.Widget _buildAnalysisHeader(String username, String dateRange) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Budget Analysis Report',
          style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated for: $username',
                style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
            pw.Text('Period: $dateRange',
                style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Generated on: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey500),
        ),
        pw.Divider(thickness: 2),
      ],
    );
  }

  static pw.Widget _buildAnalysisOverview(
    int underCount, int nearCount, int overCount,
    String currencySymbol,
    double totalBudgeted, double totalSpent, double savings, double savingsRate,
  ) {
    final savingsColor = savings >= 0 ? PdfColors.green700 : PdfColors.red700;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Status chips
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Budget Overview',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _statusChip('Under Budget', underCount, PdfColors.green),
                  _statusChip('Near Limit',   nearCount,  PdfColors.orange),
                  _statusChip('Over Budget',  overCount,  PdfColors.red),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),

        // Savings summary
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: savings >= 0 ? PdfColors.green50 : PdfColors.red50,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(
                color: savings >= 0 ? PdfColors.green200 : PdfColors.red200),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Budget Savings Summary',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _summaryItem('Total Budgeted', currencySymbol, totalBudgeted, PdfColors.grey800),
                  _summaryItem('Total Spent',    currencySymbol, totalSpent,    PdfColors.grey800),
                  _summaryItem(
                    savings >= 0 ? 'Amount Saved' : 'Over Budget',
                    currencySymbol, savings.abs(), savingsColor,
                  ),
                  pw.Column(
                    children: [
                      pw.Text('Savings Rate',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        '${savingsRate.toStringAsFixed(1)}%',
                        style: pw.TextStyle(
                            fontSize: 14, fontWeight: pw.FontWeight.bold, color: savingsColor),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _statusChip(String label, int count, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: color),
      ),
      child: pw.Column(
        children: [
          pw.Text(count.toString(),
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: color)),
          pw.SizedBox(height: 4),
          pw.Text(label, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        ],
      ),
    );
  }

  // Mirrors the in-app _buildBudgetHealthCard() — one status row per
  // duration (Weekly/Monthly/Yearly) instead of one blended letter grade,
  // since mixing different period lengths together hides real problems.
  static pw.Widget _buildBudgetHealthSection(Map<String, Map<String, dynamic>> healthByCategory) {
    PdfColor statusColor(String status) {
      switch (status) {
        case 'Healthy': return PdfColors.green700;
        case 'Caution': return PdfColors.orange;
        case 'At Risk': return PdfColors.deepOrange;
        case 'Overspending': return PdfColors.red;
        default: return PdfColors.grey400;
      }
    }

    const durations = ['Weekly', 'Monthly', 'Yearly'];

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Budget Health',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(
            'Calculated separately per duration, since mixing weekly, monthly\nand yearly budgets together would distort the result.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 12),
          ...durations.map((duration) {
            final entry = healthByCategory[duration];
            final status = (entry?['status'] as String?) ?? 'No Data';

            if (status == 'No Data') {
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Row(
                  children: [
                    pw.SizedBox(width: 70, child: pw.Text(duration,
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))),
                    pw.Text('No budgets in this category',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey500)),
                  ],
                ),
              );
            }

            final color = statusColor(status);
            final successRate = entry!['successRate'] as double;
            final durSavingsRate = entry['savingsRate'] as double;

            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: color, width: 1),
              ),
              child: pw.Row(
                children: [
                  pw.SizedBox(width: 70, child: pw.Text(duration,
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(
                    child: pw.Text(
                      '${successRate.toStringAsFixed(0)}% of periods on budget'
                      ' \u00b7 ${durSavingsRate >= 0 ? "+" : ""}${durSavingsRate.toStringAsFixed(0)}% saved',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: color,
                      borderRadius: pw.BorderRadius.circular(10),
                    ),
                    child: pw.Text(status,
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  static pw.Widget _buildBudgetDetailSection(
    String title,
    List<Map<String, dynamic>> budgets,
    String currencySymbol,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(3),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _tableCell('Category',       isHeader: true),
                  _tableCell('Spent',          isHeader: true),
                  _tableCell('Budget',         isHeader: true),
                  _tableCell('Usage',          isHeader: true),
                  _tableCell('vs Last Period', isHeader: true),
                ],
              ),
              ...budgets.map((budget) {
                final percentage = budget['percentage'] as double;
                final isOver     = budget['isOverBudget'] as bool;
                final isNear     = budget['isNearLimit'] as bool;
                final change     = budget['change'] as double;
                final isImprove  = budget['isImprovement'] as bool;
                final prevLabel  = budget['prevPeriodLabel'] as String;

                final statusColor = isOver ? PdfColors.red
                    : isNear ? PdfColors.orange : PdfColors.green700;
                final statusText  = isOver ? 'OVER' : isNear ? 'NEAR' : 'OK';

                String compText;
                PdfColor compColor;
                if (change.abs() < 0.5) {
                  compText  = 'No change vs $prevLabel';
                  compColor = PdfColors.grey600;
                } else if (isImprove) {
                  compText  = 'down ${change.abs().toStringAsFixed(1)}% vs $prevLabel';
                  compColor = PdfColors.green700;
                } else {
                  compText  = 'up ${change.abs().toStringAsFixed(1)}% vs $prevLabel';
                  compColor = PdfColors.red;
                }

                return pw.TableRow(
                  children: [
                    _tableCell(budget['categoryName'] as String),
                    _tableCell('$currencySymbol ${(budget['spent'] as double).toStringAsFixed(2)}'),
                    _tableCell('$currencySymbol ${(budget['budgetLimit'] as double).toStringAsFixed(2)}'),
                    _tableCell('$statusText  ${percentage.toStringAsFixed(0)}%', color: statusColor),
                    _tableCell(compText, color: compColor),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildRecommendationsSection(List<String> recommendations) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Recommendations',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          ...recommendations.map((tip) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('  -  ', style: pw.TextStyle(fontSize: 12, color: PdfColors.blue700)),
                pw.Expanded(
                  child: pw.Text(tip, style: const pw.TextStyle(fontSize: 12)),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  SHARED / EXPENSE / INCOME HELPERS
  // ─────────────────────────────────────────────────────────────

  static String _formatDateRange(DateTime start, DateTime end, String preset) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    switch (preset) {
      case 'Day':        return '${start.day} ${months[start.month - 1]} ${start.year}';
      case 'Week':       return '${start.day} ${months[start.month - 1]} - ${end.day} ${months[end.month - 1]} ${end.year}';
      case 'Month':      return '${months[start.month - 1]} ${start.year}';
      case 'Year':       return '${start.year}';
      case 'Date Range': return '${start.day} ${months[start.month - 1]} - ${end.day} ${months[end.month - 1]} ${end.year}';
      default:           return '${months[start.month - 1]} ${start.year}';
    }
  }

  static pw.Widget _buildHeader(String username, String dateRange, bool isExpense) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '${isExpense ? "Expense" : "Income"} Report',
          style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated for: $username',
                style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
            pw.Text('Period: $dateRange',
                style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Generated on: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey500),
        ),
        pw.Divider(thickness: 2),
      ],
    );
  }

  static pw.Widget _buildTransactionSummary(
    String currencySymbol, double totalIncome, double totalExpense, double balance,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Transaction Summary',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _summaryItem('Income',  currencySymbol, totalIncome,  PdfColors.green),
              _summaryItem('Expense', currencySymbol, totalExpense, PdfColors.red),
              _summaryItem('Balance', currencySymbol, balance,
                  balance >= 0 ? PdfColors.green : PdfColors.red),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryItem(
    String label, String currencySymbol, double value, PdfColor color,
  ) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.SizedBox(height: 4),
        pw.Text(
          '$currencySymbol ${value.toStringAsFixed(2)}',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: color),
        ),
      ],
    );
  }

  static pw.Widget _buildBudgetPerformance(
    String currencySymbol, List<Map<String, dynamic>> budgetPerformance,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Budget Performance',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _tableCell('Category', isHeader: true),
                  _tableCell('Spent',    isHeader: true),
                  _tableCell('Budget',   isHeader: true),
                  _tableCell('Status',   isHeader: true),
                ],
              ),
              ...budgetPerformance.map((budget) {
                final percentage = budget['percentage'] as double;
                final isOver     = budget['isOverBudget'] as bool;
                final status     = isOver
                    ? '${percentage.toStringAsFixed(0)}% OVER'
                    : '${percentage.toStringAsFixed(0)}% OK';
                return pw.TableRow(
                  children: [
                    _tableCell(budget['categoryName']),
                    _tableCell('$currencySymbol ${budget['spent'].toStringAsFixed(2)}'),
                    _tableCell('$currencySymbol ${budget['budgetLimit'].toStringAsFixed(2)}'),
                    _tableCell(status, color: isOver ? PdfColors.red : PdfColors.green),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildBreakdownTable(
    bool isExpense, String currencySymbol, List<Map<String, dynamic>> breakdown,
  ) {
    if (breakdown.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(16),
        child: pw.Text(
          'No ${isExpense ? "expenses" : "income"} data for this period',
          style: const pw.TextStyle(color: PdfColors.grey600),
        ),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            isExpense ? 'Expenses by Category' : 'Income by Source',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _tableCell(isExpense ? 'Category' : 'Source', isHeader: true),
                  _tableCell('Transactions', isHeader: true),
                  _tableCell('Amount',       isHeader: true),
                  _tableCell('Percentage',   isHeader: true),
                ],
              ),
              ...breakdown.map((item) {
                final name       = isExpense ? item['categoryName'] : item['sourceName'];
                final amount     = item['amount'];
                final count      = item['transactionCount'];
                final percentage = item['percentage'];
                return pw.TableRow(
                  children: [
                    _tableCell(name),
                    _tableCell(count.toString()),
                    _tableCell('$currencySymbol ${amount.toStringAsFixed(2)}'),
                    _tableCell('${percentage.toStringAsFixed(1)}%'),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildInsights(
    bool isExpense, String currencySymbol, double balance,
    List<Map<String, dynamic>> breakdown, List<Map<String, dynamic>> budgetPerformance,
  ) {
    List<String> insights = [];

    // Tab-aware transaction count — matches the in-app report tab's fix.
    // The old version here compared overall income vs expense balance,
    // which doesn't make sense as an "insight" while looking at just the
    // Expense or just the Income tab specifically.
    if (breakdown.isNotEmpty) {
      final totalTransactions = breakdown.fold<int>(
          0, (sum, item) => sum + ((item['transactionCount'] as int?) ?? 0));
      insights.add(
        'You made $totalTransactions ${isExpense ? "expense" : "income"} '
        'transaction${totalTransactions == 1 ? "" : "s"} this period'
      );
    }

    if (breakdown.isNotEmpty) {
      final top  = breakdown.first;
      final name = isExpense ? top['categoryName'] : top['sourceName'];
      insights.add(isExpense
          ? '$name is your top expense category'
          : '$name is your main income source');
    }

    if (isExpense && budgetPerformance.isNotEmpty) {
      final overCount  = budgetPerformance.where((b) => b['isOverBudget']).length;
      final underCount = budgetPerformance.length - overCount;
      if (underCount == budgetPerformance.length) {
        insights.add('You are under budget on all categories!');
      } else if (overCount > 0) {
        insights.add('You are over budget on $overCount ${overCount == 1 ? "category" : "categories"}');
      }
    }

    if (insights.isEmpty) insights.add('Start tracking transactions to see insights!');

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Key Insights',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          ...insights.map((insight) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(insight, style: const pw.TextStyle(fontSize: 12)),
          )),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter() {
    return pw.Column(
      children: [
        pw.Divider(thickness: 1),
        pw.Text('Generated by Budget Tracker App',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey500)),
        pw.Text('This report is for personal reference only',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey400)),
      ],
    );
  }

  static pw.Widget _tableCell(String text, {bool isHeader = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 11 : 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? PdfColors.black,
        ),
      ),
    );
  }
}