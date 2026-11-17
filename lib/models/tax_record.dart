import 'package:cloud_firestore/cloud_firestore.dart';

class TaxRecord {
  final String? id;
  final String userId;
  final String financialYear; // e.g., "2024-2025"
  final Map<String, double> income;
  final Map<String, double> expenses;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String propertyId;
  final String propertyName;
  final String notes;
  final bool isLocked;
  final String? sourceFileName;
  final String? sourceParser;
  final String parserVersion;
  final List<Map<String, dynamic>> lineItems;

  static const List<String> incomeCategoryOptions = [
    'Gross rent',
    'Other rental-related income',
  ];

  static const List<String> expenseCategoryOptions = [
    'Advertising for tenants',
    'Body corporate fees and charges',
    'Borrowing expenses',
    'Cleaning',
    'Council rates',
    'Capital works deductions',
    'Gardening and lawn mowing',
    'Insurance',
    'Interest on loans',
    'Land tax',
    'Legal expenses',
    'Pest control',
    'Property agent fees and commission',
    'Repairs and maintenance',
    'Stationery, telephone and postage',
    'Water charges',
    'Sundry rental expenses',
  ];

  TaxRecord({
    this.id,
    required this.userId,
    required this.financialYear,
    Map<String, double>? income,
    Map<String, double>? expenses,
    this.createdAt,
    this.updatedAt,
    this.propertyId = 'default',
    this.propertyName = 'Primary Property',
    this.notes = '',
    this.isLocked = false,
    this.sourceFileName,
    this.sourceParser,
    this.parserVersion = 'v1',
    List<Map<String, dynamic>>? lineItems,
  }) : income = income ?? {},
       expenses = expenses ?? {},
       lineItems = lineItems ?? [];

  double get totalIncome =>
      income.values.fold(0.0, (runningTotal, amount) => runningTotal + amount);

  double get totalExpenses => expenses.values.fold(
    0.0,
    (runningTotal, amount) => runningTotal + amount,
  );

  double get netPosition => totalIncome - totalExpenses;

  factory TaxRecord.fromMap(Map<String, dynamic> data, String documentId) {
    T? read<T>(String field) {
      final value = data[field];
      if (value == null) return null;
      if (value is T) return value;
      throw FormatException('Rental record $documentId has an invalid $field.');
    }

    Map<String, double> readAmounts(String field) {
      final amounts = read<Map<String, dynamic>>(field) ?? const {};
      final normalized = <String, double>{};
      for (final entry in amounts.entries) {
        final amount = entry.value;
        if (amount is! num || !amount.isFinite) {
          throw FormatException(
            'Rental record $documentId has an invalid amount in $field.',
          );
        }
        normalized[entry.key] = amount.toDouble();
      }
      return normalized;
    }

    final rawLineItems = read<List<dynamic>>('lineItems') ?? const [];
    return TaxRecord(
      id: documentId,
      userId: read<String>('userId') ?? '',
      financialYear: read<String>('financialYear') ?? '',
      income: readAmounts('income'),
      expenses: readAmounts('expenses'),
      createdAt: read<Timestamp>('createdAt')?.toDate(),
      updatedAt: read<Timestamp>('updatedAt')?.toDate(),
      propertyId: read<String>('propertyId') ?? 'default',
      propertyName: read<String>('propertyName') ?? 'Primary Property',
      notes: read<String>('notes') ?? '',
      isLocked: read<bool>('isLocked') ?? false,
      sourceFileName: read<String>('sourceFileName'),
      sourceParser: read<String>('sourceParser'),
      parserVersion: read<String>('parserVersion') ?? 'v1',
      lineItems: rawLineItems
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    final map = {
      'userId': userId,
      'financialYear': financialYear,
      'income': income,
      'expenses': expenses,
      'propertyId': propertyId,
      'propertyName': propertyName,
      'notes': notes,
      'isLocked': isLocked,
      'parserVersion': parserVersion,
      'lineItems': lineItems,
    };
    if (sourceFileName != null) {
      map['sourceFileName'] = sourceFileName!;
    }
    if (sourceParser != null) {
      map['sourceParser'] = sourceParser!;
    }
    return map;
  }

  TaxRecord copyWith({
    String? id,
    String? userId,
    String? financialYear,
    Map<String, double>? income,
    Map<String, double>? expenses,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? propertyId,
    String? propertyName,
    String? notes,
    bool? isLocked,
    String? sourceFileName,
    String? sourceParser,
    String? parserVersion,
    List<Map<String, dynamic>>? lineItems,
  }) {
    return TaxRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      financialYear: financialYear ?? this.financialYear,
      income: income ?? this.income,
      expenses: expenses ?? this.expenses,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      propertyId: propertyId ?? this.propertyId,
      propertyName: propertyName ?? this.propertyName,
      notes: notes ?? this.notes,
      isLocked: isLocked ?? this.isLocked,
      sourceFileName: sourceFileName ?? this.sourceFileName,
      sourceParser: sourceParser ?? this.sourceParser,
      parserVersion: parserVersion ?? this.parserVersion,
      lineItems: lineItems ?? this.lineItems,
    );
  }

  // Pre-fill categories based on ATO Rental Property Worksheet
  static TaxRecord empty(
    String userId,
    String financialYear, {
    String propertyId = 'default',
    String propertyName = 'Primary Property',
  }) {
    return TaxRecord(
      userId: userId,
      financialYear: financialYear,
      propertyId: propertyId,
      propertyName: propertyName,
      income: {for (final category in incomeCategoryOptions) category: 0.0},
      expenses: {for (final category in expenseCategoryOptions) category: 0.0},
    );
  }
}
