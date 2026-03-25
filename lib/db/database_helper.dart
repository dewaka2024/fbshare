import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // ← was: sqflite

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  // ── DB file: <app support>/db/fb_share_pro.db ─────────────────────────────
  Future<String> get dbPath async {
    final appSupport = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(appSupport.path, 'db'));
    if (!dbDir.existsSync()) dbDir.createSync(recursive: true);
    return p.join(dbDir.path, 'fb_share_pro.db');
  }

  Future<Database> _open() async {
    final path = await dbPath;
    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE groups (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL DEFAULT '',
        image_url   TEXT NOT NULL DEFAULT '',
        url         TEXT NOT NULL DEFAULT '',
        group_id    TEXT NOT NULL DEFAULT '',
        category_id TEXT NOT NULL DEFAULT '',
        idx         INTEGER NOT NULL DEFAULT -1
      )
    ''');

    await db.execute('''
      CREATE TABLE group_categories (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL DEFAULT '',
        is_expanded INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE items (
        id           TEXT PRIMARY KEY,
        original_url TEXT NOT NULL DEFAULT '',
        og_title     TEXT NOT NULL DEFAULT '',
        og_desc      TEXT NOT NULL DEFAULT '',
        og_image     TEXT NOT NULL DEFAULT '',
        created_at   INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE pages (
        url       TEXT PRIMARY KEY,
        name      TEXT NOT NULL DEFAULT '',
        image_url TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  // ── Close (call from AutomationProvider.dispose) ──────────────────────────
  Future<void> close() async {
    final d = _db;
    if (d != null) {
      await d.close();
      _db = null;
    }
  }

  // ── Settings ───────────────────────────────────────────────────────────────
  Future<String> getSetting(String key) async {
    final d = await db;
    final rows = await d.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? '' : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    final d = await db;
    await d.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Groups ─────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getGroups() async {
    final d = await db;
    return d.query('groups', orderBy: 'idx ASC'); // ← was: unordered
  }

  Future<void> saveGroups(List<Map<String, dynamic>> groups) async {
    final d = await db;
    final batch = d.batch();
    batch.delete('groups');
    for (final g in groups) {
      batch.insert('groups', g, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsertGroup(Map<String, dynamic> group) async {
    final d = await db;
    await d.insert('groups', group,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearGroups() async {
    final d = await db;
    await d.delete('groups');
  }

  // ── Group Categories ───────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getCategories() async {
    final d = await db;
    return d.query('group_categories');
  }

  Future<void> saveCategories(List<Map<String, dynamic>> cats) async {
    final d = await db;
    final batch = d.batch();
    batch.delete('group_categories');
    for (final c in cats) {
      batch.insert('group_categories', c,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ── Items (Post Repository) ────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getItems() async {
    final d = await db;
    return d.query('items', orderBy: 'created_at DESC');
  }

  Future<void> saveItems(List<Map<String, dynamic>> items) async {
    final d = await db;
    final batch = d.batch();
    batch.delete('items');
    for (final i in items) {
      batch.insert('items', i, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsertItem(Map<String, dynamic> item) async {
    final d = await db;
    await d.insert('items', item,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteItem(String id) async {
    final d = await db;
    await d.delete('items', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearItems() async {
    final d = await db;
    await d.delete('items');
  }

  // ── Pages ──────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getPages() async {
    final d = await db;
    return d.query('pages');
  }

  Future<void> savePages(List<Map<String, dynamic>> pages) async {
    final d = await db;
    final batch = d.batch();
    batch.delete('pages');
    for (final pg in pages) {
      batch.insert('pages', pg, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}
