import 'package:cloud_firestore/cloud_firestore.dart';
import 'currency_service.dart';

/// Helper functions for managing budgets

/// Creates a new budget for a user
Future<String?> createBudget({
  required String userId,
  required String categoryId,
  required double budgetLimit,
  required String durationType,
  double? originalBudgetLimit,
  String? originalCurrency,
}) async {
  try {
    final docRef = await FirebaseFirestore.instance.collection('budgets').add({
      'userID':              userId,
      'categoryID':          categoryId,
      'budgetLimit':         budgetLimit,
      'durationType':        durationType,
      'originalBudgetLimit': originalBudgetLimit ?? budgetLimit,
      'originalCurrency':    originalCurrency ?? 'MYR',
      'createdAt':           FieldValue.serverTimestamp(),
    });
    return docRef.id;
  } catch (e) {
    print('Error creating budget: $e');
    return null;
  }
}

/// Fetches budgets for a user, optionally filtered by duration type
Future<List<Map<String, dynamic>>> fetchBudgets({
  required String userId,
  String? durationType, // If null, fetch all
}) async {
  try {
    Query query = FirebaseFirestore.instance
        .collection('budgets')
        .where('userID', isEqualTo: userId);

    // Add duration filter if specified
    if (durationType != null) {
      query = query.where('durationType', isEqualTo: durationType);
    }

    final snapshot = await query.get();

    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return {
        'id':                  doc.id,
        'userID':              data['userID'],
        'categoryID':          data['categoryID'],
        'budgetLimit':         (data['budgetLimit'] ?? 0).toDouble(),
        'originalBudgetLimit': (data['originalBudgetLimit'] ?? data['budgetLimit'] ?? 0).toDouble(),
        'originalCurrency':    (data['originalCurrency'] as String?) ?? 'MYR',
        'durationType':        data['durationType'] ?? 'Monthly',
        'createdAt':           data['createdAt'],
      };
    }).toList();
  } catch (e) {
    print('Error fetching budgets: $e');
    return [];
  }
}

/// Calculates total spent for a specific category in a date range.
/// Pass [targetCurrency] + [rates] to get amounts converted on the fly.
Future<double> calculateSpentForCategory({
  required String userId,
  required String categoryId,
  required DateTime startDate,
  required DateTime endDate,
  String? targetCurrency,
  Map<String, double>? rates,
}) async {
  try {
    final endInclusive = DateTime(
      endDate.year, endDate.month, endDate.day, 23, 59, 59,
    );

    final snapshot = await FirebaseFirestore.instance
        .collection('expenses')
        .where('userID', isEqualTo: userId)
        .where('categoryID', isEqualTo: categoryId)
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endInclusive)
        .get();

    double total = 0.0;
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final originalAmount   = ((data['originalAmount']   ?? data['amount']) as num).toDouble();
      final originalCurrency = (data['originalCurrency'] as String?) ?? targetCurrency ?? 'MYR';

      if (targetCurrency != null && rates != null && originalCurrency != targetCurrency) {
        total += CurrencyService.convertSync(originalAmount, originalCurrency, targetCurrency, rates);
      } else {
        total += originalAmount;
      }
    }
    return total;
  } catch (e) {
    print('Error calculating spent: $e');
    return 0.0;
  }
}

/// Gets date range based on duration type
/// weekStartDay: 'Monday' or 'Sunday'
Map<String, DateTime> getDateRangeForDuration(
  String durationType,
  String weekStartDay,
) {
  final now = DateTime.now();

  switch (durationType) {
    case 'Weekly':
      // Week calculation based on user preference
      final weekday = now.weekday; // 1=Monday, 7=Sunday
      int daysToSubtract;

      if (weekStartDay == 'Monday') {
        // Week starts Monday (weekday 1)
        daysToSubtract = weekday - 1; // Mon=0, Tue=1, ..., Sun=6
      } else {
        // Week starts Sunday
        daysToSubtract = weekday == 7 ? 0 : weekday; // Sun=0, Mon=1, ..., Sat=6
      }

      final startOfWeek = now.subtract(Duration(days: daysToSubtract));
      final startDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      final endDate = startDate.add(const Duration(days: 6));
      return {
        'start': startDate,
        'end': endDate,
      };

    case 'Yearly':
      final startOfYear = DateTime(now.year, 1, 1);
      final endOfYear = DateTime(now.year, 12, 31);
      return {
        'start': startOfYear,
        'end': endOfYear,
      };

    case 'Monthly':
    default:
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0);
      return {
        'start': startOfMonth,
        'end': endOfMonth,
      };
  }
}

/// Calculates total budget limit for a specific duration
double calculateTotalBudgetLimit(List<Map<String, dynamic>> budgets) {
  double total = 0.0;
  for (var budget in budgets) {
    total += (budget['budgetLimit'] ?? 0).toDouble(); // Ensure double conversion!
  }
  return total;
}

/// Calculates total spent across all budgets for a duration
Future<double> calculateTotalSpent({
  required String userId,
  required List<Map<String, dynamic>> budgets,
  required DateTime startDate,
  required DateTime endDate,
  String? targetCurrency,
  Map<String, double>? rates,
}) async {
  double total = 0.0;
  for (var budget in budgets) {
    final categoryId = budget['categoryID'];
    final spent = await calculateSpentForCategory(
      userId: userId,
      categoryId: categoryId,
      startDate: startDate,
      endDate: endDate,
      targetCurrency: targetCurrency,
      rates: rates,
    );
    total += spent;
  }
  return total;
}

/// Updates an existing budget
Future<bool> updateBudget({
  required String budgetId,
  required double budgetLimit,
}) async {
  try {
    await FirebaseFirestore.instance
        .collection('budgets')
        .doc(budgetId)
        .update({
      'budgetLimit': budgetLimit,
    });
    return true;
  } catch (e) {
    print('Error updating budget: $e');
    return false;
  }
}

/// Deletes a budget
Future<bool> deleteBudget(String budgetId) async {
  try {
    await FirebaseFirestore.instance.collection('budgets').doc(budgetId).delete();
    return true;
  } catch (e) {
    print('Error deleting budget: $e');
    return false;
  }
}

/// Gets budget by ID
Future<Map<String, dynamic>?> getBudgetById(String budgetId) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('budgets')
        .doc(budgetId)
        .get();

    if (doc.exists && doc.data() != null) {
      final data = doc.data() as Map<String, dynamic>; // Cast to Map!
      return {
        'id': doc.id,
        'userID': data['userID'],
        'categoryID': data['categoryID'],
        'budgetLimit': (data['budgetLimit'] ?? 0).toDouble(),
        'durationType': data['durationType'] ?? 'Monthly',
        'createdAt': data['createdAt'],
      };
    }
    return null;
  } catch (e) {
    print('Error getting budget: $e');
    return null;
  }
}
