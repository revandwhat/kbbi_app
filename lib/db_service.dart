import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DbService {
  Database? _db;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'kbbi.db'));

    // First launch: copy the bundled database to real storage.
    if (!await file.exists()) {
      final data = await rootBundle.load('assets/kbbi.db');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }

    _db = await databaseFactory.openDatabase(file.path);
  }

  /// Normal autocomplete: "mej" -> meja, meja makan, ...
  Future<List<Map<String, Object?>>> suggestWords(
    String q, {
    String? pos,
    int? minLen,
    int? maxLen,
  }) async {
    final args = <Object?>['$q%'];
    var where = 'norm LIKE ?';
    if (pos != null) {
      where += ' AND pos LIKE ?';
      args.add('%$pos%');
    }
    if (minLen != null) {
      where += ' AND len >= ?';
      args.add(minLen);
    }
    if (maxLen != null) {
      where += ' AND len <= ?';
      args.add(maxLen);
    }
    args.add(q);

    return _db!.rawQuery(
      'SELECT word, pos, definition FROM entries '
      'WHERE $where '
      'ORDER BY (norm = ?) DESC, norm '
      'LIMIT 12',
      args,
    );
  }

  /// Compound suggestions: "meja" -> meja + tulis, meja + hijau, ...
  Future<List<Map<String, Object?>>> suggestCompounds(
    String q, {
    String? pos,
    int? minLen,
    int? maxLen,
  }) async {
    final args = <Object?>['$q%'];
    var where = 'first_token LIKE ?';
    if (pos != null) {
      where += ' AND pos LIKE ?';
      args.add('%$pos%');
    }
    if (minLen != null) {
      where += ' AND len >= ?';
      args.add(minLen);
    }
    if (maxLen != null) {
      where += ' AND len <= ?';
      args.add(maxLen);
    }

    return _db!.rawQuery(
      'SELECT first_token, tail, phrase, pos FROM compounds '
      'WHERE $where ORDER BY phrase LIMIT 8',
      args,
    );
  }

  Future<List<Map<String, Object?>>> lookup(String norm) async {
    return _db!.rawQuery(
      'SELECT word, pos, definition, len FROM entries WHERE norm = ?',
      [norm],
    );
  }
}
