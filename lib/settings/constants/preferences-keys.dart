class PreferencesKeys {




  // Custom folder holding movements.db. Empty string means the platform
  // default location is used. Device-local, so it is excluded from portable
  // backup/restore. Only honored on desktop, where SQLite can open real
  // filesystem paths.
  static const databaseFolderPath = 'databaseFolderPath';

  // Homepage





  static const categoryListSortOption = 'defaultCategoryListSortOption';

  // Wallets
  static const walletListSortOption = 'defaultWalletListSortOption';



  // Wallet filter defaults (stored as StringList of wallet IDs; empty = all
  // accounts). The sync clears them by prefix.
  static const homePageWalletFilter = 'homePageWalletFilter_1';

  // The Extrato also lists records hidden with the "Oculto" tag.
  static const extratoShowHidden = 'extratoShowHidden';

  // The user's companies and which bank accounts are theirs (JSON,
  // portable), and the accounts this device leaves out of the Extrato.
  static const companies = 'empresas';
  static const hiddenAccounts = 'contasOcultas';
  static const walletsTabWalletFilter = 'walletsTabWalletFilter_1';

  // Currency




  // Dinzo integration
  static const dinzoApiKey = 'dinzoApiKey'; // never exported to backups
  static const brapiApiKey = 'brapiApiKey'; // never exported to backups
  static const dinzoConfig = 'dinzoConfig';
  static const dinzoLastSync = 'dinzoLastSync';
  static const dailyBanks = 'dailyBanks';
  static const welcomeSeen = 'welcomeSeen';
  static const cryptoQuotesMain = 'cryptoQuotesMain';
  static const cryptoQuotesUpdatedAt = 'cryptoQuotesUpdatedAt';
  static const cryptoQuotesUsd = 'cryptoQuotesUsd';
  static const assetNotes = 'assetNotes';
  static const portfolioDiagram = 'portfolioDiagram';
  static const assetLots = 'assetLots';
  static const allowManualRecords = 'allowManualRecords';
  // Income split (Settings → Orçamento, BudgetPlan), portable.
  static const budgetPlan = 'budgetPlan';
  // Calculator disguise on start (lib/disguise/), off by default, portable.
  static const disguiseEnabled = 'disguiseEnabled';
  // Spending wallets (Extrato's "Total" column, TotalWallets), by name, portable.
  static const totalWallets = 'totalWallets';
  // Paper money wallet, where manual records go (CashWallet), by name, portable.
  static const cashWallet = 'cashWallet';
  // Dinzo request budget (DinzoRateLimiter), device-only.
  static const dinzoRequestLog = 'dinzoRequestLog';
  static const dinzoBlockedUntil = 'dinzoQuotaBlockedUntil';
  static const dinzoRequestDaily = 'dinzoRequestDaily'; // minute -> count, 24 h
  static const dinzoServerRemaining = 'dinzoServerRemaining'; // last RateLimit r=

  // Disguise calculator tape (lib/disguise), device-only.
  static const calcTape = 'calcTape';
}
