import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MerchantCategoryManager {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Check if we've seen this merchant before
  Future<String?> getSuggestedCategory(String merchantName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    
    try {
      // Normalize merchant name (lowercase, trim)
      final normalizedName = merchantName.toLowerCase().trim();
      
      // Query user's learned merchants
      final snapshot = await _firestore
          .collection('merchant_categories')
          .where('userId', isEqualTo: user.uid)
          .where('merchantName', isEqualTo: normalizedName)
          .limit(1)
          .get();
      
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first.data()['category'] as String?;
      }
      
      // Not found - check seed database (common merchants)
      return _getSeedCategory(normalizedName);
      
    } catch (e) {
      print('Error getting suggested category: $e');
      return null;
    }
  }
  
  // Save merchant-category mapping
  Future<void> saveMerchantCategory(String merchantName, String category) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      final normalizedName = merchantName.toLowerCase().trim();
      
      // Check if already exists
      final existing = await _firestore
          .collection('merchant_categories')
          .where('userId', isEqualTo: user.uid)
          .where('merchantName', isEqualTo: normalizedName)
          .limit(1)
          .get();
      
      if (existing.docs.isNotEmpty) {
        // Update existing
        await existing.docs.first.reference.update({
          'category': category,
          'lastUsed': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new
        await _firestore.collection('merchant_categories').add({
          'userId': user.uid,
          'merchantName': normalizedName,
          'category': category,
          'createdAt': FieldValue.serverTimestamp(),
          'lastUsed': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Error saving merchant category: $e');
    }
  }
  
  // Seed database: Common Malaysian merchants
  String? _getSeedCategory(String normalizedName) {
    // Common restaurants & food
    if (normalizedName.contains('mcdonald') || 
        normalizedName.contains('kfc') ||
        normalizedName.contains('pizza') ||
        normalizedName.contains('burger') ||
        normalizedName.contains('nasi') ||
        normalizedName.contains('restoran') ||
        normalizedName.contains('restaurant') ||
        normalizedName.contains('cafe') ||
        normalizedName.contains('coffee') ||
        normalizedName.contains('mamak') ||
        normalizedName.contains('kedai makan') ||
        normalizedName.contains('food')) {
      return 'Food & Dining';
    }
    
    // Convenience stores
    if (normalizedName.contains('7-eleven') ||
        normalizedName.contains('seven eleven') ||
        normalizedName.contains('99 speedmart') ||
        normalizedName.contains('mydin') ||
        normalizedName.contains('tesco') ||
        normalizedName.contains('giant') ||
        normalizedName.contains('aeon')) {
      return 'Food & Dining'; // Most purchases are food
    }
    
    // Gas stations
    if (normalizedName.contains('shell') ||
        normalizedName.contains('petron') ||
        normalizedName.contains('petronas') ||
        normalizedName.contains('caltex') ||
        normalizedName.contains('bhp') ||
        normalizedName.contains('petrol')) {
      return 'Transportation';
    }
    
    // Pharmacies
    if (normalizedName.contains('guardian') ||
        normalizedName.contains('watsons') ||
        normalizedName.contains('pharmacy') ||
        normalizedName.contains('farmasi') ||
        normalizedName.contains('clinic') ||
        normalizedName.contains('klinik') ||
        normalizedName.contains('hospital')) {
      return 'Health & Medical';
    }
    
    // Entertainment
    if (normalizedName.contains('cinema') ||
        normalizedName.contains('gsc') ||
        normalizedName.contains('tgv') ||
        normalizedName.contains('karaoke') ||
        normalizedName.contains('bowling')) {
      return 'Entertainment';
    }
    
    // Shopping
    if (normalizedName.contains('uniqlo') ||
        normalizedName.contains('h&m') ||
        normalizedName.contains('zara') ||
        normalizedName.contains('padini') ||
        normalizedName.contains('fashion') ||
        normalizedName.contains('store')) {
      return 'Shopping';
    }
    
    // Bills & utilities
    if (normalizedName.contains('celcom') ||
        normalizedName.contains('maxis') ||
        normalizedName.contains('digi') ||
        normalizedName.contains('unifi') ||
        normalizedName.contains('astro') ||
        normalizedName.contains('tnb') ||
        normalizedName.contains('water') ||
        normalizedName.contains('electric')) {
      return 'Bills & Utilities';
    }
    
    // No match found
    return null;
  }
}
