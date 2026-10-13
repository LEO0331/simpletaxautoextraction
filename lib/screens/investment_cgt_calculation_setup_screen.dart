import 'package:flutter/material.dart';

import '../models/investment_transaction.dart';
import '../models/investment_ledger.dart';
import '../models/tax_decimal.dart';
import '../services/investment_parcel_ledger.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'investment_cgt_result_screen.dart';
import 'investment_cgt_routes.dart';

class InvestmentCgtCalculationSetupScreen extends StatefulWidget {
  final AuthService? authService;
  final FirestoreService? firestoreService;

  const InvestmentCgtCalculationSetupScreen({
    super.key,
    this.authService,
    this.firestoreService,
  });

  @override
  State<InvestmentCgtCalculationSetupScreen> createState() =>
      _InvestmentCgtCalculationSetupScreenState();
}

class _InvestmentCgtCalculationSetupScreenState
    extends State<InvestmentCgtCalculationSetupScreen> {
  late final AuthService _authService;
  late final FirestoreService _firestoreService;
  DateTime? _cutOffDate;
  final Map<String, TextEditingController> _priceControllers = {};
  bool _loading = true;
  List<InvestmentTransaction> _transactions = const [];
  List<SaleAllocation> _allocations = const [];
  String? _loadError;
  List<String> _tickers = const [];

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _firestoreService = widget.firestoreService ?? FirestoreService();
    _load();
  }

  Future<void> _load() async {
    final user = _authService.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      return;
    }
    try {
      final records = await _firestoreService.getInvestmentTransactionsOnce(
        user.uid,
      );
      final allocations = await _firestoreService.getInvestmentAllocationsOnce(
        user.uid,
      );
      final buys = records.where((r) => r.isBuy).toList();
      final tickerSet = buys.map((e) => e.ticker).toSet().toList()..sort();
      for (final t in tickerSet) {
        _priceControllers[t] = TextEditingController();
      }
      if (mounted) {
        setState(() {
          _transactions = records;
          _allocations = allocations;
          _tickers = tickerSet;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError =
              'Unable to load transactions and parcel selections. Please retry.';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _calculate() {
    if (_cutOffDate == null) {
      _showError('Cut-off date is required.');
      return;
    }

    final day = DateTime.utc(
      _cutOffDate!.year,
      _cutOffDate!.month,
      _cutOffDate!.day,
    );
    var requiredTickers = _transactions
        .where(
          (t) =>
              t.isBuy &&
              !DateTime.utc(
                t.tradeDate.year,
                t.tradeDate.month,
                t.tradeDate.day,
              ).isAfter(day),
        )
        .map((t) => t.ticker)
        .toSet();
    if (_transactions.any(
      (t) =>
          t.isSell &&
          !DateTime.utc(
            t.tradeDate.year,
            t.tradeDate.month,
            t.tradeDate.day,
          ).isAfter(day),
    )) {
      final ledger = InvestmentParcelLedger().replay(
        transactions: _transactions,
        allocations: _allocations,
        asOfDate: _cutOffDate,
      );
      if (ledger.needsReview) {
        _showError(
          'Review transaction facts and sale selections in the parcel ledger first.',
        );
        return;
      }
      requiredTickers = ledger.parcels
          .where((p) => p.remainingUnits > TaxDecimal.zero)
          .map((p) => p.ticker)
          .toSet();
    }
    final prices = <String, double>{};
    for (final t in requiredTickers) {
      final v = double.tryParse(_priceControllers[t]!.text.trim());
      if (v == null || !v.isFinite || v <= 0) {
        _showError('Cut-off price is required and must be > 0 for $t.');
        return;
      }
      prices[t] = v;
    }

    final hasInvalidDate = _transactions.any(
      (tx) => DateTime.utc(
        tx.tradeDate.year,
        tx.tradeDate.month,
        tx.tradeDate.day,
      ).isAfter(day),
    );
    if (hasInvalidDate) {
      _showError(
        'Some transactions are after cut-off date and will be excluded from result.',
      );
    }

    Navigator.pushNamed(
      context,
      InvestmentCgtRoutes.results,
      arguments: InvestmentCgtResultArgs(
        cutOffDate: _cutOffDate!,
        tickerPrices: prices,
        transactions: _transactions,
        allocations: _allocations,
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CGT Calculation Setup')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(child: Text(_loadError!))
          : _transactions.isEmpty
          ? const Center(child: Text('No BUY transactions available.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  title: Text(
                    _cutOffDate == null
                        ? 'Select cut-off date'
                        : 'Cut-off date: ${_cutOffDate!.toIso8601String().split('T').first}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(now.year - 20),
                      lastDate: DateTime(now.year + 2),
                      initialDate: _cutOffDate ?? now,
                    );
                    if (picked != null) {
                      setState(() {
                        _cutOffDate = DateTime(
                          picked.year,
                          picked.month,
                          picked.day,
                        );
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                const Text('Cut-off price per ticker'),
                const Text(
                  'Only remaining holdings at the selected cut-off require a price.',
                ),
                const SizedBox(height: 8),
                ..._tickers.map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: _priceControllers[t],
                      decoration: InputDecoration(
                        labelText: '$t cut-off price',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _calculate,
                  child: const Text('Calculate'),
                ),
              ],
            ),
    );
  }
}
