import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/category.dart' as models;
import '../models/offline_transaction.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/privacy_provider.dart';
import '../providers/transactions_provider.dart';
import '../screens/transaction_edit_screen.dart';
import '../services/offline_storage_service.dart';
import '../theme/sure_tokens.dart';
import '../utils/amount_parser.dart';
import '../utils/money_masker.dart';
import '../widgets/money_text.dart';
import '../widgets/sync_status_badge.dart';
import 'category_avatar.dart';
import 'category_picker_sheet.dart';
import 'fork_strings.dart';
import 'transaction_meta_store.dart';

/// One tab per month, like Cashew's transactions page, reading the whole offline
/// cache so it works without a connection.
class TransactionsTabScreen extends StatefulWidget {
  const TransactionsTabScreen({super.key});

  @override
  State<TransactionsTabScreen> createState() => _TransactionsTabScreenState();
}

class _TransactionsTabScreenState extends State<TransactionsTabScreen> {
  final _storage = OfflineStorageService();
  final _metaStore = TransactionMetaStore.instance;
  late final TransactionsProvider _transactionsProvider;

  List<OfflineTransaction> _transactions = [];
  bool _isSearching = false;
  String _query = '';
  bool _pendingOnly = false;

  @override
  void initState() {
    super.initState();
    _transactionsProvider = context.read<TransactionsProvider>();
    // The provider's own list is scoped to whichever account screen loaded last,
    // so this screen only uses it as a signal that the cache changed.
    _transactionsProvider.addListener(_onCacheMayHaveChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialLoad());
  }

  @override
  void dispose() {
    _transactionsProvider.removeListener(_onCacheMayHaveChanged);
    super.dispose();
  }

  Future<void> _initialLoad() async {
    await _metaStore.load();
    await _reloadFromCache();
    await _loadCategories();
    if (_transactions.isEmpty) {
      await _syncFromServer();
    }
  }

  void _onCacheMayHaveChanged() {
    if (_transactionsProvider.isLoading) return;
    _reloadFromCache();
  }

  Future<void> _reloadFromCache() async {
    final cached = await _storage.getTransactions();
    if (!mounted) return;
    setState(() => _transactions = cached);
  }

  Future<String?> _accessToken() async {
    final token = await context.read<AuthProvider>().getValidAccessToken();
    if (token == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(ForkStrings.signInAgain)),
      );
    }
    return token;
  }

  Future<void> _loadCategories() async {
    final categoriesProvider = context.read<CategoriesProvider>();
    final token = await _accessToken();
    if (token == null) return;
    await categoriesProvider.fetchCategories(accessToken: token);
  }

  Future<void> _syncFromServer() async {
    final token = await _accessToken();
    if (token == null) return;
    await _transactionsProvider.fetchTransactions(
      accessToken: token,
      forceSync: true,
    );
    await _reloadFromCache();
  }

  Future<void> _openEditor(OfflineTransaction transaction) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TransactionEditScreen(transaction: transaction),
      ),
    );
    await _reloadFromCache();
  }

  Future<void> _changeCategory(OfflineTransaction transaction) async {
    final categories = context.read<CategoriesProvider>().categories;
    final messenger = ScaffoldMessenger.of(context);

    final picked = await showCategoryPicker(
      context,
      categories: categories,
      selectedCategoryId: transaction.categoryId,
    );
    if (picked == null || picked.id == transaction.categoryId) return;

    final token = await _accessToken();
    if (token == null) return;

    final updated = await _transactionsProvider.updateTransaction(
      accessToken: token,
      transaction: transaction,
      categoryId: picked.id,
    );
    if (!updated) {
      final reason = _transactionsProvider.error;
      messenger.showSnackBar(
        SnackBar(content: Text(reason ?? ForkStrings.categoryChangeFailed)),
      );
    }
    await _reloadFromCache();
  }

  bool get _isFiltering => _query.trim().isNotEmpty || _pendingOnly;

  List<OfflineTransaction> _visibleTransactions(
    Map<String, models.Category> categoriesById,
  ) {
    final needle = _query.trim().toLowerCase();

    bool matches(OfflineTransaction t) {
      final isDeleting = t.syncStatus == SyncStatus.pendingDelete;
      if (isDeleting) return false;
      if (_pendingOnly && !_metaStore.get(t.id).pending) return false;
      if (needle.isEmpty) return true;

      final categoryName =
          categoriesById[t.categoryId]?.displayName ?? t.categoryName ?? '';
      final haystack = [t.name, t.merchantName, t.notes, categoryName]
          .whereType<String>()
          .join(' ')
          .toLowerCase();
      return haystack.contains(needle);
    }

    final visible = _transactions.where(matches).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return visible;
  }

  List<DateTime> _monthRange(List<OfflineTransaction> transactions) {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final months = transactions
        .map((t) => DateTime.tryParse(t.date))
        .whereType<DateTime>()
        .map((d) => DateTime(d.year, d.month))
        .toList();

    var first = currentMonth;
    var last = currentMonth;
    for (final month in months) {
      if (month.isBefore(first)) first = month;
      if (month.isAfter(last)) last = month;
    }

    return [
      for (var m = first; !m.isAfter(last); m = DateTime(m.year, m.month + 1)) m,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<CategoriesProvider>().categories;
    final categoriesById = {for (final c in categories) c.id: c};
    final visible = _visibleTransactions(categoriesById);

    final months = _monthRange(_transactions);
    final now = DateTime.now();
    final currentMonthIndex = months.indexOf(DateTime(now.year, now.month));

    _TransactionList listOf(List<OfflineTransaction> transactions, String emptyText) {
      return _TransactionList(
        transactions: transactions,
        categoriesById: categoriesById,
        emptyText: emptyText,
        onRefresh: _syncFromServer,
        onTap: _openEditor,
        onAvatarTap: _changeCategory,
      );
    }

    final monthTabs = TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.center,
      tabs: [for (final month in months) Tab(text: _monthLabel(month))],
    );
    final monthPages = TabBarView(
      children: [
        for (final month in months)
          listOf(
            visible.where((t) => _isInMonth(t.date, month)).toList(),
            ForkStrings.noTransactionsThisMonth,
          ),
      ],
    );

    // Search results span all months, so the month tabs give way to one list.
    // The tree above the body stays the same so the search field keeps focus.
    return DefaultTabController(
      // Rebuilt only when the month range grows, so a sync keeps the selected tab
      key: ValueKey(months.length),
      length: months.length,
      initialIndex: currentMonthIndex,
      child: Scaffold(
        appBar: _buildAppBar(bottom: _isFiltering ? null : monthTabs),
        body: _isFiltering
            ? listOf(visible, ForkStrings.noMatchingTransactions)
            : monthPages,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar({required PreferredSizeWidget? bottom}) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppBar(
      title: _isSearching
          ? TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: ForkStrings.searchTransactions,
                border: InputBorder.none,
              ),
              onChanged: (value) => setState(() => _query = value),
            )
          : const Text(ForkStrings.transactionsTab),
      actions: [
        IconButton(
          tooltip: ForkStrings.pendingOnly,
          isSelected: _pendingOnly,
          icon: const Icon(Icons.schedule_outlined),
          selectedIcon: Icon(Icons.schedule, color: colorScheme.primary),
          onPressed: () => setState(() => _pendingOnly = !_pendingOnly),
        ),
        IconButton(
          tooltip: ForkStrings.searchTransactions,
          icon: Icon(_isSearching ? Icons.close : Icons.search),
          onPressed: () => setState(() {
            _isSearching = !_isSearching;
            _query = '';
          }),
        ),
      ],
      bottom: bottom,
    );
  }

  String _monthLabel(DateTime month) {
    final locale = Localizations.localeOf(context).toString();
    final isThisYear = month.year == DateTime.now().year;
    final format = isThisYear ? DateFormat.MMMM(locale) : DateFormat.yMMM(locale);
    return format.format(month);
  }

  static bool _isInMonth(String isoDate, DateTime month) {
    final date = DateTime.tryParse(isoDate);
    if (date == null) return false;
    return date.year == month.year && date.month == month.month;
  }
}

class _TransactionList extends StatelessWidget {
  final List<OfflineTransaction> transactions;
  final Map<String, models.Category> categoriesById;
  final String emptyText;
  final Future<void> Function() onRefresh;
  final void Function(OfflineTransaction) onTap;
  final void Function(OfflineTransaction) onAvatarTap;

  const _TransactionList({
    required this.transactions,
    required this.categoriesById,
    required this.emptyText,
    required this.onRefresh,
    required this.onTap,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (transactions.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Center(
              child: Text(
                emptyText,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final days = <String, List<OfflineTransaction>>{};
    for (final transaction in transactions) {
      days.putIfAbsent(transaction.date, () => []).add(transaction);
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _TotalsBar(transactions: transactions),
          for (final MapEntry(key: date, value: dayTransactions) in days.entries) ...[
            _DayHeader(isoDate: date, transactions: dayTransactions),
            for (final transaction in dayTransactions)
              _TransactionRow(
                transaction: transaction,
                category: categoriesById[transaction.categoryId],
                onTap: () => onTap(transaction),
                onAvatarTap: () => onAvatarTap(transaction),
              ),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              ForkStrings.transactionCount(transactions.length),
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Signed amounts in Sure's display convention: inflow positive, outflow negative.
class _Money {
  static double signedAmount(OfflineTransaction transaction) {
    final double magnitude;
    try {
      magnitude = AmountParser.parse(transaction.amount).value.abs();
    } on FormatException {
      return 0;
    }
    return transaction.isIncome ? magnitude : -magnitude;
  }

  static String format(BuildContext context, double amount, String currency) {
    final locale = Localizations.localeOf(context).toString();
    final formatter = NumberFormat.simpleCurrency(locale: locale, name: currency);
    return formatter.format(amount);
  }

  static Map<String, List<double>> countedByCurrency(
    List<OfflineTransaction> transactions,
  ) {
    final byCurrency = <String, List<double>>{};
    final metaStore = TransactionMetaStore.instance;
    for (final transaction in transactions) {
      if (!metaStore.get(transaction.id).countsTowardsTotals) continue;
      byCurrency
          .putIfAbsent(transaction.currency, () => [])
          .add(signedAmount(transaction));
    }
    return byCurrency;
  }
}

class _TotalsBar extends StatelessWidget {
  final List<OfflineTransaction> transactions;

  const _TotalsBar({required this.transactions});

  @override
  Widget build(BuildContext context) {
    final hideAmounts = context.watch<PrivacyProvider>().hidden;
    final colorScheme = Theme.of(context).colorScheme;
    final byCurrency = _Money.countedByCurrency(transactions);
    if (byCurrency.isEmpty) return const SizedBox.shrink();

    String money(double amount, String currency) => MoneyMasker.mask(
          _Money.format(context, amount, currency),
          hidden: hideAmounts,
        );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(SureTokens.radiusMd),
      ),
      child: Column(
        children: [
          for (final MapEntry(key: currency, value: amounts) in byCurrency.entries)
            Builder(builder: (context) {
              final spent = amounts.where((a) => a < 0).fold(0.0, (s, a) => s - a);
              final earned = amounts.where((a) => a > 0).fold(0.0, (s, a) => s + a);
              final net = earned - spent;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  MoneyText('↓ ${money(spent, currency)}', trend: MoneyTrend.outflow),
                  MoneyText('↑ ${money(earned, currency)}', trend: MoneyTrend.inflow),
                  MoneyText(
                    '= ${money(net, currency)}',
                    trend: MoneyTrend.neutral,
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String isoDate;
  final List<OfflineTransaction> transactions;

  const _DayHeader({required this.isoDate, required this.transactions});

  @override
  Widget build(BuildContext context) {
    final hideAmounts = context.watch<PrivacyProvider>().hidden;
    final colorScheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final date = DateTime.tryParse(isoDate);
    final isThisYear = date?.year == DateTime.now().year;
    final dateFormat =
        isThisYear ? DateFormat.MMMMEEEEd(locale) : DateFormat.yMMMMEEEEd(locale);
    final label = date == null ? isoDate : dateFormat.format(date);

    final byCurrency = _Money.countedByCurrency(transactions);
    final hasSingleTotal = byCurrency.length == 1 && transactions.length > 1;
    String? dayTotal;
    if (hasSingleTotal) {
      final MapEntry(key: currency, value: amounts) = byCurrency.entries.first;
      final net = amounts.fold(0.0, (s, a) => s + a);
      dayTotal = MoneyMasker.mask(
        _Money.format(context, net, currency),
        hidden: hideAmounts,
      );
    }

    final style = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: colorScheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          if (dayTotal != null) Text(dayTotal, style: style),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final OfflineTransaction transaction;
  final models.Category? category;
  final VoidCallback onTap;
  final VoidCallback onAvatarTap;

  const _TransactionRow({
    required this.transaction,
    required this.category,
    required this.onTap,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final hideAmounts = context.watch<PrivacyProvider>().hidden;
    final accounts = context.watch<AccountsProvider>().accounts;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final meta = TransactionMetaStore.instance.get(transaction.id);

    final isSynced =
        transaction.syncStatus == SyncStatus.synced && transaction.id != null;
    final accountName = accounts
        .where((a) => a.id == transaction.accountId)
        .map((a) => a.name)
        .firstOrNull;
    final categoryName =
        category?.displayName ?? transaction.categoryName ?? ForkStrings.uncategorized;
    final subtitle = [categoryName, accountName].whereType<String>().join(' · ');

    final signed = _Money.signedAmount(transaction);
    final trend = !meta.countsTowardsTotals
        ? MoneyTrend.neutral
        : SureMoney.trendForAmount(signed);
    final amountText = MoneyMasker.mask(
      _Money.format(context, signed, transaction.currency),
      hidden: hideAmounts,
    );

    return Opacity(
      opacity: meta.excluded ? 0.5 : 1,
      child: InkWell(
        onTap: isSynced ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              InkResponse(
                onTap: isSynced ? onAvatarTap : null,
                radius: 26,
                child: CategoryAvatar(category: category),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: SureTokens.weightMedium,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (meta.pending) const _PendingBadge(),
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!isSynced)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SyncStatusBadge(
                    syncStatus: transaction.syncStatus,
                    compact: true,
                  ),
                ),
              MoneyText(
                amountText,
                trend: trend,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: SureTokens.weightMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingBadge extends StatelessWidget {
  const _PendingBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SureTokens.radiusMd),
        border: Border.all(color: colorScheme.tertiary),
      ),
      child: Text(
        ForkStrings.pending,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.tertiary,
            ),
      ),
    );
  }
}
