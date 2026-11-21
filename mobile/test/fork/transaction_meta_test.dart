import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/fork/category_avatar.dart';
import 'package:sure_mobile/fork/transaction_meta_store.dart';

void main() {
  group('TransactionMeta', () {
    test('reads the API fields', () {
      final meta = TransactionMeta.fromApiJson({
        'kind': 'standard',
        'excluded': false,
        'split_parent': false,
        'pending': true,
      });

      expect(meta.kind, 'standard');
      expect(meta.pending, isTrue);
      expect(meta.countsTowardsTotals, isTrue);
    });

    test('leaves transfers, card payments, exclusions and split parents out of totals', () {
      expect(const TransactionMeta(kind: 'funds_movement').countsTowardsTotals, isFalse);
      expect(const TransactionMeta(kind: 'cc_payment').countsTowardsTotals, isFalse);
      expect(const TransactionMeta(excluded: true).countsTowardsTotals, isFalse);
      expect(const TransactionMeta(splitParent: true).countsTowardsTotals, isFalse);
    });

    test('counts one-off and loan payments as spending', () {
      expect(const TransactionMeta(kind: 'one_time').countsTowardsTotals, isTrue);
      expect(const TransactionMeta(kind: 'loan_payment').countsTowardsTotals, isTrue);
    });

    test('survives a round trip through storage', () {
      const meta = TransactionMeta(kind: 'cc_payment', excluded: true, pending: true);
      expect(TransactionMeta.fromStored(meta.toStored()), meta);
    });

    test('unknown transactions count, so totals work before the first sync', () {
      expect(TransactionMetaStore.instance.get('never-seen').countsTowardsTotals, isTrue);
    });
  });

  group('parseHexColor', () {
    test('parses Sure category colours', () {
      expect(parseHexColor('#e99537'), const Color(0xFFE99537));
    });

    test('rejects anything else', () {
      expect(parseHexColor(null), isNull);
      expect(parseHexColor('#fff'), isNull);
      expect(parseHexColor('#zzzzzz'), isNull);
    });
  });
}
