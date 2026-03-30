import '../models/tax_record.dart';

class AnomalyService {
  List<String> detectYearlyAnomalies(List<TaxRecord> records) {
    if (records.length < 2) {
      return const [];
    }

    final sorted = [...records]
      ..sort((a, b) => a.financialYear.compareTo(b.financialYear));
    final alerts = <String>[];

    for (int i = 1; i < sorted.length; i++) {
      final previous = sorted[i - 1];
      final current = sorted[i];

      final incomeDelta = _deltaPercent(
        previous.totalIncome,
        current.totalIncome,
      );
      final expenseDelta = _deltaPercent(
        previous.totalExpenses,
        current.totalExpenses,
      );

      if (incomeDelta.abs() >= 30) {
        alerts.add(
          'FY ${current.financialYear}: income changed ${incomeDelta.toStringAsFixed(1)}% vs ${previous.financialYear}.',
        );
      }
      if (expenseDelta.abs() >= 30) {
        alerts.add(
          'FY ${current.financialYear}: expenses changed ${expenseDelta.toStringAsFixed(1)}% vs ${previous.financialYear}.',
        );
      }
    }

    return alerts;
  }

  double _deltaPercent(double previous, double current) {
    if (previous == 0) {
      return current == 0 ? 0 : 100;
    }
    return ((current - previous) / previous) * 100;
  }
}
