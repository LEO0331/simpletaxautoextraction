import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';

import '../models/investment_ledger.dart';
import '../models/investment_transaction.dart';
import '../models/tax_decimal.dart';
import '../models/managed_fund_statement.dart';
import '../services/annual_cgt_calculator.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/investment_parcel_ledger.dart';
import '../utils/file_exporter.dart';
import '../utils/source_fingerprint.dart';
import 'investment_cgt_home_screen.dart';
import 'managed_fund_statement_screen.dart';

/// Phase 1 worksheet: explicit selections, reviewed facts, and review gates.
class InvestmentLedgerScreen extends StatefulWidget {
  final AuthService? authService;
  final FirestoreService? firestoreService;
  const InvestmentLedgerScreen({
    super.key,
    this.authService,
    this.firestoreService,
  });

  @override
  State<InvestmentLedgerScreen> createState() => _InvestmentLedgerScreenState();
}

class _InvestmentLedgerScreenState extends State<InvestmentLedgerScreen> {
  late final AuthService _auth;
  late final FirestoreService _store;
  List<InvestmentTransaction> _transactions = [];
  List<SaleAllocation> _allocations = [];
  List<ManagedFundStatement> _statements = [];
  List<Map<String, dynamic>> _savedSnapshots = [];
  int _generation = 0;
  int _year = 2025;
  bool _loading = true;
  bool _busy = false;
  bool _stale = false;
  StreamSubscription<int>? _generationChanges;
  StreamSubscription<dynamic>? _authChanges;
  String? _ownerUid;
  bool _resident = false;
  bool _nonTemporary = false;
  bool _history = false;
  bool _funds = false;
  bool _assets = false;
  bool _lossesReviewed = false;
  final _losses = TextEditingController(text: '0');
  final _lossEvidence = TextEditingController();
  final _lossOrigins = TextEditingController();
  Map<String, dynamic>? _snapshot;

  @override
  void initState() {
    super.initState();
    _auth = widget.authService ?? AuthService();
    _store = widget.firestoreService ?? FirestoreService();
    final uid = _auth.currentUser?.uid;
    _ownerUid = uid;
    _authChanges = _auth.authStateChanges.listen((user) {
      if (mounted && user?.uid != _ownerUid) {
        setState(() {
          _transactions = [];
          _allocations = [];
          _statements = [];
          _savedSnapshots = [];
          _snapshot = null;
          _stale = true;
          _lossEvidence.clear();
          _lossOrigins.clear();
          _losses.text = '0';
        });
      }
    });
    if (uid != null) {
      _generationChanges = _store
          .watchInvestmentLedgerGeneration(uid)
          .listen(
            (generation) {
              if (mounted && !_loading && generation > _generation) {
                setState(() {
                  _stale = true;
                  _snapshot = null;
                });
              }
            },
            onError: (_) {
              if (mounted) {
                setState(() {
                  _stale = true;
                  _snapshot = null;
                });
              }
            },
          );
    }
    _load();
  }

  @override
  void dispose() {
    _losses.dispose();
    _lossEvidence.dispose();
    _lossOrigins.dispose();
    _generationChanges?.cancel();
    _authChanges?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid != _ownerUid) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      // Read generation first; a concurrent source change rejects later saves.
      final generation = await _store.getInvestmentLedgerGeneration(uid);
      final transactions = await _store.getInvestmentTransactionsOnce(uid);
      final allocations = await _store.getInvestmentAllocationsOnce(uid);
      final statements = await _store.getManagedFundStatementsOnce(uid);
      final savedSnapshots = await _store.getInvestmentCalculationSnapshotsOnce(
        uid,
      );
      if (generation != await _store.getInvestmentLedgerGeneration(uid)) {
        throw StateError('Ledger changed while loading.');
      }
      if (!mounted || _auth.currentUser?.uid != _ownerUid) return;
      setState(() {
        _generation = generation;
        _transactions = transactions;
        _allocations = allocations;
        _statements = statements;
        _savedSnapshots = savedSnapshots;
        _snapshot = null;
        _stale = false;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _stale = true;
          _snapshot = null;
        });
      }
      _message('Unable to load the ledger. Retry before calculating.');
    }
  }

  InvestmentLedgerResult _ledger({List<SaleAllocation>? allocations}) =>
      InvestmentParcelLedger().replay(
        transactions: _transactions,
        allocations: allocations ?? _allocations,
        statements: _statements,
        asOfDate: DateTime(_year + 1, 6, 30),
      );

  void _invalidate() => setState(() => _snapshot = null);
  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _allocate(InvestmentTransaction sale) async {
    if (_auth.currentUser?.uid != _ownerUid) return;
    if (!sale.isReviewed || sale.id == null) {
      _message('Review the sale in saved transactions first.');
      return;
    }
    final earlier = InvestmentParcelLedger().replay(
      transactions: _transactions,
      allocations: _allocations,
      statements: _statements.where((s) => s.isReviewed).toList(),
      asOfDate: DateTime(
        sale.tradeDate.year,
        sale.tradeDate.month,
        sale.tradeDate.day,
      ).subtract(const Duration(days: 1)),
    );
    final candidates = earlier.parcels
        .where(
          (p) =>
              p.ticker == sale.ticker &&
              p.accountNumber == sale.accountNumber &&
              p.remainingUnits > TaxDecimal.zero,
        )
        .toList();
    if (candidates.isEmpty) {
      _message(
        'No reviewed earlier parcels available. Check acquisitions and earlier sales.',
      );
      return;
    }
    final previous = _allocations
        .where((a) => a.sellTransactionId == sale.id)
        .firstOrNull;
    final controllers = <String, TextEditingController>{
      for (final p in candidates)
        p.buyTransactionId: TextEditingController(
          text:
              previous?.selections
                  .where((s) => s.buyTransactionId == p.buyTransactionId)
                  .firstOrNull
                  ?.units ??
              '',
        ),
    };
    String? error;
    final selected = await showDialog<SaleAllocation>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          return AlertDialog(
            title: Text('Allocate ${sale.ticker} sale'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Select exactly ${sale.unitsExact ?? sale.units} units. '
                      'Specific parcels; no automatic FIFO.',
                    ),
                    if (earlier.needsReview)
                      const Text(
                        'Earlier history needs review. Resolve missing allocations or facts first.',
                      ),
                    for (final p in candidates)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          key: ValueKey('parcel-${p.buyTransactionId}'),
                          controller: controllers[p.buyTransactionId],
                          decoration: InputDecoration(
                            labelText:
                                '${p.acquisitionDate.toIso8601String().split('T').first}: '
                                '${p.remainingUnits} units available',
                            helperText:
                                'Remaining adjusted basis: AUD ${p.remainingCostBase}',
                          ),
                        ),
                      ),
                    if (error != null)
                      Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  try {
                    final selections = <ParcelSelection>[];
                    for (final entry in controllers.entries) {
                      if (entry.value.text.trim().isEmpty) continue;
                      final units = TaxDecimal.parse(entry.value.text.trim());
                      if (units < TaxDecimal.zero) {
                        throw const FormatException(
                          'Units cannot be negative.',
                        );
                      }
                      if (!units.isZero) {
                        selections.add(
                          ParcelSelection(
                            buyTransactionId: entry.key,
                            units: units.toString(),
                          ),
                        );
                      }
                    }
                    final allocation = SaleAllocation(
                      sellTransactionId: sale.id!,
                      selections: selections,
                      revision: previous?.revision ?? 0,
                      transactionRevisions: {
                        sale.id!: sale.revision,
                        for (final s in selections)
                          s.buyTransactionId: _transactions
                              .singleWhere((t) => t.id == s.buyTransactionId)
                              .revision,
                      },
                    );
                    final trial = InvestmentParcelLedger().replay(
                      transactions: _transactions,
                      statements: _statements
                          .where((s) => s.isReviewed)
                          .toList(),
                      allocations: [
                        ..._allocations.where(
                          (a) => a.sellTransactionId != sale.id,
                        ),
                        allocation,
                      ],
                      asOfDate: sale.tradeDate,
                    );
                    if (trial.needsReview) {
                      update(() => error = trial.issues.join('\n'));
                      return;
                    }
                    Navigator.pop(dialogContext, allocation);
                  } on FormatException {
                    update(
                      () => error =
                          'Enter valid decimal quantities for the selected parcels.',
                    );
                  }
                },
                child: const Text('Save selection'),
              ),
            ],
          );
        },
      ),
    );
    // Dialog route can still be animating while its TextFields are disposed.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final c in controllers.values) {
      c.dispose();
    }
    if (selected == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _store.saveInvestmentAllocation(
        _ownerUid!,
        selected,
        expectedRevision: previous?.revision ?? 0,
      );
      await _load();
      _message('Specific parcel selection saved.');
    } catch (_) {
      _message(
        'Selection could not be saved. Reload and review changed or locked facts.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _calculate() {
    if (_auth.currentUser?.uid != _ownerUid) return;
    if (_stale) {
      _message('Sources changed. Reload before calculating.');
      return;
    }
    final originBalances = <CapitalLossCarryForward>[];
    try {
      for (final line
          in _lossOrigins.text
              .split('\n')
              .where((line) => line.trim().isNotEmpty)) {
        final match = RegExp(
          r'^(\d{4})\s*=\s*(\d+(?:\.\d{1,2})?)$',
        ).firstMatch(line.trim());
        if (match == null) throw const FormatException();
        originBalances.add(
          CapitalLossCarryForward(
            originStartYear: int.parse(match[1]!),
            amount: match[2]!,
            evidenceReference: _lossEvidence.text.trim(),
          ),
        );
      }
    } on FormatException {
      _message('Enter originating balances as startYear=amount, one per line.');
      return;
    }
    final context = AnnualCgtContext(
      confirmedContinuousResident: _resident,
      confirmedNonTemporaryResident: _nonTemporary,
      completeHistory: _history,
      noPendingFundAdjustments: _funds,
      priorLossesReviewed:
          _lossesReviewed && _lossEvidence.text.trim().isNotEmpty,
      priorLosses: _losses.text.trim(),
      priorLossBalances: originBalances,
      confirmedSupportedAssets: _assets,
    );
    final ledger = _ledger();
    final result = AnnualCgtCalculator().calculate(
      ledger: ledger,
      year: TaxYear(_year),
      context: context,
    );
    final input = {
      'schemaVersion': 1,
      'calculationVersion': result.snapshot['calculationVersion'],
      'ruleVersion': result.snapshot['ruleVersion'],
      ...result.toMap(),
      'ledgerGeneration': _generation,
      'inputRevisions': ledger.toMap()['inputRevisions'],
      'allocationRevisions': ledger.toMap()['allocationRevisions'],
      'statementRevisions': ledger.toMap()['statementRevisions'],
      'openingLossEvidence': _lossEvidence.text.trim(),
    };
    setState(
      () => _snapshot = {
        ...input,
        'inputHash': SourceFingerprint.text(jsonEncode(input)),
        'calculatedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<void> _saveSnapshot() async {
    if (_auth.currentUser?.uid != _ownerUid) return;
    if (_snapshot == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _store.saveInvestmentCalculationSnapshot(_ownerUid!, _snapshot!);
      final saved = await _store.getInvestmentCalculationSnapshotsOnce(
        _ownerUid!,
      );
      if (mounted) setState(() => _savedSnapshots = saved);
      _message('Immutable calculation snapshot saved.');
    } catch (_) {
      _message('Sources changed or saving failed. Reload and recalculate.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportSnapshot() async {
    if (_auth.currentUser?.uid != _ownerUid) return;
    final snapshot = _snapshot;
    if (snapshot == null) return;
    try {
      final generation = await _store.getInvestmentLedgerGeneration(_ownerUid!);
      if (!mounted) return;
      if (generation != snapshot['ledgerGeneration']) {
        setState(() {
          _stale = true;
          _snapshot = null;
        });
        _message('Sources changed. Reload and recalculate before exporting.');
        return;
      }
      if (!identical(snapshot, _snapshot)) {
        _message('Review inputs changed. Recalculate before exporting.');
        return;
      }
      final saved = await saveTextFile(
        'investment_cgt_$_year.json',
        const JsonEncoder.withIndent('  ').convert(snapshot),
      );
      _message(saved ? 'Worksheet JSON exported.' : 'Export cancelled.');
    } catch (_) {
      _message('Unable to verify current sources. Retry before exporting.');
    }
  }

  Widget _confirmation(String label, bool value, ValueChanged<bool> change) =>
      CheckboxListTile(
        value: value,
        title: Text(label),
        onChanged: _busy
            ? null
            : (v) {
                change(v ?? false);
                _invalidate();
              },
      );

  @override
  Widget build(BuildContext context) {
    if (_auth.currentUser == null) {
      return const Scaffold(body: Center(child: Text('Please sign in again.')));
    }
    if (_auth.currentUser?.uid != _ownerUid) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Account changed. Return to the dashboard and reopen this screen.',
          ),
        ),
      );
    }
    final ledger = _ledger();
    final sales =
        _transactions
            .where(
              (t) =>
                  t.isSell &&
                  !t.tradeDate.isAfter(DateTime(_year + 1, 6, 30, 23, 59, 59)),
            )
            .toList()
          ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Realised CGT and parcel ledger'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _busy
                ? null
                : () {
                    setState(() => _loading = true);
                    _load();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(InvestmentCgtHomeScreen.disclaimer),
                if (_stale)
                  const Text(
                    'Sources changed or could not be loaded. Reload before calculating.',
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const Key('ledger-year'),
                  initialValue: _year,
                  decoration: const InputDecoration(
                    labelText: 'Financial year',
                  ),
                  items: const [
                    DropdownMenuItem(value: 2024, child: Text('2024-2025')),
                    DropdownMenuItem(value: 2025, child: Text('2025-2026')),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _year = v!;
                          _snapshot = null;
                          _lossesReviewed = false;
                          _lossEvidence.clear();
                          _lossOrigins.clear();
                        }),
                ),
                const SizedBox(height: 12),
                const Text('Recorded remaining holdings at 30 June'),
                TextButton.icon(
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Annual fund statements, AMIT and DRP'),
                  onPressed: _busy
                      ? null
                      : () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ManagedFundStatementScreen(
                                authService: _auth,
                                firestoreService: _store,
                              ),
                            ),
                          );
                          if (mounted) await _load();
                        },
                ),
                if (_transactions.isEmpty)
                  const Text(
                    'No transactions. Import and review acquisitions first.',
                  ),
                if (ledger.needsReview)
                  const Text(
                    'Holdings are incomplete until the issues below are resolved.',
                  ),
                for (final p in ledger.parcels.where(
                  (p) => p.remainingUnits > TaxDecimal.zero,
                ))
                  ListTile(
                    title: Text('${p.ticker}: ${p.remainingUnits} units'),
                    subtitle: SelectableText(
                      'Acquired ${p.acquisitionDate.toIso8601String().split('T').first} · '
                      'Adjusted cost base: AUD ${p.remainingCostBase}\nParcel ID: ${p.buyTransactionId}',
                    ),
                  ),
                for (final issue in ledger.issues)
                  Text(issue, style: const TextStyle(color: Colors.red)),
                if (ledger.costBaseHistory.isNotEmpty)
                  ExpansionTile(
                    title: const Text('AMIT cost-base history'),
                    children: [
                      for (final adjustment in ledger.costBaseHistory)
                        ListTile(
                          title: Text(
                            '${adjustment['date']} · parcel ${adjustment['parcelId']}',
                          ),
                          subtitle: Text(
                            'Statement ${adjustment['statementId']} revision ${adjustment['statementRevision']}\n'
                            'Basis ${adjustment['openingCostBase']} → ${adjustment['closingCostBase']} · '
                            'adjustment ${adjustment['amount']} · E10 gain ${adjustment['e10Gain']}\n'
                            'Evidence: ${adjustment['evidenceReference']}',
                          ),
                        ),
                    ],
                  ),
                for (final gain in ledger.fundGains.where(
                  (g) => TaxYear(_year).contains(g.date),
                ))
                  ListTile(
                    title: Text('${gain.kind} capital gain: AUD ${gain.gain}'),
                    subtitle: Text(
                      'Statement ${gain.statementId} · ${gain.reference} · '
                      'Potential discount eligible: ${gain.discountEligible}',
                    ),
                  ),
                const SizedBox(height: 12),
                const Text('Disposals — select specific acquisition parcels'),
                for (final sale in sales)
                  Card(
                    child: ListTile(
                      title: Text(
                        '${sale.ticker}: ${sale.unitsExact ?? sale.units} units sold',
                      ),
                      subtitle: SelectableText(
                        '${sale.tradeDate.toIso8601String().split('T').first} · '
                        '${sale.isReviewed ? 'Reviewed' : 'Review transaction first'}\nSale ID: ${sale.id}',
                      ),
                      trailing: TextButton(
                        key: ValueKey('allocate-${sale.id}'),
                        onPressed: _busy || _stale
                            ? null
                            : () => _allocate(sale),
                        child: const Text('Select parcels'),
                      ),
                    ),
                  ),
                for (final d in ledger.disposals.where(
                  (d) => TaxYear(_year).contains(d.disposalDate),
                ))
                  ExpansionTile(
                    title: Text(
                      'Gain AUD ${d.capitalGain} / loss AUD ${d.capitalLoss}',
                    ),
                    children: [
                      ListTile(
                        subtitle: Text(
                          'Sale ${d.sellTransactionId} · acquisition ${d.buyTransactionId}\n'
                          '${d.units} units · gross proceeds ${d.grossProceeds} · disposal fees ${d.disposalCosts}\n'
                          'Allocated acquisition basis ${d.costBase}; tax cost base including disposal fees ${d.taxCostBase}\n'
                          'Reduced tax cost base including disposal fees ${d.taxReducedCostBase}\n'
                          'Potential discount eligible: ${d.discountEligible}',
                        ),
                      ),
                    ],
                  ),
                const Divider(),
                const Text(
                  'Annual worksheet: reviewed ordinary AUD investments and supported AMIT statements. '
                  'Missing statements, special fund treatment and residency events require review; do not confirm '
                  'the items below unless supported by your records.',
                ),
                _confirmation(
                  'Confirmed Australian resident throughout relevant ownership',
                  _resident,
                  (v) => _resident = v,
                ),
                _confirmation(
                  'Confirmed not subject to temporary-resident treatment',
                  _nonTemporary,
                  (v) => _nonTemporary = v,
                ),
                _confirmation(
                  'Complete acquisitions, disposals and opening holdings reconciled',
                  _history,
                  (v) => _history = v,
                ),
                _confirmation(
                  'No fund/AMIT changes, corporate actions or attributed gains affect these records',
                  _funds,
                  (v) => _funds = v,
                ),
                _confirmation(
                  'Confirmed personal AUD share/unit capital holdings with brokerage-only bases; no exemptions or rollovers',
                  _assets,
                  (v) => _assets = v,
                ),
                TextField(
                  key: const Key('opening-losses'),
                  controller: _losses,
                  decoration: const InputDecoration(
                    labelText: 'Reviewed opening capital losses (AUD)',
                  ),
                  onChanged: (_) => _invalidate(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _lossEvidence,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText:
                        'Opening loss evidence / originating years (including zero)',
                  ),
                  onChanged: (_) => _invalidate(),
                ),
                TextField(
                  key: const Key('loss-origins'),
                  controller: _lossOrigins,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Losses by originating year: e.g. 2023=100.00',
                    helperText:
                        'One line per start year; sum must match opening losses. Leave blank for zero.',
                  ),
                  onChanged: (_) => _invalidate(),
                ),
                _confirmation(
                  'Opening loss balance is verified, including any zero balance',
                  _lossesReviewed,
                  (v) => _lossesReviewed = v,
                ),
                ElevatedButton(
                  key: const Key('calculate-annual'),
                  onPressed: _busy || _stale ? null : _calculate,
                  child: const Text('Calculate annual worksheet'),
                ),
                if (_snapshot != null) ...[
                  Text(
                    '${_snapshot!['status']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final issue in _snapshot!['issues'] as List)
                    Text('$issue'),
                  Text(
                    'Total current-year gains: AUD ${_snapshot!['totalCapitalGains']}',
                  ),
                  Text(
                    'Current-year losses: AUD ${_snapshot!['currentYearLosses']}',
                  ),
                  Text(
                    'Prior losses used: AUD ${_snapshot!['priorLossesUsed']}',
                  ),
                  Text(
                    'Losses carried forward: AUD ${_snapshot!['lossesCarriedForward']}',
                  ),
                  if (_snapshot!['netCapitalGain'] != null)
                    Text(
                      'Net capital gain: AUD ${_snapshot!['netCapitalGain']}',
                    ),
                  ExpansionTile(
                    title: const Text(
                      'Loss allocation and calculation provenance',
                    ),
                    children: [
                      SelectableText(
                        const JsonEncoder.withIndent('  ').convert(_snapshot),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : _saveSnapshot,
                        child: const Text('Save snapshot'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _exportSnapshot,
                        child: const Text('Export worksheet JSON'),
                      ),
                    ],
                  ),
                ],
                const Divider(),
                const Text(
                  'Latest 20 saved worksheets — historical snapshots are retained after corrections',
                ),
                for (final saved in _savedSnapshots.where(
                  (saved) => saved['year'] == TaxYear(_year).toString(),
                ))
                  ExpansionTile(
                    title: Text('${saved['year']} · ${saved['status']}'),
                    subtitle: Text(
                      saved['ledgerGeneration'] == _generation
                          ? 'Matches the loaded source generation'
                          : 'Historical snapshot — sources have changed; recalculate for current figures',
                    ),
                    children: [
                      SelectableText(
                        const JsonEncoder.withIndent('  ').convert(saved),
                      ),
                    ],
                  ),
              ],
            ),
    );
  }
}
