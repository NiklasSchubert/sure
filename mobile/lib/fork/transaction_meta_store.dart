import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/log_service.dart';

/// Server fields upstream's offline cache drops. Kept beside the cache instead of
/// in it so the fork does not have to thread new fields through every upstream
/// model constructor and merge path.
class TransactionMeta {
  // Sure's Transaction::BUDGET_EXCLUDED_KINDS minus one_time, which is real spending
  static const _movementKinds = {'funds_movement', 'cc_payment'};

  final String? kind;
  final bool excluded;
  final bool splitParent;
  final bool pending;

  const TransactionMeta({
    this.kind,
    this.excluded = false,
    this.splitParent = false,
    this.pending = false,
  });

  static const unknown = TransactionMeta();

  factory TransactionMeta.fromApiJson(Map<String, dynamic> json) {
    return TransactionMeta(
      kind: json['kind']?.toString(),
      excluded: json['excluded'] == true,
      splitParent: json['split_parent'] == true,
      pending: json['pending'] == true,
    );
  }

  factory TransactionMeta.fromStored(Map<String, dynamic> json) {
    return TransactionMeta(
      kind: json['k'] as String?,
      excluded: json['e'] == true,
      splitParent: json['s'] == true,
      pending: json['p'] == true,
    );
  }

  Map<String, dynamic> toStored() => {
        if (kind != null) 'k': kind,
        if (excluded) 'e': true,
        if (splitParent) 's': true,
        if (pending) 'p': true,
      };

  bool get countsTowardsTotals =>
      !excluded && !splitParent && !_movementKinds.contains(kind);

  @override
  bool operator ==(Object other) =>
      other is TransactionMeta &&
      other.kind == kind &&
      other.excluded == excluded &&
      other.splitParent == splitParent &&
      other.pending == pending;

  @override
  int get hashCode => Object.hash(kind, excluded, splitParent, pending);
}

class TransactionMetaStore {
  static const _prefsKey = 'fork.transaction_meta.v1';

  TransactionMetaStore._();

  static final TransactionMetaStore instance = TransactionMetaStore._();

  final Map<String, TransactionMeta> _byId = {};
  Future<void>? _loading;
  bool _flushScheduled = false;

  TransactionMeta get(String? transactionId) =>
      _byId[transactionId] ?? TransactionMeta.unknown;

  Future<void> load() => _loading ??= _load();

  void record(Map<String, dynamic> apiJson) {
    final id = apiJson['id']?.toString();
    if (id == null || id.isEmpty) return;

    final meta = TransactionMeta.fromApiJson(apiJson);
    if (_byId[id] == meta) return;

    _byId[id] = meta;
    _scheduleFlush();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((id, stored) {
        // Entries recorded from a fresh API response win over the persisted copy
        _byId.putIfAbsent(
          id,
          () => TransactionMeta.fromStored(stored as Map<String, dynamic>),
        );
      });
    } catch (e) {
      LogService.instance.warning(
        'TransactionMetaStore',
        'Could not load transaction metadata: ${e.runtimeType}',
      );
    }
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    // Coalesces the hundreds of records a sync produces into one write
    scheduleMicrotask(() async {
      _flushScheduled = false;
      await _flush();
    });
  }

  Future<void> _flush() async {
    try {
      await load();
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _byId.map((id, meta) => MapEntry(id, meta.toStored())),
      );
      await prefs.setString(_prefsKey, encoded);
    } catch (e) {
      LogService.instance.warning(
        'TransactionMetaStore',
        'Could not persist transaction metadata: ${e.runtimeType}',
      );
    }
  }
}
