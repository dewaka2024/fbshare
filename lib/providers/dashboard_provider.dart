// lib/providers/dashboard_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class PostItem {
  final String id;
  final String name;
  final String link;
  const PostItem({required this.id, required this.name, required this.link});
}

class GroupItem {
  final String id;
  final String name;
  String categoryId;
  bool isSelected;
  GroupItem({required this.id, required this.name, this.categoryId = '', this.isSelected = false});
}

class CategoryItem {
  final String id;
  final String name;
  bool isExpanded;
  CategoryItem({required this.id, required this.name, this.isExpanded = true});
}

enum LogLevel { info, success, warning, error }

class LogEntry {
  final String timestamp;
  final String message;
  final LogLevel level;
  const LogEntry({required this.timestamp, required this.message, this.level = LogLevel.info});
}

// ── DashboardProvider ─────────────────────────────────────────────────────────

class DashboardProvider extends ChangeNotifier {
  // ── Posts ──────────────────────────────────────────────────────────────────
  final List<PostItem> _posts = [];
  PostItem? _selectedPost;

  List<PostItem> get posts => List.unmodifiable(_posts);
  PostItem? get selectedPost => _selectedPost;

  void addPost(String name, String link) {
    if (name.trim().isEmpty || link.trim().isEmpty) return;
    _posts.insert(0, PostItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.trim(),
      link: link.trim(),
    ));
    notifyListeners();
  }

  void removePost(String id) {
    _posts.removeWhere((p) => p.id == id);
    if (_selectedPost?.id == id) _selectedPost = null;
    notifyListeners();
  }

  void selectPost(PostItem post) {
    _selectedPost = _selectedPost?.id == post.id ? null : post;
    notifyListeners();
  }

  // ── Categories & Groups ────────────────────────────────────────────────────
  final List<CategoryItem> _categories = [];
  final List<GroupItem> _groups = [];

  List<CategoryItem> get categories => List.unmodifiable(_categories);

  List<GroupItem> groupsForCategory(String categoryId) =>
      _groups.where((g) => g.categoryId == categoryId).toList();

  int get totalGroupCount => _groups.length;
  int get selectedGroupCount => _groups.where((g) => g.isSelected).length;

  void addCategory(String name) {
    if (name.trim().isEmpty) return;
    _categories.add(CategoryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.trim(),
    ));
    notifyListeners();
  }

  void removeCategory(String id) {
    for (final g in _groups) {
      if (g.categoryId == id) g.categoryId = '';
    }
    _categories.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  void toggleCategoryExpanded(String id) {
    final idx = _categories.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    _categories[idx].isExpanded = !_categories[idx].isExpanded;
    notifyListeners();
  }

  void moveGroupToCategory(String groupId, String categoryId) {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return;
    _groups[idx].categoryId = categoryId;
    notifyListeners();
  }

  void toggleGroupSelection(String groupId) {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return;
    _groups[idx].isSelected = !_groups[idx].isSelected;
    notifyListeners();
  }

  void selectAllGroups(String categoryId) {
    for (final g in _groups) {
      if (g.categoryId == categoryId) g.isSelected = true;
    }
    notifyListeners();
  }

  // ── Sync ────────────────────────────────────────────────────────────────────
  bool _isSyncing = false;
  int _syncCurrent = 0;
  int _syncTotal = 0;

  bool get isSyncing => _isSyncing;
  int get syncCurrent => _syncCurrent;
  int get syncTotal => _syncTotal;

  void beginSyncDemo(int total) {
    if (_isSyncing) return;
    _isSyncing = true;
    _syncCurrent = 0;
    _syncTotal = total;
    notifyListeners();
    _advanceSyncDemo();
  }

  void _advanceSyncDemo() {
    if (!_isSyncing || _syncCurrent >= _syncTotal) {
      _isSyncing = false;
      notifyListeners();
      return;
    }
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!_isSyncing) return;
      _syncCurrent++;
      notifyListeners();
      _advanceSyncDemo();
    });
  }

  void endSync(List<GroupItem> newGroups) {
    _isSyncing = false;
    _groups.clear();
    _groups.addAll(newGroups);
    notifyListeners();
  }

  void loadDemoGroups() {
    const demoNames = [
      'Sales Pros Network', 'Marketing Hub', 'B2B Leads', 'Startup Connect',
      'Digital Entrepreneurs', 'E-Commerce Masters', 'Lead Generation Pro',
      'Business Owners PH', 'Freelancers United', 'Tech Founders',
      'Social Media Growth', 'Affiliate Marketers', 'Drop Shippers Group',
      'Online Sellers PH', 'Virtual Assistants Network',
    ];
    _groups.clear();
    for (int i = 0; i < demoNames.length; i++) {
      _groups.add(GroupItem(id: 'g_$i', name: demoNames[i], categoryId: ''));
    }
    notifyListeners();
  }

  // ── Automation / Log ────────────────────────────────────────────────────────
  bool _isRunning = false;
  int _sharedCount = 0;
  int _targetCount = 0;
  final List<LogEntry> _logEntries = [];
  Timer? _automationTimer;

  bool get isRunning => _isRunning;
  int get sharedCount => _sharedCount;
  int get targetCount => _targetCount;
  List<LogEntry> get logEntries => List.unmodifiable(_logEntries);

  String _nowTs() {
    final n = DateTime.now();
    final h = n.hour.toString().padLeft(2, '0');
    final m = n.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void startAutomation() {
    if (_selectedPost == null) return;
    final selected = _groups.where((g) => g.isSelected).toList();
    if (selected.isEmpty) return;

    _isRunning = true;
    _sharedCount = 0;
    _targetCount = selected.length;
    _logEntries.clear();
    _log('🚀 Automation started — ${selected.length} groups selected', LogLevel.info);
    _log('📌 Post: ${_selectedPost!.name}', LogLevel.info);
    notifyListeners();

    int idx = 0;
    _automationTimer = Timer.periodic(const Duration(seconds: 3), (t) {
      if (idx >= selected.length) {
        t.cancel();
        _isRunning = false;
        _log('✅ Automation complete — $_sharedCount/${selected.length} groups', LogLevel.success);
        notifyListeners();
        return;
      }
      final group = selected[idx];
      _sharedCount++;
      _log('✅ ${group.name}: Shared successfully', LogLevel.success);
      idx++;
      if (idx < selected.length) {
        _log('⏳ Waiting 30s delay before next group…', LogLevel.warning);
      }
      notifyListeners();
    });
  }

  void stopAutomation() {
    _automationTimer?.cancel();
    _automationTimer = null;
    _isRunning = false;
    _log('⏹ Automation stopped by user', LogLevel.warning);
    notifyListeners();
  }

  void _log(String message, LogLevel level) {
    _logEntries.insert(0, LogEntry(timestamp: _nowTs(), message: message, level: level));
    if (_logEntries.length > 200) _logEntries.removeLast();
  }

  void clearLog() {
    _logEntries.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _automationTimer?.cancel();
    super.dispose();
  }
}
