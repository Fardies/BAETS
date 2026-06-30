import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserActivityService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Call this whenever user opens the app
  static Future<void> updateLastActive() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'lastActiveAt': FieldValue.serverTimestamp(),
        });
        print('✅ Updated lastActiveAt for user: ${user.uid}');
      }
    } catch (e) {
      print('❌ Error updating lastActiveAt: $e');
      // Don't throw error - this shouldn't break app
    }
  }

  // Helper to check if user is active (used in last 30 days)
  static Future<bool> isUserActive(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists || userDoc.data()?['lastActiveAt'] == null) {
        return false;
      }

      final lastActive = (userDoc.data()!['lastActiveAt'] as Timestamp).toDate();
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      
      return lastActive.isAfter(thirtyDaysAgo);
    } catch (e) {
      print('❌ Error checking user activity: $e');
      return false;
    }
  }

  // Get count of active users
  static Future<int> getActiveUserCount() async {
    try {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      
      final usersSnapshot = await _firestore
          .collection('users')
          .where('lastActiveAt', isGreaterThan: Timestamp.fromDate(thirtyDaysAgo))
          .get();
      
      return usersSnapshot.docs.length;
    } catch (e) {
      print('❌ Error getting active user count: $e');
      return 0;
    }
  }

  // Optional: Initialize lastActiveAt for existing users who don't have it
  static Future<void> initializeLastActiveForExistingUsers() async {
    try {
      final usersSnapshot = await _firestore
          .collection('users')
          .get();

      final batch = _firestore.batch();
      int updateCount = 0;
      
      for (var doc in usersSnapshot.docs) {
        final data = doc.data();
        if (data['lastActiveAt'] == null) {
          batch.update(doc.reference, {
            'lastActiveAt': FieldValue.serverTimestamp(),
          });
          updateCount++;
        }
      }

      if (updateCount > 0) {
        await batch.commit();
        print('✅ Initialized lastActiveAt for $updateCount users');
      } else {
        print('✅ All users already have lastActiveAt field');
      }
    } catch (e) {
      print('❌ Error initializing lastActiveAt: $e');
    }
  }
}
