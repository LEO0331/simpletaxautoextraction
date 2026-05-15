import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/investment_cgt_calculation.dart';
import '../models/investment_transaction.dart';
import '../services/investment_cgt_calculator.dart';
import '../services/export_service.dart';
import '../utils/file_exporter.dart';

class InvestmentCgtResultArgs {
  final DateTime cutOffDate;
  final Map<String, double> tickerPrices;
  final List<InvestmentTransaction> transactions;

  const InvestmentCgtResultArgs({
    required this.cutOffDate,
    required this.tickerPrices,
    required this.transactions,
  });
}

class InvestmentCgtResultScreen extends StatelessWidget {
  final InvestmentCgtResultArgs args;
  final ExportService _exportService = ExportService();
  final InvestmentCgtCalculator _calculator = const InvestmentCgtCalculator();

  InvestmentCgtResultScreen({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    final session = _calculator.calculate(
      cutOffDate: args.cutOffDate,
      tickerPrices: args.tickerPrices,
      transactions: args.transactions,
    );
    final calculations = session.calculations;
    final summary = session.summary;

    return Scaffold(
      appBar: AppBar(title: const Text('Investment CGT Results')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _summaryCard('Total cost base', summary.totalCostBase),
                _summaryCard(
                  'Total market value',
                  summary.totalMarketValueAtCutOff,
                ),
                _summaryCard(
                  'Total estimated gain/loss',
                  summary.totalEstimatedGainLoss,
                ),
                _summaryCard(
                  'Potential discount eligible gains',
                  summary.totalPotentialDiscountEligibleGains,
                ),
                _summaryCard(
                  'Not eligible gains',
                  summary.totalNotEligibleGains,
                ),
                _summaryCard(
                  'Estimated taxable gain after discount',
                  summary.totalEstimatedTaxableGainAfterDiscount,
                ),
                _summaryCard(
                  'Estimated capital losses',
                  summary.totalEstimatedCapitalLosses,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () async {
                    final csv = _exportService
                        .exportInvestmentCgtCalculationToCsv(calculations);
                    final saved = await saveTextFile(
                      'investment_cgt_results.csv',
                      csv,
                    );
                    if (!saved) {
                      await Clipboard.setData(ClipboardData(text: csv));
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            saved
                                ? 'Calculation CSV exported.'
                                : 'CSV copied to clipboard.',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Export CSV'),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'This is an estimate only and does not constitute tax advice. '
                    'Please confirm with a qualified accountant or tax adviser.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: calculations.isEmpty
                  ? const Center(
                      child: Text(
                        'No eligible BUY transactions found for this cut-off setup.',
                      ),
                    )
                  : ListView.separated(
                      itemCount: calculations.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _calculationCard(calculations[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(String label, double value) {
    return Card(
      child: SizedBox(
        width: 260,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _calculationCard(InvestmentCgtCalculation c) {
    final gainPositive = c.estimatedGainLoss >= 0;
    final daysColor = c.potentialCgtDiscountEligible
        ? Colors.green
        : Colors.red;
    final gainColor = gainPositive ? Colors.green : Colors.red;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.transaction.ticker} • ${c.transaction.securityName}'),
            const SizedBox(height: 6),
            Text(
              'Trade date: ${c.transaction.tradeDate.toIso8601String().split('T').first}',
            ),
            Text('Units: ${c.transaction.units}'),
            Text('Cost base: ${c.transaction.totalCost.toStringAsFixed(2)}'),
            Text('Cut-off price: ${c.cutOffPrice.toStringAsFixed(6)}'),
            Text('Market value: ${c.marketValueAtCutOff.toStringAsFixed(2)}'),
            Text(
              'Estimated gain/loss: ${c.estimatedGainLoss.toStringAsFixed(2)} (${c.gainLossPercent.toStringAsFixed(2)}%)',
              style: TextStyle(color: gainColor, fontWeight: FontWeight.w700),
            ),
            Text(
              'Holding days: ${c.holdingDays}',
              style: TextStyle(color: daysColor, fontWeight: FontWeight.w700),
            ),
            Text(
              c.potentialCgtDiscountEligible
                  ? 'Potential CGT discount eligible'
                  : 'Not yet over 12 months',
              style: TextStyle(color: daysColor, fontWeight: FontWeight.w700),
            ),
            Text(
              'Estimated taxable gain after discount: ${c.estimatedTaxableGainAfterDiscount.toStringAsFixed(2)}',
            ),
          ],
        ),
      ),
    );
  }
}
