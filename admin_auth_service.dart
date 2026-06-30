import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Sign in admin with email and password
  Future<UserCredential?> signInAdmin(String email, String password) async {
    try {
      // Verify email is from baets.com domain
      if (!email.toLowerCase().endsWith('@baets.com')) {
        throw Exception('Only @baets.com email addresses are allowed');
      }

      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Log admin login activity
      await _logAdminActivity(
        'Admin Login',
        'Admin logged in: $email',
      );

      return userCredential;
    } catch (e) {
      print('❌ Admin sign in error: $e');
      rethrow;
    }
  }

  // Sign out admin
  Future<void> signOutAdmin() async {
    try {
      final email = _auth.currentUser?.email;
      await _auth.signOut();
      
      if (email != null) {
        await _logAdminActivity(
          'Admin Logout', 
          'Admin logged out: $email',
        );
      }
    } catch (e) {
      print('❌ Admin sign out error: $e');
      rethrow;
    }
  }

  // Get current admin info
  Future<Map<String, dynamic>?> getAdminInfo() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        return {
          'uid': user.uid,
          'email': user.email,
          'displayName': user.displayName ?? user.email?.split('@')[0] ?? 'Admin',
        };
      }
      return null;
    } catch (e) {
      print('❌ Error getting admin info: $e');
      return null;
    }
  }

  // Get dashboard statistics with consistent lastActiveAt logic
  Future<Map<String, dynamic>> getDashboardStats() async {
    try {
      // Get total users
      final usersSnapshot = await _firestore.collection('users').get();
      final totalUsers = usersSnapshot.docs.length;
      
      // Get active users (lastActiveAt in last 30 days)
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      
      int activeUsers = 0;
      for (var doc in usersSnapshot.docs) {
        final data = doc.data();
        if (data['lastActiveAt'] != null) {
          final lastActive = (data['lastActiveAt'] as Timestamp).toDate();
          if (lastActive.isAfter(thirtyDaysAgo)) {
            activeUsers++;
          }
        }
      }

      return {
        'totalUsers': totalUsers,
        'activeUsers': activeUsers,
      };
    } catch (e) {
      print('❌ Error getting dashboard stats: $e');
      return {
        'totalUsers': 0,
        'activeUsers': 0,
      };
    }
  }

  // Log admin activity
  Future<void> _logAdminActivity(String action, String description) async {
    try {
      await _firestore.collection('admin_activity_logs').add({
        'action': action,
        'description': description,
        'adminEmail': _auth.currentUser?.email,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Error logging admin activity: $e');
      // Don't throw - logging failure shouldn't break functionality
    }
  }

  // Get recent admin activity logs
  Future<List<Map<String, dynamic>>> getRecentAdminActivity({int limit = 10}) async {
    try {
      final querySnapshot = await _firestore
          .collection('admin_activity_logs')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('❌ Error getting admin activity: $e');
      return [];
    }
  }

  // Check if current user is admin
  bool isAdmin() {
    final email = _auth.currentUser?.email;
    return email != null && email.toLowerCase().endsWith('@baets.com');
  }
}

