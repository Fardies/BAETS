import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Helper functions for managing categories and income sources

// ============================================================
// Shared icon/color mapping — SINGLE SOURCE OF TRUTH.
// Previously this same table was copy-pasted separately inside
// home_page.dart, budget_page.dart, budget_report_tab.dart, and
// add_transaction_page.dart (and had drifted out of sync between
// them — e.g. 'Healthcare' vs 'Health & Medical', 'Others' vs 'Other').
// Now every screen imports and reads from these two maps instead,
// so changing an icon/color here updates it everywhere at once.
// ============================================================

final Map<String, Map<String, dynamic>> categoryIconMapping = {
  'Food & Dining':     {'icon': Icons.restaurant_outlined,      'color': Color.fromARGB(255, 244, 149, 181)},
  'Transportation':    {'icon': Icons.directions_car_outlined,  'color': Color(0xFF26C6DA)},
  'Shopping':          {'icon': Icons.shopping_bag_outlined,    'color': Color(0xFFFFB74D)},
  'Entertainment':     {'icon': Icons.movie_outlined,           'color': Color(0xFFAB47BC)},
  'Bills & Utilities': {'icon': Icons.receipt_long_outlined,    'color': Color(0xFFFF8A65)},
  'Health & Medical':  {'icon': Icons.medical_services_outlined,'color': Color(0xFF66BB6A)},
  'Education':         {'icon': Icons.school_outlined,          'color': Color(0xFF42A5F5)},
};

final Map<String, Map<String, dynamic>> incomeIconMapping = {
  'Salary': {'icon': Icons.work_outline,           'color': Color(0xFF66BB6A)},
  'Bonus':  {'icon': Icons.star_outline,           'color': Color(0xFFFFB74D)},
  'Gift':   {'icon': Icons.card_giftcard_outlined, 'color': Color(0xFFFF6B9D)},
};

// Fallback used for any custom category/source the user has added that
// isn't one of the defaults above.
const Map<String, dynamic> defaultIconColor = {
  'icon': Icons.category_outlined,
  'color': Color(0xFF9E9E9E),
};

/// Looks up the icon/color for an expense category name.
Map<String, dynamic> getCategoryIconColor(String categoryName) {
  return categoryIconMapping[categoryName] ?? defaultIconColor;
}

/// Looks up the icon/color for an income source name.
Map<String, dynamic> getIncomeIconColor(String sourceName) {
  return incomeIconMapping[sourceName] ?? defaultIconColor;
}

/// Creates default expense categories for a new user
Future<void> createDefaultExpenseCategories(String userId) async {
  final defaultCategories = [
    {'name': 'Food & Dining', 'userID': userId},
    {'name': 'Transportation', 'userID': userId},
    {'name': 'Shopping', 'userID': userId},
    {'name': 'Entertainment', 'userID': userId},
    {'name': 'Bills & Utilities', 'userID': userId},
    {'name': 'Health & Medical', 'userID': userId},
    {'name': 'Education', 'userID': userId},
    // "Other" removed - users can add custom categories instead!
  ];

  for (var category in defaultCategories) {
    await FirebaseFirestore.instance
        .collection('expenseCategories')
        .add(category);
  }
}

/// Creates default income sources for a new user
Future<void> createDefaultIncomeSources(String userId) async {
  final defaultSources = [
    {'name': 'Salary', 'userID': userId},
    {'name': 'Bonus', 'userID': userId},
    {'name': 'Gift', 'userID': userId},
    // "Other" removed - users can add custom sources instead!
  ];

  for (var source in defaultSources) {
    await FirebaseFirestore.instance
        .collection('incomeSources')
        .add(source);
  }
}

/// Creates both default categories and income sources for a new user
Future<void> createDefaultCategoriesAndSources(String userId) async {
  await createDefaultExpenseCategories(userId);
  await createDefaultIncomeSources(userId);
}

/// Fetches expense categories for the current user
/// Returns them sorted: default categories first (in order), then custom ones alphabetically
Future<List<Map<String, dynamic>>> fetchExpenseCategories(String userId) async {
  final snapshot = await FirebaseFirestore.instance
      .collection('expenseCategories')
      .where('userID', isEqualTo: userId)
      .get();

  final categories = snapshot.docs.map((doc) {
    return {
      'id': doc.id,
      'name': doc.data()['name'] ?? 'Unknown',
      'userID': doc.data()['userID'],
    };
  }).toList();

  // Define default category order
  final defaultOrder = [
    'Food & Dining',
    'Transportation',
    'Shopping',
    'Entertainment',
    'Bills & Utilities',
    'Health & Medical',
    'Education',
  ];

  // Sort: Default categories in order, then custom categories alphabetically
  categories.sort((a, b) {
    final aName = a['name'] as String;
    final bName = b['name'] as String;
    
    final aIndex = defaultOrder.indexOf(aName);
    final bIndex = defaultOrder.indexOf(bName);
    
    // Both are default categories - sort by default order
    if (aIndex != -1 && bIndex != -1) {
      return aIndex.compareTo(bIndex);
    }
    
    // Only a is default - a comes first
    if (aIndex != -1) return -1;
    
    // Only b is default - b comes first
    if (bIndex != -1) return 1;
    
    // Both are custom - sort alphabetically
    return aName.compareTo(bName);
  });

  return categories;
}

/// Fetches income sources for the current user
/// Returns them sorted: default sources first (in order), then custom ones alphabetically
Future<List<Map<String, dynamic>>> fetchIncomeSources(String userId) async {
  final snapshot = await FirebaseFirestore.instance
      .collection('incomeSources')
      .where('userID', isEqualTo: userId)
      .get();

  final sources = snapshot.docs.map((doc) {
    return {
      'id': doc.id,
      'name': doc.data()['name'] ?? 'Unknown',
      'userID': doc.data()['userID'],
    };
  }).toList();

  // Define default source order
  final defaultOrder = [
    'Salary',
    'Bonus',
    'Gift',
  ];

  // Sort: Default sources in order, then custom sources alphabetically
  sources.sort((a, b) {
    final aName = a['name'] as String;
    final bName = b['name'] as String;
    
    final aIndex = defaultOrder.indexOf(aName);
    final bIndex = defaultOrder.indexOf(bName);
    
    // Both are default sources - sort by default order
    if (aIndex != -1 && bIndex != -1) {
      return aIndex.compareTo(bIndex);
    }
    
    // Only a is default - a comes first
    if (aIndex != -1) return -1;
    
    // Only b is default - b comes first
    if (bIndex != -1) return 1;
    
    // Both are custom - sort alphabetically
    return aName.compareTo(bName);
  });

  return sources;
}

/// Gets category name by ID
Future<String> getCategoryNameById(String categoryId) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('expenseCategories')
        .doc(categoryId)
        .get();
    
    if (doc.exists && doc.data() != null) {
      return doc.data()!['name'] ?? 'Unknown';
    }
    return 'Unknown';
  } catch (e) {
    print('Error getting category name: $e');
    return 'Unknown';
  }
}

/// Gets income source name by ID
Future<String> getIncomeSourceNameById(String sourceId) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('incomeSources')
        .doc(sourceId)
        .get();
    
    if (doc.exists && doc.data() != null) {
      return doc.data()!['name'] ?? 'Unknown';
    }
    return 'Unknown';
  } catch (e) {
    print('Error getting income source name: $e');
    return 'Unknown';
  }
}

/// Adds a new custom expense category for a user
Future<String?> addCustomExpenseCategory(String userId, String categoryName) async {
  try {
    final docRef = await FirebaseFirestore.instance
        .collection('expenseCategories')
        .add({
      'name': categoryName,
      'userID': userId,
    });
    return docRef.id;
  } catch (e) {
    print('Error adding custom category: $e');
    return null;
  }
}

/// Adds a new custom income source for a user
Future<String?> addCustomIncomeSource(String userId, String sourceName) async {
  try {
    final docRef = await FirebaseFirestore.instance
        .collection('incomeSources')
        .add({
      'name': sourceName,
      'userID': userId,
    });
    return docRef.id;
  } catch (e) {
    print('Error adding custom income source: $e');
    return null;
  }
}