import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_auth_service.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  final AdminAuthService _authService = AdminAuthService();
  final TextEditingController _searchController = TextEditingController();
  
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  Map<String, dynamic>? _userStats;
  bool _isLoading = true;
  String _selectedFilter = 'all'; // all, active, inactive, myr, others

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      setState(() => _isLoading = true);

      // Load all users
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .orderBy('createdAt', descending: true)
          .get();

      final users = <Map<String, dynamic>>[];
      
      for (var doc in usersSnapshot.docs) {
        final userData = doc.data();
        userData['id'] = doc.id;
        
        // Check if user is active (has activity in last 30 days)
        final isActive = await _checkUserActivity(doc.id);
        userData['isActive'] = isActive;
        userData['status'] = userData['isDisabled'] == true ? 'inactive' : 'active';
        
        users.add(userData);
      }

      // Calculate stats
      final stats = _calculateUserStats(users);

      setState(() {
        _allUsers = users;
        _filteredUsers = users;
        _userStats = stats;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading users: $e');
      setState(() => _isLoading = false);
      _showErrorSnackBar('Failed to load users: $e');
    }
  }

  Future<bool> _checkUserActivity(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      
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

  Map<String, dynamic> _calculateUserStats(List<Map<String, dynamic>> users) {
    final totalUsers = users.length;
    final activeUsers = users.where((user) => user['isActive'] == true).length;
    final myrUsers = users.where((user) => user['currency'] == 'MYR').length;
    final otherCurrencyUsers = totalUsers - myrUsers;
    final inactiveAccounts = users.where((user) => user['status'] == 'inactive').length;

    // Registration by month (last 6 months)
    final registrationStats = <String, int>{};
    final now = DateTime.now();
    
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthKey = '${_getMonthName(month.month)} ${month.year}';
      registrationStats[monthKey] = 0;
    }

    for (var user in users) {
      if (user['createdAt'] != null) {
        final createdAt = (user['createdAt'] as Timestamp).toDate();
        final monthKey = '${_getMonthName(createdAt.month)} ${createdAt.year}';
        if (registrationStats.containsKey(monthKey)) {
          registrationStats[monthKey] = registrationStats[monthKey]! + 1;
        }
      }
    }

    return {
      'totalUsers': totalUsers,
      'activeUsers': activeUsers,
      'myrUsers': myrUsers,
      'otherCurrencyUsers': otherCurrencyUsers,
      'inactiveAccounts': inactiveAccounts,
      'registrationStats': registrationStats,
    };
  }

  void _filterUsers() {
    final searchTerm = _searchController.text.toLowerCase();
    
    setState(() {
      _filteredUsers = _allUsers.where((user) {
        // Text search
        final matchesSearch = searchTerm.isEmpty ||
            user['username']?.toLowerCase().contains(searchTerm) == true ||
            user['email']?.toLowerCase().contains(searchTerm) == true;

        // Filter by status/type
        final matchesFilter = _selectedFilter == 'all' ||
            (_selectedFilter == 'active' && user['isActive'] == true) ||
            (_selectedFilter == 'inactive' && user['isActive'] != true) ||
            (_selectedFilter == 'deactivated' && user['isDisabled'] == true);

        return matchesSearch && matchesFilter;
      }).toList();
    });
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
            Icon(Icons.people_alt, color: Colors.blue),
            const SizedBox(width: 8),
            const Text(
              'User Management',
              style: TextStyle(color: Colors.black87),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.grey[600]),
            onPressed: _loadUserData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats Overview
                  _buildStatsSection(),
                  const SizedBox(height: 28), // More space (was 24)
                  
                  // Search & Filter
                  _buildSearchAndFilter(),
                  const SizedBox(height: 20), // More space (was 16)
                  
                  // Users Table
                  _buildUsersTable(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsSection() {
    if (_userStats == null) return Container();

    final stats = [
      {
        'title': 'Total Users',
        'value': '${_userStats!['totalUsers']}',
        'icon': Icons.people,
        'color': Colors.blue,
      },
      {
        'title': 'Active Users',
        'value': '${_userStats!['activeUsers']}',
        'icon': Icons.people_outline,
        'color': Colors.green,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'User Statistics',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16), // More space (was 12)
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.2, // Same as dashboard
            crossAxisSpacing: 12,   // Same as dashboard  
            mainAxisSpacing: 12,    // Same as dashboard
          ),
          itemCount: stats.length,
          itemBuilder: (context, index) {
            final stat = stats[index];
            return Container(
              padding: const EdgeInsets.all(16), // Same as dashboard
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
                    size: 32, // Same as dashboard
                  ),
                  const SizedBox(height: 8),
                  Text(
                    stat['value'] as String,
                    style: const TextStyle(
                      fontSize: 24, // Same as dashboard
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stat['title'] as String,
                    style: TextStyle(
                      fontSize: 12, // Same as dashboard
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

  Widget _buildSearchAndFilter() {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search & Filter Users',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          
          // Search bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by username or email...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.blue),
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Filter chips
          Wrap(
            spacing: 8,
            children: [
              _buildFilterChip('All Users', 'all'),
              _buildFilterChip('Active', 'active'),
              _buildFilterChip('Inactive', 'inactive'),
              _buildFilterChip('Deactivated', 'deactivated'),
            ],
          ),
          const SizedBox(height: 8),
          
          // Results count
          Text(
            'Showing ${_filteredUsers.length} of ${_allUsers.length} users',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = selected ? value : 'all';
        });
        _filterUsers();
      },
      selectedColor: Colors.blue[100],
      checkmarkColor: Colors.blue[700],
    );
  }

  Widget _buildUsersTable() {
    return Container(
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
          // Table header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'User List',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          
          // Table content
          _filteredUsers.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.search_off, size: 48, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(
                          'No users found',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _filteredUsers.length,
                  itemBuilder: (context, index) {
                    final user = _filteredUsers[index];
                    return _buildUserRow(user, index);
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildUserRow(Map<String, dynamic> user, int index) {
    final createdAt = user['createdAt'] != null
        ? (user['createdAt'] as Timestamp).toDate()
        : null;
    
    final isActive = user['isActive'] == true;
    final isDisabled = user['status'] == 'inactive';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), // More vertical padding (was 12)
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          // User info
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Username
                Text(
                  user['username'] ?? 'Unknown',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                
                // Email + Active status
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user['email'] ?? 'No email',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      ' • ',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      isActive ? 'Active' : 'Inactive',
                      style: TextStyle(
                        color: isActive ? Colors.green[600] : Colors.grey[500],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                
                // Registration date
                Text(
                  createdAt != null 
                      ? '${createdAt.day} ${_getMonthName(createdAt.month)} ${createdAt.year}'
                      : 'Unknown registration date',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                
                // Currency badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: user['currency'] == 'MYR' 
                        ? Colors.blue[50] 
                        : Colors.orange[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: user['currency'] == 'MYR' 
                          ? Colors.blue[200]! 
                          : Colors.orange[200]!,
                    ),
                  ),
                  child: Text(
                    user['currency'] ?? 'Unknown',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: user['currency'] == 'MYR' 
                          ? Colors.blue[700] 
                          : Colors.orange[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Actions
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 18),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'view',
                child: Row(
                  children: [
                    Icon(Icons.visibility, size: 16),
                    SizedBox(width: 8),
                    Text('View Profile'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: isDisabled ? 'activate' : 'deactivate',
                child: Row(
                  children: [
                    Icon(
                      isDisabled ? Icons.check_circle : Icons.block,
                      size: 16,
                      color: isDisabled ? Colors.green : Colors.red,
                    ),
                    SizedBox(width: 8),
                    Text(isDisabled ? 'Activate' : 'Deactivate'),
                  ],
                ),
              ),
            ],
            onSelected: (action) => _handleUserAction(action, user),
          ),
        ],
      ),
    );
  }

  void _handleUserAction(String action, Map<String, dynamic> user) {
    switch (action) {
      case 'view':
        _showUserProfile(user);
        break;
      case 'activate':
      case 'deactivate':
        _showStatusChangeConfirmation(user, action == 'activate');
        break;
    }
  }

  void _showUserProfile(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.person, color: Colors.blue),
            SizedBox(width: 8),
            Text('User Profile'),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileRow('Username', user['username'] ?? 'Unknown'),
              _buildProfileRow('Email', user['email'] ?? 'No email'),
              _buildProfileRow('Currency', user['currency'] ?? 'Unknown'),
              _buildProfileRow(
                'Registration Date',
                user['createdAt'] != null
                    ? () {
                        final date = (user['createdAt'] as Timestamp).toDate();
                        return '${date.day} ${_getMonthName(date.month)} ${date.year}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                      }()
                    : 'Unknown',
              ),
              _buildProfileRow(
                'Account Status',
                user['status'] == 'inactive' ? 'Deactivated by admin' : 'Active',
              ),
              _buildProfileRow(
                'Usage Status',
                user['isActive'] == true 
                    ? 'Active (used in last 30 days)' 
                    : 'Inactive (no activity in last 30 days)',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  void _showStatusChangeConfirmation(Map<String, dynamic> user, bool activate) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(activate ? 'Activate User' : 'Deactivate User'),
        content: Text(
          activate
              ? 'Are you sure you want to activate ${user['username']}\'s account?'
              : 'Are you sure you want to deactivate ${user['username']}\'s account? They won\'t be able to log in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _updateUserStatus(user['id'], !activate);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: activate ? Colors.green : Colors.red,
            ),
            child: Text(activate ? 'Activate' : 'Deactivate'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateUserStatus(String userId, bool disable) async {
    try {
      // Update both isDisabled and status fields for consistency
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({
            'isDisabled': disable,
            'status': disable ? 'inactive' : 'active', // Add status field too
          });

      // TODO: Add admin activity logging once implemented
      // await _authService.logAdminActivity(...)

      _showSuccessSnackBar(
        disable ? 'User account deactivated successfully' : 'User account activated successfully',
      );
      
      // Reload data to show changes
      await _loadUserData();
    } catch (e) {
      print('❌ Error updating user status: $e');
      _showErrorSnackBar('Failed to update user status. Please check your admin permissions.');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month];
  }
}