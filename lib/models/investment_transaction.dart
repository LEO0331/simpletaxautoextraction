import 'package:cloud_firestore/cloud_firestore.dart';

enum InvestmentTransactionType { buy, sell }

extension InvestmentTransactionTypeX on InvestmentTransactionType {
  String get value => this == InvestmentTransactionType.buy ? 'BUY' : 'SELL';

  static InvestmentTransactionType fromString(String raw) {
    return raw.toUpperCase() == 'SELL'
        ? InvestmentTransactionType.sell
        : InvestmentTransactionType.buy;
  }
}

class InvestmentTransaction {
  final String? id;
  final String userId;
  final String ticker;
  final String securityName;
  final InvestmentTransactionType transactionType;
  final DateTime tradeDate;
  final DateTime? settlementDate;
  final double units;
  final double averagePrice;
  final double consideration;
  final double brokerage;
  final double? gst;
  final double totalCost;
  final String? confirmationNumber;
  final String? accountNumber;
  final String? sourceFileName;
  final String sourceParser;
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

  bool get isBuy => transactionType == InvestmentTransactionType.buy;
  bool get isSell => transactionType == InvestmentTransactionType.sell;

  factory InvestmentTransaction.fromMap(Map<String, dynamic> data, String id) {
    return InvestmentTransaction(
      id: id,
      userId: data['userId'] ?? '',
      ticker: data['ticker'] ?? '',
      securityName: data['securityName'] ?? '',
      transactionType: InvestmentTransactionTypeX.fromString(
        data['transactionType'] ?? 'BUY',
      ),
      tradeDate: (data['tradeDate'] as Timestamp).toDate(),
      settlementDate: (data['settlementDate'] as Timestamp?)?.toDate(),
      units: (data['units'] as num?)?.toDouble() ?? 0,
      averagePrice: (data['averagePrice'] as num?)?.toDouble() ?? 0,
      consideration: (data['consideration'] as num?)?.toDouble() ?? 0,
      brokerage: (data['brokerage'] as num?)?.toDouble() ?? 0,
      gst: (data['gst'] as num?)?.toDouble(),
      totalCost: (data['totalCost'] as num?)?.toDouble() ?? 0,
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
      'userId': userId,
      'ticker': ticker,
      'securityName': securityName,
      'transactionType': transactionType.value,
      'tradeDate': Timestamp.fromDate(tradeDate),
      'settlementDate': settlementDate == null
          ? null
          : Timestamp.fromDate(settlementDate!),
      'units': units,
      'averagePrice': averagePrice,
      'consideration': consideration,
      'brokerage': brokerage,
      'gst': gst,
      'totalCost': totalCost,
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
