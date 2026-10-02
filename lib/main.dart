import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  runApp(const KbbiApp());
}

class KbbiApp extends StatelessWidget {
  const KbbiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KBBI Ku',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const SearchPage(),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final DbService _db = DbService();
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  bool _ready = false;
  List<Map<String, Object?>> _words = [];
  List<Map<String, Object?>> _compounds = [];

  String _pos = '';
  static const double _maxLen = 30;
  RangeValues _lenRange = const RangeValues(1, _maxLen);

  static const Map<String, String> _posNames = {
    '': 'Semua kelas kata',
    'n': 'Nomina (kata benda)',
    'v': 'Verba (kata kerja)',
    'adj': 'Adjektiva (kata sifat)',
    'adv': 'Adverbia',
    'pron': 'Pronomina',
    'num': 'Numeralia',
    'p': 'Preposisi',
    'conj': 'Konjungsi',
    'i': 'Interjeksi',
    'prt': 'Partikel',
    'uk': 'Ungkapan',
    'cak': 'Cakapan',
    'ark': 'Arkais',
  };

  @override
  void initState() {
    super.initState();
    _db.init().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _search);
  }

  Future<void> _search() async {
    if (!_ready) return;
    final q = _controller.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _words = [];
        _compounds = [];
      });
      return;
    }
    final minLen = _lenRange.start.round();
    final maxLen = _lenRange.end.round();
    final words = await _db.suggestWords(
      q,
      pos: _pos.isEmpty ? null : _pos,
      minLen: minLen > 1 ? minLen : null,
      maxLen: maxLen < _maxLen ? maxLen : null,
    );
    final compounds = await _db.suggestCompounds(
      q,
      pos: _pos.isEmpty ? null : _pos,
      minLen: minLen > 1 ? minLen : null,
      maxLen: maxLen < _maxLen ? maxLen : null,
    );
    if (!mounted) return;
    setState(() {
      _words = words;
      _compounds = compounds;
    });
  }

  Future<void> _openDetail(String norm) async {
    final rows = await _db.lookup(norm);
    if (!mounted || rows.isEmpty) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DetailSheet(rows: rows),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('KBBI Ku'), centerTitle: true),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: TextField(
                    controller: _controller,
                    onChanged: _onChanged,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Ketik kata... (mis. "meja")',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      suffixIcon: ValueListenableBuilder(
                        valueListenable: _controller,
                        builder: (_, value, _) => value.text.isEmpty
                            ? const SizedBox.shrink()
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _controller.clear();
                                  _onChanged('');
                                },
                              ),
                      ),
                    ),
                  ),
                ),
                _buildFilters(),
                Expanded(child: _buildResults()),
              ],
            ),
    );
  }

  Widget _buildFilters() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: const Text('Filter'),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: _pos,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: _posNames.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) {
                setState(() => _pos = v ?? '');
                _search();
              },
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Jumlah huruf: ${_lenRange.start.round()} - ${_lenRange.end.round()}',
          ),
          RangeSlider(
            values: _lenRange,
            min: 1,
            max: _maxLen.toDouble(),
            divisions: _maxLen.toInt() - 1,
            labels: RangeLabels(
              '${_lenRange.start.round()}',
              '${_lenRange.end.round()}',
            ),
            onChanged: (v) => setState(() => _lenRange = v),
            onChangeEnd: (_) => _search(),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_controller.text.trim().isEmpty) {
      return const Center(
        child: Text(
          'Ketik untuk mulai mencari.\nCoba ketik "meja"',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (_compounds.isNotEmpty) ..._section('Frasa - kata majemuk'),
        for (final c in _compounds) _compoundTile(c),
        if (_words.isNotEmpty) ..._section('Kata'),
        for (final w in _words) _wordTile(w),
        if (_words.isEmpty && _compounds.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Tidak ada hasil yang cocok.')),
          ),
      ],
    );
  }

  List<Widget> _section(String title) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
      ];

  Widget _wordTile(Map<String, Object?> row) {
    return ListTile(
      title: Text('${row['word']}'),
      subtitle: Text(
        '${row['definition'] ?? ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _posBadge(row['pos'] as String?),
      onTap: () => _openDetail('${row['word']}'.toLowerCase()),
    );
  }

  Widget _compoundTile(Map<String, Object?> row) {
    return ListTile(
      leading: const Icon(Icons.extension),
      title: Text.rich(
        TextSpan(
          text: '${row['first_token']}',
          children: [
            TextSpan(
              text: ' + ${row['tail']}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      trailing: _posBadge(row['pos'] as String?),
      onTap: () => _openDetail('${row['phrase']}'.toLowerCase()),
    );
  }

  Widget _posBadge(String? pos) {
    if (pos == null || pos.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Text(pos, style: const TextStyle(fontSize: 12)),
    );
  }
}

class DetailSheet extends StatelessWidget {
  const DetailSheet({super.key, required this.rows});

  final List<Map<String, Object?>> rows;

  @override
  Widget build(BuildContext context) {
    final first = rows.first;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text(
            '${first['word']}',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              if ((first['pos'] as String?)?.isNotEmpty ?? false)
                Chip(
                  label: Text('${first['pos']}'),
                  visualDensity: VisualDensity.compact,
                ),
              Chip(
                label: Text('${first['len']} huruf'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final r in rows) ...[
            Text('${r['definition'] ?? '(tidak ada definisi)'}'),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
