import 'package:flutter/material.dart';

import '../models/investment_transaction.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'investment_transaction_review_screen.dart';
import '../services/parsers/commsec_trade_confirmation_parser.dart';

class InvestmentTransactionListScreen extends StatefulWidget {
  final AuthService? authService;
  final FirestoreService? firestoreService;

  const InvestmentTransactionListScreen({
    super.key,
    this.authService,
    this.firestoreService,
  });

  @override
  State<InvestmentTransactionListScreen> createState() =>
      _InvestmentTransactionListScreenState();
}

class _InvestmentTransactionListScreenState
    extends State<InvestmentTransactionListScreen> {
  late final AuthService _authService;
  late final FirestoreService _firestoreService;
  String _tickerFilter = '';
  String _typeFilter = 'ALL';
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _firestoreService = widget.firestoreService ?? FirestoreService();
  }

  bool _match(InvestmentTransaction t) {
    final tickerOk =
        _tickerFilter.isEmpty ||
        t.ticker.toLowerCase().contains(_tickerFilter.toLowerCase());
    final typeOk =
        _typeFilter == 'ALL' || t.transactionType.value == _typeFilter;
    final dateOk =
        _dateRange == null ||
        (!t.tradeDate.isBefore(_dateRange!.start) &&
            !t.tradeDate.isAfter(_dateRange!.end));
    return tickerOk && typeOk && dateOk;
  }

  Future<void> _edit(InvestmentTransaction t) async {
    final updated = await Navigator.push<InvestmentTransaction>(
      context,
      MaterialPageRoute(
        builder: (_) => InvestmentTransactionReviewScreen(
          userId: t.userId,
          extraction: InvestmentExtractionResult(
            draft: InvestmentTransactionDraft(
              ticker: t.ticker,
              securityName: t.securityName,
              transactionType: t.transactionType,
              tradeDate: t.tradeDate,
              settlementDate: t.settlementDate,
              units: t.units,
              averagePrice: t.averagePrice,
              consideration: t.consideration,
              brokerage: t.brokerage,
              gst: t.gst,
              totalCost: t.totalCost,
              confirmationNumber: t.confirmationNumber,
              accountNumber: t.accountNumber,
              sourceFileName: t.sourceFileName,
              sourceParser: t.sourceParser,
              parserVersion: t.parserVersion,
              notes: t.notes,
              needsReview: false,
            ),
            confidence: 1,
            missingFields: const [],
            warnings: const [],
            rawText: '',
          ),
          existing: t,
        ),
      ),
    );
    if (updated == null) return;
    await _firestoreService.saveInvestmentTransaction(updated);
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please sign in again.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Investment Transactions')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Ticker filter',
                    ),
                    onChanged: (v) => setState(() => _tickerFilter = v),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _typeFilter,
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('ALL')),
                    DropdownMenuItem(value: 'BUY', child: Text('BUY')),
                    DropdownMenuItem(value: 'SELL', child: Text('SELL')),
                  ],
                  onChanged: (v) => setState(() => _typeFilter = v ?? 'ALL'),
                ),
                IconButton(
                  tooltip: 'Date range',
                  icon: const Icon(Icons.date_range),
                  onPressed: () async {
                    final now = DateTime.now();
                    final selected = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(now.year - 20),
                      lastDate: DateTime(now.year + 1),
                    );
                    if (selected != null) {
                      setState(() => _dateRange = selected);
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<InvestmentTransaction>>(
              stream: _firestoreService.getInvestmentTransactions(user.uid),
              builder: (_, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final records = snapshot.data!.where(_match).toList();
                if (records.isEmpty) {
                  return const Center(child: Text('No transactions found.'));
                }
                return ListView.separated(
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final t = records[i];
                    return Card(
                      child: ListTile(
                        title: Text('${t.ticker} • ${t.transactionType.value}'),
                        subtitle: Text(
                          '${t.securityName}\n'
                          'Trade: ${t.tradeDate.toIso8601String().split('T').first} | Units: ${t.units}\n'
                          'Avg: ${t.averagePrice.toStringAsFixed(6)} | Brokerage: ${t.brokerage.toStringAsFixed(2)} | Total: ${t.totalCost.toStringAsFixed(2)}'
                          '${t.sourceFileName == null ? '' : '\nSource: ${t.sourceFileName}'}',
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            switch (v) {
                              case 'edit':
                                await _edit(t);
                                break;
                              case 'delete':
                                await _firestoreService
                                    .deleteInvestmentTransaction(
                                      user.uid,
                                      t.id!,
                                    );
                                break;
                              case 'lock':
                                await _firestoreService
                                    .saveInvestmentTransaction(
                                      t.copyWith(isLocked: !t.isLocked),
                                    );
                                break;
                              default:
                                break;
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                            PopupMenuItem(
                              value: 'lock',
                              child: Text(t.isLocked ? 'Unlock' : 'Lock'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
