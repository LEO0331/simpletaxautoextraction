import 'package:cloud_firestore/cloud_firestore.dart';
import 'investment_ledger_fact.dart';

enum InvestmentTransactionType { buy, sell }

extension InvestmentTransactionTypeX on InvestmentTransactionType {
  String get value => this == InvestmentTransactionType.buy ? 'BUY' : 'SELL';

  static InvestmentTransactionType fromString(String raw) {
    return raw.toUpperCase() == 'SELL'
        ? InvestmentTransactionType.sell
        : InvestmentTransactionType.buy;
  }
}

class InvestmentTransaction implements InvestmentLedgerFact {
  static String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  static DateTime? _dateOnly(dynamic value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final parts = value.split('-').map(int.parse).toList();
    final date = DateTime.utc(parts[0], parts[1], parts[2]);
    return _day(date) == value ? date : null;
  }

  static bool _reviewedTradeDate(Map<String, dynamic> data) {
    final day = _dateOnly(data['tradeDateIso']);
    final timestamp = data['tradeDate'];
    return day != null &&
        timestamp is Timestamp &&
        timestamp.toDate().toUtc() == day;
  }

  @override
  final String? id;
  @override
  final String userId;
  @override
  final String ticker;
  final String securityName;
  final InvestmentTransactionType transactionType;
  @override
  final DateTime tradeDate;
  final DateTime? settlementDate;
  @override
  final double units;
  final double averagePrice;
  @override
  final double consideration;
  @override
  final double brokerage;
  final double? gst;
  @override
  final double totalCost;
  @override
  final String? unitsExact;
  @override
  final String? considerationExact;
  @override
  final String? brokerageExact;
  @override
  final String? totalCostExact;
  @override
  final String? sourceHash;
  @override
  final bool isReviewed;
  @override
  final bool isVoided;
  @override
  final int revision;
  @override
  final String? confirmationNumber;
  @override
  final String? accountNumber;
  @override
  final String? sourceFileName;
  @override
  final String sourceParser;
  @override
  final String parserVersion;
  final String notes;
  final bool isLocked;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const InvestmentTransaction({
    this.id,
    required this.userId,
    required this.ticker,
    required this.securityName,
    required this.transactionType,
    required this.tradeDate,
    this.settlementDate,
    required this.units,
    required this.averagePrice,
    required this.consideration,
    required this.brokerage,
    this.gst,
    required this.totalCost,
    this.unitsExact,
    this.considerationExact,
    this.brokerageExact,
    this.totalCostExact,
    this.sourceHash,
    this.isReviewed = false,
    this.isVoided = false,
    this.revision = 0,
    this.confirmationNumber,
    this.accountNumber,
    this.sourceFileName,
    required this.sourceParser,
    required this.parserVersion,
    this.notes = '',
    this.isLocked = false,
    this.createdAt,
    this.updatedAt,
  });

  @override
  bool get isBuy => transactionType == InvestmentTransactionType.buy;
  @override
  bool get isSell => transactionType == InvestmentTransactionType.sell;
  @override
  String get direction => transactionType.value;

  factory InvestmentTransaction.fromMap(Map<String, dynamic> data, String id) {
    return InvestmentTransaction(
      id: id,
      userId: data['userId'] ?? '',
      ticker: data['ticker'] ?? '',
      securityName: data['securityName'] ?? '',
      transactionType: InvestmentTransactionTypeX.fromString(
        data['transactionType'] ?? 'BUY',
      ),
      tradeDate:
          _dateOnly(data['tradeDateIso']) ??
          (data['tradeDate'] as Timestamp).toDate(),
      settlementDate:
          _dateOnly(data['settlementDateIso']) ??
          (data['settlementDate'] as Timestamp?)?.toDate(),
      units: (data['units'] as num?)?.toDouble() ?? 0,
      averagePrice: (data['averagePrice'] as num?)?.toDouble() ?? 0,
      consideration: (data['consideration'] as num?)?.toDouble() ?? 0,
      brokerage: (data['brokerage'] as num?)?.toDouble() ?? 0,
      gst: (data['gst'] as num?)?.toDouble(),
      totalCost: (data['totalCost'] as num?)?.toDouble() ?? 0,
      unitsExact: data['unitsExact'] as String?,
      considerationExact: data['considerationExact'] as String?,
      brokerageExact: data['brokerageExact'] as String?,
      totalCostExact: data['totalCostExact'] as String?,
      sourceHash: data['sourceHash'] as String?,
      isReviewed:
          data['isReviewed'] == true &&
          data['schemaVersion'] == 2 &&
          _reviewedTradeDate(data) &&
          const ['BUY', 'SELL'].contains(data['transactionType']) &&
          [
            'unitsExact',
            'considerationExact',
            'brokerageExact',
            'totalCostExact',
          ].every(
            (key) => data[key] is String && (data[key] as String).isNotEmpty,
          ),
      isVoided: data['isVoided'] == true,
      revision: (data['revision'] as num?)?.toInt() ?? 0,
      confirmationNumber: data['confirmationNumber'],
      accountNumber: data['accountNumber'],
      sourceFileName: data['sourceFileName'],
      sourceParser: data['sourceParser'] ?? '',
      parserVersion: data['parserVersion'] ?? 'v1',
      notes: data['notes'] ?? '',
      isLocked: data['isLocked'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'schemaVersion': 2,
      'userId': userId,
      'ticker': ticker,
      'securityName': securityName,
      'transactionType': transactionType.value,
      'tradeDateIso': _day(tradeDate),
      'settlementDateIso': settlementDate == null
          ? null
          : _day(settlementDate!),
      'tradeDate': Timestamp.fromDate(
        DateTime.utc(tradeDate.year, tradeDate.month, tradeDate.day),
      ),
      'settlementDate': settlementDate == null
          ? null
          : Timestamp.fromDate(
              DateTime.utc(
                settlementDate!.year,
                settlementDate!.month,
                settlementDate!.day,
              ),
            ),
      'units': units,
      'averagePrice': averagePrice,
      'consideration': consideration,
      'brokerage': brokerage,
      'gst': gst,
      'totalCost': totalCost,
      'unitsExact': unitsExact,
      'considerationExact': considerationExact,
      'brokerageExact': brokerageExact,
      'totalCostExact': totalCostExact,
      'sourceHash': sourceHash,
      'isReviewed': isReviewed,
      'isVoided': isVoided,
      'revision': revision,
      'confirmationNumber': confirmationNumber,
      'accountNumber': accountNumber,
      'sourceFileName': sourceFileName,
      'sourceParser': sourceParser,
      'parserVersion': parserVersion,
      'notes': notes,
      'isLocked': isLocked,
    };
  }

  InvestmentTransaction copyWith({
    String? id,
    String? userId,
    String? ticker,
    String? securityName,
    InvestmentTransactionType? transactionType,
    DateTime? tradeDate,
    DateTime? settlementDate,
    double? units,
    double? averagePrice,
    double? consideration,
    double? brokerage,
    double? gst,
    double? totalCost,
    String? unitsExact,
    String? considerationExact,
    String? brokerageExact,
    String? totalCostExact,
    String? sourceHash,
    bool? isReviewed,
    bool? isVoided,
    int? revision,
    String? confirmationNumber,
    String? accountNumber,
    String? sourceFileName,
    String? sourceParser,
    String? parserVersion,
    String? notes,
    bool? isLocked,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InvestmentTransaction(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      ticker: ticker ?? this.ticker,
      securityName: securityName ?? this.securityName,
      transactionType: transactionType ?? this.transactionType,
      tradeDate: tradeDate ?? this.tradeDate,
      settlementDate: settlementDate ?? this.settlementDate,
      units: units ?? this.units,
      averagePrice: averagePrice ?? this.averagePrice,
      consideration: consideration ?? this.consideration,
      brokerage: brokerage ?? this.brokerage,
      gst: gst ?? this.gst,
      totalCost: totalCost ?? this.totalCost,
      unitsExact: unitsExact ?? this.unitsExact,
      considerationExact: considerationExact ?? this.considerationExact,
      brokerageExact: brokerageExact ?? this.brokerageExact,
      totalCostExact: totalCostExact ?? this.totalCostExact,
      sourceHash: sourceHash ?? this.sourceHash,
      isReviewed: isReviewed ?? this.isReviewed,
      isVoided: isVoided ?? this.isVoided,
      revision: revision ?? this.revision,
      confirmationNumber: confirmationNumber ?? this.confirmationNumber,
      accountNumber: accountNumber ?? this.accountNumber,
      sourceFileName: sourceFileName ?? this.sourceFileName,
      sourceParser: sourceParser ?? this.sourceParser,
      parserVersion: parserVersion ?? this.parserVersion,
      notes: notes ?? this.notes,
      isLocked: isLocked ?? this.isLocked,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
