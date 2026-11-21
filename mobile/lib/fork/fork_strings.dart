// English only; kept out of upstream's app_en.arb, which changes with every upstream feature
abstract final class ForkStrings {
  static const transactionsTab = 'Transactions';
  static const searchTransactions = 'Search transactions';
  static const searchCategories = 'Search categories';
  static const pending = 'Pending';
  static const pendingOnly = 'Pending only';
  static const uncategorized = 'Uncategorized';
  static const noTransactionsThisMonth = 'No transactions this month';
  static const noMatchingTransactions = 'No matching transactions';
  static const signInAgain = 'Session expired, sign in again';
  static const categoryChangeFailed = 'Could not change the category';
  static const assistantSubtitle = 'Ask questions about your finances';

  static String transactionCount(int count) =>
      count == 1 ? '1 transaction' : '$count transactions';
}
