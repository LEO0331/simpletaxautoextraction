import 'package:cloud_firestore/cloud_firestore.dart';

class TaxRecord {
  final String? id;
  final String userId;
  final String financialYear; // e.g., "2024-2025"
  final Map<String, double> income;
  final Map<String, double> expenses;

  TaxRecord({
    this.id,
    required this.userId,
    required this.financialYear,
    Map<String, double>? income,
    Map<String, double>? expenses,
  })  : income = income ?? {},
        expenses = expenses ?? {};

  double get totalIncome =>
      income.values.fold(0.0, (sum, amount) => sum + amount);

  double get totalExpenses =>
      expenses.values.fold(0.0, (sum, amount) => sum + amount);

  double get netPosition => totalIncome - totalExpenses;

  factory TaxRecord.fromMap(Map<String, dynamic> data, String documentId) {
    return TaxRecord(
      id: documentId,
      userId: data['userId'] ?? '',
      financialYear: data['financialYear'] ?? '',
      income: Map<String, double>.from(data['income'] ?? {}),
      expenses: Map<String, double>.from(data['expenses'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'financialYear': financialYear,
      'income': income,
      'expenses': expenses,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  // Pre-fill categories based on ATO Rental Property Worksheet
  static TaxRecord empty(String userId, String financialYear) {
    return TaxRecord(
      userId: userId,
      financialYear: financialYear,
      income: {
        'Gross rent': 0.0,
        'Other rental-related income': 0.0,
      },
      expenses: {
        'Advertising for tenants': 0.0,
        'Body corporate fees and charges': 0.0,
        'Borrowing expenses': 0.0,
        'Cleaning': 0.0,
        'Council rates': 0.0,
        'Capital works deductions': 0.0,
        'Gardening and lawn mowing': 0.0,
        'Insurance': 0.0,
        'Interest on loans': 0.0,
        'Land tax': 0.0,
        'Legal expenses': 0.0,
        'Pest control': 0.0,
        'Property agent fees and commission': 0.0,
        'Repairs and maintenance': 0.0,
        'Stationery, telephone and postage': 0.0,
        'Water charges': 0.0,
        'Sundry rental expenses': 0.0,
      },
    );
  }
}
