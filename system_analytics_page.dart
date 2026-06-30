import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';

class SystemAnalyticsPage extends StatefulWidget {
  const SystemAnalyticsPage({super.key});

  @override
  State<SystemAnalyticsPage> createState() => _SystemAnalyticsPageState();
}

class _SystemAnalyticsPageState extends State<SystemAnalyticsPage> {
  bool _isLoading = true;

  // User Growth Data
  Map<String, int> _registrationData = {};
  int _totalUsers = 0;
  int _thisMonthUsers = 0;
  double _growthRate = 0.0;
  List<Map<String, dynamic>> _monthlyGrowthTable = [];

  // Performance Data
  int _activeUsers = 0;
  int _inactiveUsers = 0;
  int _deactivatedUsers = 0;
  Map<String, int> _currencyDistribution = {};
  List<Map<String, dynamic>> _activityBreakdownTable = [];
  Map<String, int> _userEngagementData = {};
  List<Map<String, dynamic>> _engagementBreakdownTable = [];

  @override
  void initState() {
    super.initState();
    _loadAnalyticsData();
  }

  Future<void> _loadAnalyticsData() async {
    try {
      setState(() => _isLoading = true);

      // Load all users
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .orderBy('createdAt')
          .get();

      // Process user growth data
      _processUserGrowthData(usersSnapshot.docs);

      // Process performance data  
      await _processPerformanceData(usersSnapshot.docs);

      setState(() => _isLoading = false);
    } catch (e) {
      print('❌ Error loading analytics data: $e');
      setState(() => _isLoading = false);
    }
  }

  void _processUserGrowthData(List<QueryDocumentSnapshot> users) {
    final now = DateTime.now();
    final registrationCounts = <String, int>{};
    final monthlyData = <Map<String, dynamic>>[];

    // Initialize last 6 months with 0 counts
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthKey = '${_getMonthName(month.month)} ${month.year}';
      registrationCounts[monthKey] = 0;
    }

    int currentMonthCount = 0;
    int lastMonthCount = 0;
    int cumulativeTotal = 0;

    // Process each month for the table
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthKey = '${_getMonthName(month.month)} ${month.year}';
      int monthCount = 0;

      // Count users for this month
      for (var user in users) {
        final data = user.data() as Map<String, dynamic>;
        if (data['createdAt'] != null) {
          final createdAt = (data['createdAt'] as Timestamp).toDate();
          if (createdAt.year == month.year && createdAt.month == month.month) {
            monthCount++;
          }
        }
      }

      registrationCounts[monthKey] = monthCount;
      cumulativeTotal += monthCount;

      // Calculate growth percentage (compare to previous month)
      double growthPercentage = 0.0;
      if (i < 5) { // Not the first month
        final prevMonthCount = monthlyData.isNotEmpty ? monthlyData.last['newUsers'] : 0;
        if (prevMonthCount > 0) {
          growthPercentage = ((monthCount - prevMonthCount) / prevMonthCount) * 100;
        }
      }

      monthlyData.add({
        'month': monthKey,
        'newUsers': monthCount,
        'totalUsers': cumulativeTotal,
        'growthRate': growthPercentage,
      });

      // Track current and last month for summary
      if (month.year == now.year && month.month == now.month) {
        currentMonthCount = monthCount;
      }
      if (month.year == now.year && month.month == now.month - 1) {
        lastMonthCount = monthCount;
      }
    }

    // Calculate overall growth rate
    if (lastMonthCount > 0) {
      _growthRate = ((currentMonthCount - lastMonthCount) / lastMonthCount) * 100;
    } else {
      _growthRate = currentMonthCount > 0 ? 100.0 : 0.0;
    }

    _registrationData = registrationCounts;
    _totalUsers = users.length;
    _thisMonthUsers = currentMonthCount;
    _monthlyGrowthTable = monthlyData;
  }

  Future<void> _processPerformanceData(List<QueryDocumentSnapshot> users) async {
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    int activeCount = 0;
    int deactivatedCount = 0;
    final currencyCount = <String, int>{};
    
    // User engagement metrics
    int usersWithBudgets = 0;
    int usersWithExpenses = 0;
    int completeProfiles = 0;

    for (var user in users) {
      final data = user.data() as Map<String, dynamic>;
      
      // Check active status
      if (data['lastActiveAt'] != null) {
        final lastActive = (data['lastActiveAt'] as Timestamp).toDate();
        if (lastActive.isAfter(thirtyDaysAgo)) {
          activeCount++;
        }
      }

      // Check deactivated status
      if (data['isDisabled'] == true) {
        deactivatedCount++;
      }

      // Count currency distribution
      final currency = data['currency'] ?? 'Unknown';
      currencyCount[currency] = (currencyCount[currency] ?? 0) + 1;

      // Check profile completeness (has email, username, currency)
      if (data['email'] != null && data['username'] != null && data['currency'] != null) {
        completeProfiles++;
      }
    }

    _activeUsers = activeCount;
    _inactiveUsers = users.length - activeCount - deactivatedCount;
    _deactivatedUsers = deactivatedCount;
    _currencyDistribution = currencyCount;

    // Get user engagement data
    usersWithBudgets = await _getUsersWithData('budgets');
    usersWithExpenses = await _getUsersWithData('expenses');

    _userEngagementData = {
      'Complete Profiles': completeProfiles,
      'Users with Budgets': usersWithBudgets,
      'Users with Expenses': usersWithExpenses,
      'Empty Accounts': users.length - usersWithExpenses,
    };

    // Build activity breakdown table
    _activityBreakdownTable = [
      {
        'level': 'Active (last 30 days)',
        'count': _activeUsers,
        'percentage': ((_activeUsers / users.length) * 100).toStringAsFixed(1),
      },
      {
        'level': 'Inactive (30+ days)',
        'count': _inactiveUsers,
        'percentage': ((_inactiveUsers / users.length) * 100).toStringAsFixed(1),
      },
      {
        'level': 'Deactivated by Admin',
        'count': _deactivatedUsers,
        'percentage': ((_deactivatedUsers / users.length) * 100).toStringAsFixed(1),
      },
    ];

    // Build engagement breakdown table
    _engagementBreakdownTable = [];
    for (var entry in _userEngagementData.entries) {
      _engagementBreakdownTable.add({
        'metric': entry.key,
        'count': entry.value,
        'percentage': users.isNotEmpty ? 
          ((entry.value / users.length) * 100).toStringAsFixed(1) : '0.0',
      });
    }
  }

  Future<int> _getUsersWithData(String collection) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(collection)
          .get();
      
      final uniqueUsers = <String>{};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['userID'] != null) {
          uniqueUsers.add(data['userID']);
        }
      }
      return uniqueUsers.length;
    } catch (e) {
      return 0;
    }
  }

  Future<int> _getCollectionCount(String collection) async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection(collection).get();
      return snapshot.docs.length;
    } catch (e) {
      return 0;
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
            Icon(Icons.analytics, color: Colors.green),
            const SizedBox(width: 8),
            const Text(
              'System Analytics',
              style: TextStyle(color: Colors.black87),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and Export button (stacked)
                  Text(
                    'Analytics Dashboard',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _exportCompleteReport,
                    icon: Icon(Icons.picture_as_pdf, size: 18),
                    label: Text('Export PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // User Growth Section
                  _buildSectionHeader('User Growth Overview'),
                  const SizedBox(height: 16),
                  _buildGrowthSummaryCards(),
                  const SizedBox(height: 24),
                  _buildUserGrowthChart(),
                  const SizedBox(height: 24),
                  _buildMonthlyGrowthTable(),
                  
                  const SizedBox(height: 40),
                  
                  // User Activity Section
                  _buildSectionHeader('User Activity Analysis'),
                  const SizedBox(height: 16),
                  _buildPerformanceSummaryCards(),
                  const SizedBox(height: 24),
                  _buildUserActivityChart(),
                  const SizedBox(height: 24),
                  _buildActivityBreakdownTable(),
                ],
              ),
            ),
    );
  }

  Widget _buildUserGrowthTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Export button and summary cards
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'User Growth Analytics',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _exportCompleteReport,
                icon: Icon(Icons.picture_as_pdf, size: 16),
                label: Text('Export PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Summary Cards
          _buildGrowthSummaryCards(),
          const SizedBox(height: 24),

          // User Registration Chart
          _buildUserGrowthChart(),
          const SizedBox(height: 24),

          // Monthly Growth Table
          _buildMonthlyGrowthTable(),
        ],
      ),
    );
  }

  Widget _buildPerformanceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Export button and summary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Performance Analytics',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _exportCompleteReport,
                icon: Icon(Icons.picture_as_pdf, size: 16),
                label: Text('Export PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Performance Cards
          _buildPerformanceSummaryCards(),
          const SizedBox(height: 24),

          // User Activity Chart
          _buildUserActivityChart(),
          const SizedBox(height: 24),

          // User Engagement Chart (replaces feature usage)
          _buildUserEngagementChart(),
          const SizedBox(height: 24),

          // Activity Breakdown Table
          _buildActivityBreakdownTable(),
          const SizedBox(height: 24),

          // User Engagement Table (replaces feature usage table)
          _buildEngagementBreakdownTable(),
        ],
      ),
    );
  }

  Widget _buildGrowthSummaryCards() {
    final cards = [
      {
        'title': 'Total Users',
        'value': '$_totalUsers',
        'icon': Icons.people,
        'color': Colors.blue,
      },
      {
        'title': 'This Month',
        'value': '$_thisMonthUsers',
        'icon': Icons.person_add,
        'color': Colors.green,
      },
    ];

    return Row(
      children: cards.asMap().entries.map((e) {
        final i    = e.key;
        final card = e.value;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == 0 ? 8 : 0),
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
              children: [
                Icon(card['icon'] as IconData,
                    color: card['color'] as Color, size: 24),
                const SizedBox(height: 8),
                Text(
                  card['value'] as String,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                ),
                const SizedBox(height: 4),
                Text(
                  card['title'] as String,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPerformanceSummaryCards() {
    final cards = [
      {
        'title': 'Active Users',
        'value': '$_activeUsers',
        'icon': Icons.people_outline,
        'color': Colors.green,
      },
      {
        'title': 'Inactive Users',
        'value': '$_inactiveUsers',
        'icon': Icons.people_alt_outlined,
        'color': Colors.orange,
      },
    ];

    return Row(
      children: [
        Expanded(child: _buildPerformanceCard(cards[0])),
        const SizedBox(width: 8),
        Expanded(child: _buildPerformanceCard(cards[1])),
      ],
    );
  }

  Widget _buildPerformanceCard(Map<String, dynamic> card) {
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
        children: [
          Icon(
            card['icon'] as IconData,
            color: card['color'] as Color,
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            card['value'] as String,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            card['title'] as String,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildUserGrowthChart() {
    return Container(
      height: 300,
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
          Text(
            'User Registration (Last 6 Months)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final months = _registrationData.keys.toList();
                        if (value.toInt() >= 0 && value.toInt() < months.length) {
                          final month = months[value.toInt()];
                          return Text(
                            month.split(' ')[0], // Show only month name
                            style: TextStyle(fontSize: 10),
                          );
                        }
                        return Text('');
                      },
                    ),
                  ),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: _registrationData.values.toList().asMap().entries.map((entry) {
                      return FlSpot(entry.key.toDouble(), entry.value.toDouble());
                    }).toList(),
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserActivityChart() {
    return Container(
      height: 300,
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
          Text(
            'User Activity Status',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (_activeUsers + _inactiveUsers).toDouble() * 1.2,
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        switch (value.toInt()) {
                          case 0:
                            return Text('Active', style: TextStyle(fontSize: 12));
                          case 1:
                            return Text('Inactive', style: TextStyle(fontSize: 12));
                          default:
                            return Text('');
                        }
                      },
                    ),
                  ),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true),
                barGroups: [
                  BarChartGroupData(
                    x: 0,
                    barRods: [
                      BarChartRodData(
                        toY: _activeUsers.toDouble(),
                        color: Colors.green,
                        width: 40,
                      ),
                    ],
                  ),
                  BarChartGroupData(
                    x: 1,
                    barRods: [
                      BarChartRodData(
                        toY: _inactiveUsers.toDouble(),
                        color: Colors.orange,
                        width: 40,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserEngagementChart() {
    return Container(
      height: 300,
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
          Text(
            'User Engagement Distribution',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _userEngagementData.isEmpty
                ? Center(child: Text('No data available'))
                : PieChart(
                    PieChartData(
                      pieTouchData: PieTouchData(enabled: true),
                      sections: _userEngagementData.entries.map((entry) {
                        final colors = [Colors.purple, Colors.teal, Colors.amber, Colors.indigo];
                        final index = _userEngagementData.keys.toList().indexOf(entry.key);
                        return PieChartSectionData(
                          color: colors[index % colors.length],
                          value: entry.value.toDouble(),
                          title: '${entry.key}\n${entry.value}',
                          radius: 80,
                          titleStyle: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyGrowthTable() {
    return Container(
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
          Text(
            'Monthly Growth Breakdown',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Month')),
                DataColumn(label: Text('New Users')),
                DataColumn(label: Text('Total Users')),
              ],
              rows: _monthlyGrowthTable.map((row) {
                return DataRow(
                  cells: [
                    DataCell(Text(row['month'])),
                    DataCell(Text('${row['newUsers']}')),
                    DataCell(Text('${row['totalUsers']}')),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityBreakdownTable() {
    return Container(
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
          Text(
            'User Activity Breakdown',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: MediaQuery.of(context).size.width - 32,
              ),
              child: DataTable(
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Expanded(child: Text('Activity Level'))),
                  DataColumn(label: Text('Count')),
                  DataColumn(label: Text('%')),
                ],
                rows: _activityBreakdownTable.map((row) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Container(
                          width: 120,
                          child: Text(
                            row['level'],
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      DataCell(Text('${row['count']}')),
                      DataCell(Text('${row['percentage']}%')),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEngagementBreakdownTable() {
    return Container(
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
          Text(
            'User Engagement Breakdown',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: MediaQuery.of(context).size.width - 32,
              ),
              child: DataTable(
                columnSpacing: 15,
                columns: const [
                  DataColumn(label: Text('Engagement Type')),
                  DataColumn(label: Text('Count')),
                  DataColumn(label: Text('%')),
                ],
                rows: _engagementBreakdownTable.map((row) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Container(
                          width: 120,
                          child: Text(
                            row['metric'],
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      DataCell(Text('${row['count']}')),
                      DataCell(Text('${row['percentage']}%')),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // TEST PDF function to check if PDF generation works
  Future<void> _testPDFGeneration() async {
    try {
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) => pw.Center(
            child: pw.Text('PDF Test Successful!', style: pw.TextStyle(fontSize: 24)),
          ),
        ),
      );
      
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'test.pdf',
      );
      
      print('✅ PDF generation works!');
    } catch (e) {
      print('❌ PDF error: $e');
    }
  }

  // Export functions - Complete PDF Analytics Report
  Future<void> _exportCompleteReport() async {
    try {
      print('🔄 Starting PDF export...');
      
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      print('📄 Creating PDF document...');
      final pdf = pw.Document();
      
      // Generate PDF content
      print('📊 Generating PDF content...');
      await _generatePDFContent(pdf);
      
      // Close loading dialog
      print('✅ Closing loading dialog...');
      Navigator.of(context).pop();
      
      // Show PDF preview and allow download
      print('📱 Showing PDF preview...');
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'BAETS_Analytics_Report_${DateTime.now().toIso8601String().split('T')[0]}.pdf',
      );

      print('🎉 PDF generated successfully!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Analytics report generated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, stackTrace) {
      print('❌ PDF Export Error: $e');
      print('📍 Stack Trace: $stackTrace');
      
      // Close loading dialog if open
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _generatePDFContent(pw.Document pdf) async {
    // Add pages to PDF
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header
            _buildPDFHeader(),
            pw.SizedBox(height: 30),
            
            // Executive Summary
            _buildPDFSummary(),
            pw.SizedBox(height: 30),
            
            // User Growth Section
            _buildPDFUserGrowthSection(),
            pw.SizedBox(height: 30),
            
            // User Activity Section  
            _buildPDFUserActivitySection(),
            pw.SizedBox(height: 20),
            
            // Footer
            _buildPDFFooter(),
          ];
        },
      ),
    );
  }

  pw.Widget _buildPDFHeader() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'BAETS BUDGET APP',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue700,
                  ),
                ),
                pw.Text(
                  'System Analytics Report',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.normal,
                  ),
                ),
              ],
            ),
            pw.Text(
              'Generated: ${DateTime.now().toLocal().toString().split(' ')[0]}',
              style: pw.TextStyle(
                fontSize: 12,
                color: PdfColors.grey600,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(color: PdfColors.blue700, thickness: 2),
      ],
    );
  }

  pw.Widget _buildPDFSummary() {
    final activePercentage = _totalUsers > 0 
        ? ((_activeUsers / _totalUsers) * 100).toStringAsFixed(1)
        : '0.0';
        
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Executive Summary',
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 15),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            _buildPDFStatCard('Total Users', '$_totalUsers', PdfColors.blue),
            _buildPDFStatCard('Active Users', '$_activeUsers', PdfColors.green),
            _buildPDFStatCard('Activity Rate', '$activePercentage%', PdfColors.orange),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildPDFStatCard(String title, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color, width: 1),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPDFUserGrowthSection() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'User Growth Analysis',
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 15),
        
        // Monthly Growth Table
        pw.Text(
          'Monthly Registration Breakdown',
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          context: null,
          headers: ['Month', 'New Users', 'Total Users'],
          data: _monthlyGrowthTable.map((row) => [
            row['month'],
            '${row['newUsers']}',
            '${row['totalUsers']}',
          ]).toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 12),
          cellHeight: 30,
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.center,
            2: pw.Alignment.center,
          },
        ),
      ],
    );
  }

  pw.Widget _buildPDFUserActivitySection() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'User Activity Analysis',
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 15),
        
        // Activity Breakdown
        pw.Text(
          'Activity Level Breakdown',
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          context: null,
          headers: ['Activity Level', 'Count', 'Percentage'],
          data: _activityBreakdownTable.map((row) => [
            row['level'],
            '${row['count']}',
            '${row['percentage']}%',
          ]).toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 12),
          cellHeight: 30,
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.center,
            2: pw.Alignment.center,
          },
        ),
      ],
    );
  }

  pw.Widget _buildPDFFooter() {
    return pw.Container(
      alignment: pw.Alignment.center,
      child: pw.Text(
        'This report was generated automatically by BAETS Admin Dashboard',
        style: pw.TextStyle(
          fontSize: 10,
          color: PdfColors.grey600,
          fontStyle: pw.FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
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





