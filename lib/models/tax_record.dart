import 'package:cloud_firestore/cloud_firestore.dart';

class TaxRecord {
  final String? id;
  final String userId;
  final String financialYear; // e.g., "2024-2025"
  final Map<String, double> income;
  final Map<String, double> expenses;
  final DateTime? createdAt;
  final DateTime? updatedAt;

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
  }) : income = income ?? {},
       expenses = expenses ?? {};

  double get totalIncome =>
      income.values.fold(0.0, (runningTotal, amount) => runningTotal + amount);

  double get totalExpenses => expenses.values.fold(
    0.0,
    (runningTotal, amount) => runningTotal + amount,
  );

  double get netPosition => totalIncome - totalExpenses;

  factory TaxRecord.fromMap(Map<String, dynamic> data, String documentId) {
    return TaxRecord(
      id: documentId,
      userId: data['userId'] ?? '',
      financialYear: data['financialYear'] ?? '',
      income: Map<String, double>.from(data['income'] ?? {}),
      expenses: Map<String, double>.from(data['expenses'] ?? {}),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'financialYear': financialYear,
      'income': income,
      'expenses': expenses,
    };
  }

  TaxRecord copyWith({
    String? id,
    String? userId,
    String? financialYear,
    Map<String, double>? income,
    Map<String, double>? expenses,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TaxRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      financialYear: financialYear ?? this.financialYear,
      income: income ?? this.income,
      expenses: expenses ?? this.expenses,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Pre-fill categories based on ATO Rental Property Worksheet
  static TaxRecord empty(String userId, String financialYear) {
    return TaxRecord(
      userId: userId,
      financialYear: financialYear,
      income: {for (final category in incomeCategoryOptions) category: 0.0},
      expenses: {for (final category in expenseCategoryOptions) category: 0.0},
    );
  }
}
