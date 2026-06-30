import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_auth_service.dart'; // Use updated version that excludes admin users
import 'admin_login_screen.dart';
import 'user_management_page.dart';
import 'system_analytics_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
} 

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final AdminAuthService _authService = AdminAuthService();
  Map<String, dynamic>? _adminInfo;
  Map<String, dynamic>? _dashboardStats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      setState(() => _isLoading = true);

      // Load admin info
      final adminInfo = await _authService.getAdminInfo();

      // Load users directly and filter out admin users
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();

      print('🔍 DEBUGGING USER EMAILS:');
      print('Total docs found: ${usersSnapshot.docs.length}');
      
      // Print all emails AND document data for debugging
      for (var doc in usersSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final email = data['email'] as String? ?? '';
        print('📧 Doc ID: ${doc.id} | Email: "$email" | Full data keys: ${data.keys.toList()}');
      }

      // Filter out invalid users (empty emails, temp docs, admin users)
      final nonAdminUsers = usersSnapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final email = data['email'] as String? ?? '';
        
        // Skip documents with empty emails (temp/invalid docs)
        if (email.isEmpty) {
          print('🗑️ Skipping invalid doc: ${doc.id} (empty email)');
          return false;
        }
        
        // Skip documents that only have temp field (garbage data)
        if (data.keys.length == 1 && data.containsKey('temp')) {
          print('🗑️ Skipping temp doc: ${doc.id}');
          return false;
        }
        
        // Skip admin users  
        final isAdminEmail = email.toLowerCase() == 'admin@baets.com';
        final isAdminDomain = email.endsWith('@baets.com');
        final isAdmin = isAdminEmail || isAdminDomain;
        
        if (isAdmin) {
          print('🔒 Skipping admin user: $email');
          return false;
        }
        
        print('✅ Valid user: $email');
        return true; // Keep valid non-admin users only
      }).toList();

      print('✅ After filtering: ${nonAdminUsers.length} non-admin users');

      // Calculate stats from filtered users
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      int activeUsers = 0;

      for (var userDoc in nonAdminUsers) {
        final data = userDoc.data() as Map<String, dynamic>;
        if (data['lastActiveAt'] != null) {
          final lastActive = (data['lastActiveAt'] as Timestamp).toDate();
          if (lastActive.isAfter(thirtyDaysAgo)) {
            activeUsers++;
          }
        }
      }

      final dashboardStats = {
        'totalUsers': nonAdminUsers.length,  // Only non-admin users
        'activeUsers': activeUsers,
      };

      setState(() {
        _adminInfo = adminInfo;
        _dashboardStats = dashboardStats;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading dashboard data: $e');
      setState(() => _isLoading = false);
      
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load dashboard: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EEF1),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.admin_panel_settings, color: Colors.blue),
            const SizedBox(width: 8),
            const Text(
              'BAETS Admin',
              style: TextStyle(color: Colors.black87),
            ),
          ],
        ),
        actions: [
          // Admin info dropdown
          PopupMenuButton<String>(
            icon: CircleAvatar(
              backgroundColor: Colors.blue[100],
              child: Text(
                _adminInfo?['displayName']?.substring(0, 1).toUpperCase() ?? 'A',
                style: TextStyle(
                  color: Colors.blue[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _adminInfo?['displayName'] ?? 'Admin',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _adminInfo?['email'] ?? '',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
            onSelected: _handleMenuSelection,
          ),
          SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Section
                  _buildWelcomeSection(),
                  const SizedBox(height: 24),
                  
                  // Stats Overview
                  _buildStatsOverview(),
                  const SizedBox(height: 24),
                  
                  // Quick Actions
                  _buildQuickActions(),
                ],
              ),
            ),
    );
  }

  Widget _buildWelcomeSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dashboard, color: Colors.blue, size: 24),
              SizedBox(width: 12),
              Text(
                'System Owner Dashboard',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Welcome back, ${_adminInfo?['displayName'] ?? 'Admin'}! Here\'s your system overview.',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsOverview() {
    if (_dashboardStats == null) {
      return Container();
    }

    final stats = [
      {
        'title': 'Total Users',
        'value': '${_dashboardStats!['totalUsers']}',
        'icon': Icons.people,
        'color': Colors.blue,
      },
      {
        'title': 'Active Users',
        'value': '${_dashboardStats!['activeUsers']}',
        'icon': Icons.people_outline,
        'color': Colors.green,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'System Overview',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: stats.length,
          itemBuilder: (context, index) {
            final stat = stats[index];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    stat['icon'] as IconData,
                    color: stat['color'] as Color,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    stat['value'] as String,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stat['title'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      {
        'title': 'User Management',
        'subtitle': 'View and manage user accounts',
        'icon': Icons.people_alt,
        'color': Colors.blue,
        'action': 'users',
      },
      {
        'title': 'System Analytics',
        'subtitle': 'View detailed app analytics',
        'icon': Icons.analytics,
        'color': Colors.green,
        'action': 'analytics',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          itemBuilder: (context, index) {
            final action = actions[index];
            return Container(
              margin: EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (action['color'] as Color).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    action['icon'] as IconData,
                    color: action['color'] as Color,
                  ),
                ),
                title: Text(
                  action['title'] as String,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(action['subtitle'] as String),
                trailing: Icon(Icons.chevron_right),
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () => _handleQuickAction(action['action'] as String),
              ),
            );
          },
        ),
      ],
    );
  }

  void _handleMenuSelection(String value) async {
    switch (value) {
      case 'logout':
        await _showLogoutConfirmation();
        break;
    }
  }

  void _handleQuickAction(String action) {
    switch (action) {
      case 'users':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const UserManagementPage(),
          ),
        );
        break;
      case 'analytics':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const SystemAnalyticsPage(),
          ),
        );
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$action feature coming soon!'),
            backgroundColor: Colors.blue,
          ),
        );
    }
  }

  Future<void> _showLogoutConfirmation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Logout'),
        content: Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _logout();
    }
  }

  Future<void> _logout() async {
    try {
      await _authService.signOutAdmin();
      
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => AdminLoginScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}