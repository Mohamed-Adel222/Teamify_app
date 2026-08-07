import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';

class AdminLeaderboardScreen extends StatefulWidget {
  const AdminLeaderboardScreen({super.key});

  @override
  State<AdminLeaderboardScreen> createState() => _AdminLeaderboardScreenState();
}

class _AdminLeaderboardScreenState extends State<AdminLeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = true;
  String? _error;
  List<dynamic> _ratings = [];
  List<dynamic> _feedback = [];

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _categoryFilter = 'Overall';
  String _timeFilter = 'All Time';
  String _sortBy = 'Rank';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final admin = context.read<AppServices>().admin;
    String? error;
    List<dynamic> ratings = [];
    List<dynamic> feedback = [];

    final ratingsResult = await admin.getRatingsLeaderboard(
      page: 1,
      search: _searchQuery,
      category: _categoryFilter,
      timePeriod: _timeFilter,
      sortBy: _sortBy,
    );
    ratingsResult.when(
      success: (data) => ratings = data['items'] as List? ?? [],
      failure: (msg) => error = msg,
    );

    final feedbackResult = await admin.getFeedbackLeaderboard(
      page: 1,
      search: _searchQuery,
      category: _categoryFilter,
      timePeriod: _timeFilter,
      sortBy: _sortBy,
    );
    feedbackResult.when(
      success: (data) => feedback = data['items'] as List? ?? [],
      failure: (msg) {
        error ??= msg;
      },
    );

    if (!mounted) return;
    setState(() {
      _ratings = ratings;
      _feedback = feedback;
      _error = error;
      _loading = false;
    });

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error!),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showUserDetails(Map<String, dynamic> user, int rank, bool isRating) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(user['full_name'] ?? user['user_name'] ?? 'User Profile'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Role: ${user['role']?.toString().toUpperCase() ?? 'N/A'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Rank: #$rank'),
                const Divider(),
                Text('Average Rating: ${user['avg_rating'] ?? 'N/A'} (${user['rating_count'] ?? 0} reviews)'),
                Text('Feedback Score: ${user['avg_score'] ?? 'N/A'} (${user['feedback_count'] ?? 0} entries)'),
                const SizedBox(height: 8),
                Text('Completed Projects: ${user['completed_projects'] ?? 0}'),
                Text('Completed Tasks: ${user['completed_tasks'] ?? 0}'),
                Text('Activity Score: ${user['activity_score'] ?? 0} / 100'),
                const Divider(),
                Text('Skills: ${user['skills'] ?? 'N/A'}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
        color: AppColors.cardBg,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          iconSize: 20,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ratings & Feedback Leaderboard',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Star Ratings'),
            Tab(text: 'Feedback Scores'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: AppColors.error.withValues(alpha: 0.1),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ),
          
          // Filters & Search Section
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search name, username, skill...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    filled: true,
                    fillColor: AppColors.cardBg,
                  ),
                  onChanged: (val) {
                    _searchQuery = val.trim();
                    _load();
                  },
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildDropdown(
                        value: _categoryFilter,
                        items: const ['Overall', 'Freelancers', 'Students', 'Team Leaders', 'Top Rated', 'Most Active'],
                        onChanged: (v) { setState(() => _categoryFilter = v!); _load(); },
                      ),
                      const SizedBox(width: 8),
                      _buildDropdown(
                        value: _timeFilter,
                        items: const ['All Time', 'This Year', 'This Month', 'This Week'],
                        onChanged: (v) { setState(() => _timeFilter = v!); _load(); },
                      ),
                      const SizedBox(width: 8),
                      _buildDropdown(
                        value: _sortBy,
                        items: const ['Rank', 'Rating', 'Completed projects', 'Activity'],
                        onChanged: (v) { setState(() => _sortBy = v!); _load(); },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Lists Section
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _buildList(_ratings, isRating: true),
                      _buildList(_feedback, isRating: false),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<dynamic> items, {required bool isRating}) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error != null
                ? 'Could not load leaderboard data.\nTap refresh after restarting the backend.'
                : 'No data found for the current filters.\nAdjust filters or try a different search.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final row = items[i] as Map<String, dynamic>;
          final rank = i + 1;
          final name = row['full_name'] ?? row['user_name'] ?? 'User';
          final score = isRating ? (row['avg_rating'] ?? 0.0) : (row['avg_score'] ?? 0.0);
          final count = isRating ? (row['rating_count'] ?? 0) : (row['feedback_count'] ?? 0);
          final role = row['role'] ?? 'user';
          
          return TCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              onTap: () => _showUserDetails(row, rank, isRating),
              leading: CircleAvatar(
                backgroundColor: rank <= 3
                    ? AppColors.warning.withValues(alpha: 0.2)
                    : AppColors.border,
                child: Text('#$rank',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${isRating ? 'Ratings' : 'Feedback entries'}: $count • ${role.toString().toUpperCase()}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isRating ? Icons.star : Icons.thumb_up,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: 4),
                  Text('$score',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
