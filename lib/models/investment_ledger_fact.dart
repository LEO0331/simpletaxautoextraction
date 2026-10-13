/// Read-only calculation boundary. Implementations may handle persistence, but
/// the ledger itself depends only on dates, exact facts and source references.
abstract interface class InvestmentLedgerFact {
  String? get id;
  String get userId;
  String get ticker;
  String? get accountNumber;
  String? get sourceHash;
  String? get confirmationNumber;
  String? get sourceFileName;
  String get sourceParser;
  String get parserVersion;
  String get direction;
  DateTime get tradeDate;
  bool get isBuy;
  bool get isSell;
  bool get isReviewed;
  bool get isVoided;
  int get revision;
  double get units;
  double get consideration;
  double get brokerage;
  double get totalCost;
  String? get unitsExact;
  String? get considerationExact;
  String? get brokerageExact;
  String? get totalCostExact;
}
