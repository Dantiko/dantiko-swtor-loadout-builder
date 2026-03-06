import 'dart:async';
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  static const _dbName = 'dantiko_lb.db';
  static const _dbVersion = 2;

  static Database? _database;

  static Future<Database> get instance async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    // Desktop support
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Characters
    await db.execute('''
      CREATE TABLE characters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        combat_style TEXT,
        discipline TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    // Loadouts
    await db.execute('''
      CREATE TABLE loadouts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        character_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        combat_style TEXT,
        discipline TEXT,
        role TEXT,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(character_id) REFERENCES characters(id) ON DELETE CASCADE
      );
    ''');

    await db.execute(
        'CREATE INDEX idx_loadouts_character_id ON loadouts(character_id);');
    await db.execute(
        'CREATE INDEX idx_loadouts_discipline ON loadouts(discipline);');
    await db.execute(
        'CREATE INDEX idx_loadouts_role ON loadouts(role);');

    // Loadout Slots
    await db.execute('''
      CREATE TABLE loadout_slots (
        loadout_id INTEGER NOT NULL,
        slot TEXT NOT NULL,
        rating INTEGER NOT NULL,
        focus TEXT NOT NULL,
        augment_key TEXT NOT NULL,
        preferred_profile TEXT NOT NULL,
        crystal_key TEXT,
        PRIMARY KEY(loadout_id, slot),
        FOREIGN KEY(loadout_id) REFERENCES loadouts(id) ON DELETE CASCADE
      );
    ''');

    await db.execute(
        'CREATE INDEX idx_loadout_slots_loadout_id ON loadout_slots(loadout_id);');

    // Optional: global stim storage
    await db.execute('''
      CREATE TABLE loadout_globals (
        loadout_id INTEGER PRIMARY KEY,
        stim_key TEXT NOT NULL,
        crystal_main_key TEXT NOT NULL,
        crystal_off_key TEXT NOT NULL,
        FOREIGN KEY(loadout_id) REFERENCES loadouts(id) ON DELETE CASCADE
      );
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Recreate loadout_globals with crystals (simple migration)
      await db.execute('DROP TABLE IF EXISTS loadout_globals;');
      await db.execute('''
        CREATE TABLE loadout_globals (
          loadout_id INTEGER PRIMARY KEY,
          stim_key TEXT NOT NULL,
          crystal_main_key TEXT NOT NULL,
          crystal_off_key TEXT NOT NULL,
          FOREIGN KEY(loadout_id) REFERENCES loadouts(id) ON DELETE CASCADE
        );
      ''');
    }
  }
}