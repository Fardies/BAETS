import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'budget_helper.dart';
import 'category_helper.dart';
import 'currency_service.dart';

class EditBudgetPage extends StatefulWidget {
  final Map<String, dynamic> budget;

  const EditBudgetPage({super.key, required this.budget});

  @override
  State<EditBudgetPage> createState() => _EditBudgetPageState();
}

class _EditBudgetPageState extends State<EditBudgetPage> {
  bool showNumberPad = false;

  late String  budgetLimit;
  late String  selectedCategoryId;
  late String  selectedCategoryName;

  String _currencySymbol = 'RM';
  String _currencyCode   = 'MYR';
  String _weekStartDay   = 'Monday';

  // All expense categories for the selector
  List<Map<String, dynamic>> expenseCategories = [];
  bool isLoadingCategories = true;

  // Category IDs already used by OTHER budgets of the same duration
  Set<String> takenCategoryIds = {};

  // Transactions this period
  List<Map<String, dynamic>> _transactions     = [];
  bool                        _loadingTransactions = true;

  // Icon/color lookup now comes from category_helper.dart's centralized
  // getCategoryIconColor() instead of this local map.

  @override
  void initState() {
    super.initState();
    budgetLimit          = (widget.budget['budgetLimit'] ?? 0).toDouble().toStringAsFixed(2);
    selectedCategoryId   = widget.budget['categoryID']   ?? '';
    selectedCategoryName = widget.budget['categoryName'] ?? 'Unknown';
    _init();
    _ensureCreatedAt();
  }

  Future<void> _init() async {
    await _loadPrefs();
    await Future.wait([_loadCategories(), _loadTransactions()]);
  }

  Future<void> _loadPrefs() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _currencyCode   = data['currency']    ?? 'MYR';
        _currencySymbol = _getCurrencySymbol(_currencyCode);
        _weekStartDay   = data['weekStartDay'] ?? 'Monday';
        if (mounted) setState(() {});

        // Convert budget limit for display using original values
        final origLimit    = (widget.budget['originalBudgetLimit'] ??
                              widget.budget['budgetLimit'] as num).toDouble();
        final origCurrency = (widget.budget['originalCurrency'] as String?) ?? _currencyCode;
        if (origCurrency != _currencyCode) {
          final converted = await CurrencyService.convert(
            amount: origLimit,
            from:   origCurrency,
            to:     _currencyCode,
          );
          if (mounted) setState(() => budgetLimit = converted.toStringAsFixed(2));
        }
      }
    } catch (e) { print('Error loading prefs: $e'); }
  }

  Future<void> _loadCategories() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      // Fetch all expense categories
      final categories = await fetchExpenseCategories(user.uid);

      // Find which categories already have a budget for this duration
      // (excluding this budget's own category)
      final durationType   = widget.budget['durationType'] ?? 'Monthly';
      final existingBudgets = await fetchBudgets(userId: user.uid, durationType: durationType);
      final taken = existingBudgets
          .where((b) => b['id'] != widget.budget['id'])
          .map<String>((b) => b['categoryID'] as String)
          .toSet();

      if (mounted) setState(() {
        expenseCategories   = categories;
        takenCategoryIds    = taken;
        isLoadingCategories = false;
      });
    } catch (e) {
      print('Error loading categories: $e');
      if (mounted) setState(() => isLoadingCategories = false);
    }
  }

  Future<void> _loadTransactions() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { setState(() => _loadingTransactions = false); return; }

    if (mounted) setState(() => _loadingTransactions = true);
    try {
      final durationType = widget.budget['durationType'] ?? 'Monthly';
      final dateRange    = getDateRangeForDuration(durationType, _weekStartDay);
      final startDate    = dateRange['start']!;
      final endDate      = DateTime(
        dateRange['end']!.year, dateRange['end']!.month, dateRange['end']!.day, 23, 59, 59,
      );

      // No orderBy — avoids needing a composite Firestore index. Sort in Dart.
      final snapshot = await FirebaseFirestore.instance
          .collection('expenses')
          .where('userID',     isEqualTo: user.uid)
          .where('categoryID', isEqualTo: widget.budget['categoryID'])
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('date', isLessThanOrEqualTo:    Timestamp.fromDate(endDate))
          .get();

      final rates = await CurrencyService.getRates();

      final list = snapshot.docs.map((doc) {
        final d = doc.data();
        final originalAmount   = ((d['originalAmount']   ?? d['amount']) as num).toDouble();
        final originalCurrency = (d['originalCurrency'] as String?) ?? _currencyCode;
        final displayAmount    = CurrencyService.convertSync(
            originalAmount, originalCurrency, _currencyCode, rates);
        return {
          'docId':       doc.id,
          'amount':      displayAmount,
          'description': d['description'] ?? '',
          'date':        d['date'],
        };
      }).toList()
        ..sort((a, b) {
          final aD = (a['date'] as Timestamp).toDate();
          final bD = (b['date'] as Timestamp).toDate();
          return bD.compareTo(aD);
        });

      if (mounted) setState(() { _transactions = list; _loadingTransactions = false; });
    } catch (e) {
      print('Error loading transactions: $e');
      if (mounted) setState(() => _loadingTransactions = false);
    }
  }

  Future<void> _ensureCreatedAt() async {
    try {
      final id = widget.budget['id'];
      if (id == null) return;
      final doc = await FirebaseFirestore.instance.collection('budgets').doc(id).get();
      if (doc.exists && doc.data()?['createdAt'] == null) {
        await FirebaseFirestore.instance.collection('budgets').doc(id)
            .update({'createdAt': FieldValue.serverTimestamp()});
      }
    } catch (_) {}
  }

  String _getCurrencySymbol(String code) {
    const s = {
      'MYR':'RM','USD':'\$','EUR':'€','GBP':'£','JPY':'¥',
      'AUD':'A\$','CAD':'C\$','SGD':'S\$','INR':'₹','CHF':'CHF',
      'CNY':'¥','AED':'AED','HKD':'HK\$','KRW':'₩','TRY':'₺','BRL':'R\$',
    };
    return s[code] ?? code;
  }

  Map<String, dynamic> _getIconColor(String name) => getCategoryIconColor(name);

  String _monthName(int m) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[m - 1];
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return '';
    final d = (ts as Timestamp).toDate();
    return '${d.day} ${_monthName(d.month)} ${d.year}';
  }

  // ─────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final durationType = widget.budget['durationType'] ?? 'Monthly';
    final spent        = (widget.budget['spent']       ?? 0).toDouble();
    final limit        = (widget.budget['budgetLimit'] ?? 0).toDouble();

    return Scaffold(
      backgroundColor: const Color(0xFFE8EEF1),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Edit Budget',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton(
              onPressed: _updateBudget,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A6B7C),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Update',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
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
                        // 1. Spending progress card
                        _buildSpendingCard(spent, limit),
                        const SizedBox(height: 24),

                        // 2. Budget limit editor
                        _buildLimitDisplay(),
                        const SizedBox(height: 24),

                        // 3. Category (editable)
                        _buildCategoryField(),
                        const SizedBox(height: 24),

                        // 4. Duration (read-only)
                        _buildDurationDisplay(durationType),
                        const SizedBox(height: 30),

                        // 5. Delete button
                        _buildDeleteButton(),
                        const SizedBox(height: 28),

                        // 6. Transaction list
                        _buildTransactionSection(durationType),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  alignment: Alignment.bottomCenter,
                  child: showNumberPad
                      ? _buildNumberPad()
                      : const SizedBox(width: double.infinity, height: 0),
                ),
              ],
            ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  SPENDING CARD
  // ─────────────────────────────────────────────────────────────

  Widget _buildSpendingCard(double spent, double limit) {
    final isOver    = spent > limit;
    final isNear    = !isOver && limit > 0 && (spent / limit) >= 0.8;
    final remaining = limit - spent;
    final pct       = limit > 0 ? ((spent / limit) * 100).clamp(0.0, 999.0) : 0.0;
    final barColor  = isOver
        ? Colors.red[400]!
        : isNear ? Colors.orange[400]! : const Color(0xFF4A6B7C);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Spending',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black54)),
              if (isOver)
                _badge('Over Budget', Colors.red)
              else if (isNear)
                _badge('Near Limit', Colors.orange),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Spent', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                const SizedBox(height: 2),
                Text('$_currencySymbol ${spent.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold,
                        color: isOver ? Colors.red[600] : Colors.black87)),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Limit', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                const SizedBox(height: 2),
                Text('$_currencySymbol ${limit.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ]),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0,
              minHeight: 10,
              backgroundColor: Colors.grey[100],
              color: barColor,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${pct.toStringAsFixed(0)}% used',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              Text(
                isOver
                    ? '$_currencySymbol ${(-remaining).toStringAsFixed(2)} over'
                    : '$_currencySymbol ${remaining.toStringAsFixed(2)} left',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: isOver ? Colors.red[600] : const Color(0xFF4A6B7C)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
  );

  // ─────────────────────────────────────────────────────────────
  //  BUDGET LIMIT DISPLAY (same card as add_budget)
  // ─────────────────────────────────────────────────────────────

  Widget _buildLimitDisplay() {
    final bool isActive = showNumberPad;
    final bool isEmpty = budgetLimit == '0.00';

    return GestureDetector(
      onTap: () => setState(() { showNumberPad = !showNumberPad; FocusScope.of(context).unfocus(); }),
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0,2))],
        ),
        child: Column(children: [
          Text('Budget Limit',
              style: TextStyle(fontSize: 13, color: isActive ? Colors.blue : Colors.grey[500], fontWeight: FontWeight.w500, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          Text('$_currencySymbol $budgetLimit',
              style: TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: isEmpty ? Colors.grey[400] : const Color(0xFF4A6B7C))),
          const SizedBox(height: 8),
          Container(height: 2, width: 60,
              decoration: BoxDecoration(color: const Color(0xFF4A6B7C).withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 6),
          Text(showNumberPad ? 'Tap to close' : 'Tap to enter amount',
              style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  CATEGORY FIELD (editable)
  // ─────────────────────────────────────────────────────────────

  Widget _buildCategoryField() {
    final iconColor = _getIconColor(selectedCategoryName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Category',
            style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
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
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0,2))],
            ),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                    color: (iconColor['color'] as Color).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(iconColor['icon'], color: iconColor['color'], size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(selectedCategoryName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.keyboard_arrow_down, color: Colors.grey[600], size: 20),
              ),
            ]),
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
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              const Text('SELECT CATEGORY',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(width: 48),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, childAspectRatio: 0.85,
                crossAxisSpacing: 16, mainAxisSpacing: 16,
              ),
              itemCount: expenseCategories.length,
              itemBuilder: (context, index) {
                final category  = expenseCategories[index];
                final iconColor = _getIconColor(category['name']);
                final isSelected = selectedCategoryId == category['id'];
                final isTaken   = takenCategoryIds.contains(category['id']);

                return GestureDetector(
                  onTap: () {
                    if (isTaken) {
                      // Already has a budget for this duration
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              '${category['name']} already has a ${widget.budget['durationType']} budget.'),
                          backgroundColor: Colors.orange[700],
                        ),
                      );
                      return;
                    }
                    setState(() {
                      selectedCategoryId   = category['id'];
                      selectedCategoryName = category['name'];
                    });
                    Navigator.pop(context);
                  },
                  child: Opacity(
                    opacity: isTaken ? 0.35 : 1.0,
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
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(iconColor['icon'], size: 40, color: iconColor['color']),
                        const SizedBox(height: 8),
                        Text(category['name'],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        if (isTaken) ...[
                          const SizedBox(height: 2),
                          Text('In use', style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                        ],
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  DURATION (read-only)
  // ─────────────────────────────────────────────────────────────

  Widget _buildDurationDisplay(String durationType) {
    const durations = ['Weekly', 'Monthly', 'Yearly'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Duration',
            style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0,2))],
          ),
          child: Row(
            children: durations.map((d) {
              final isSelected = d == durationType;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.all(4),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF4A6B7C) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(d,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : Colors.grey[400])),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  DELETE BUTTON
  // ─────────────────────────────────────────────────────────────

  Widget _buildDeleteButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _confirmDelete,
        icon: const Icon(Icons.delete_outline, size: 18),
        label: const Text('Delete Budget',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  TRANSACTION LIST (view only)
  // ─────────────────────────────────────────────────────────────

  Widget _buildTransactionSection(String durationType) {
    final label = durationType == 'Yearly' ? 'Year' : durationType == 'Weekly' ? 'Week' : 'Month';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('This $label\'s Transactions',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
          if (!_loadingTransactions)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: const Color(0xFF4A6B7C).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Text('${_transactions.length}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF4A6B7C))),
            ),
        ]),
        const SizedBox(height: 12),
        if (_loadingTransactions)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
        else if (_transactions.isEmpty)
          _buildEmptyTransactions()
        else
          ...(_transactions.map((tx) => _buildTransactionTile(tx))),
      ],
    );
  }

  Widget _buildEmptyTransactions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Icon(Icons.receipt_long_outlined, size: 52, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text('No $selectedCategoryName transactions\nthis period',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[400], height: 1.5)),
      ]),
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> tx) {
    final amount      = (tx['amount'] ?? 0).toDouble();
    final description = (tx['description'] as String? ?? '').trim();
    final dateStr     = _formatDate(tx['date']);
    final iconData    = _getIconColor(selectedCategoryName);
    final color       = iconData['color'] as Color;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0,2))],
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(iconData['icon'], color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              description.isEmpty ? selectedCategoryName : description,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(dateStr, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ]),
        ),
        Text('-$_currencySymbol ${amount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red)),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  NUMBER PAD (same as add_budget_page)
  // ─────────────────────────────────────────────────────────────

  Widget _buildNumberPad() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20), topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, -4)),
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
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
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
                          _buildKey(row, col),
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

  Widget _buildKey(int row, int col) {
    const layout = [
      ['1','2','3'], ['4','5','6'], ['7','8','9'], ['00','0','⌫'],
    ];
    final key = layout[row][col];
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          // Cents shift in from the right — same as add_transaction_page.dart.
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
        }),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F6F7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(key, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: Colors.black87)),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  ACTIONS
  // ─────────────────────────────────────────────────────────────

  Future<void> _updateBudget() async {
    setState(() => showNumberPad = false);
    final double limitValue = double.tryParse(budgetLimit) ?? 0.0;
    if (limitValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid budget limit')));
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('budgets')
          .doc(widget.budget['id'])
          .update({
        'budgetLimit':         limitValue,
        'originalBudgetLimit': limitValue,
        'originalCurrency':    _currencyCode,
        'categoryID':          selectedCategoryId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Budget updated!'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to update budget')));
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Budget'),
        content: Text(
            'Delete the budget for $selectedCategoryName?\n\nThis cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final success = await deleteBudget(widget.budget['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success ? 'Budget deleted' : 'Failed to delete budget'),
          backgroundColor: success ? Colors.green : null,
        ));
        if (success) Navigator.pop(context);
      }
    }
  }
}