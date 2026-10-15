import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/corporate_action_decision.dart';
import '../models/investment_transaction.dart';
import '../models/document_coverage.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/investment_event_service.dart';
import '../services/foreign_currency_conversion.dart';
import '../services/parsers/commsec_trade_confirmation_parser.dart';
import '../utils/source_fingerprint.dart';
import 'investment_transaction_review_screen.dart';

class InvestmentSpecialCasesScreen extends StatefulWidget {
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final InvestmentEventService? eventService;
  const InvestmentSpecialCasesScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.eventService,
  });
  @override
  State<InvestmentSpecialCasesScreen> createState() =>
      _InvestmentSpecialCasesScreenState();
}

class _InvestmentSpecialCasesScreenState
    extends State<InvestmentSpecialCasesScreen> {
  late final AuthService _auth;
  late final FirestoreService _store;
  late final InvestmentEventService _events;
  DialogRoute<dynamic>? _dialogRoute;
  MaterialPageRoute<InvestmentTransaction>? _reviewRoute;
  String? _owner;
  List<InvestmentTransaction> _buys = [];
  List<CorporateActionDecision> _actions = [];
  StreamSubscription<dynamic>? _subscription;
  String? _error;
  @override
  void initState() {
    super.initState();
    _auth = widget.authService ?? AuthService();
    _store = widget.firestoreService ?? FirestoreService();
    _events = widget.eventService ?? InvestmentEventService();
    _owner = _auth.currentUser?.uid;
    _load();
    _subscription = _auth.authStateChanges.listen((user) {
      if (!mounted || user?.uid == _owner) return;
      _owner = user?.uid;
      final dialog = _dialogRoute;
      if (dialog?.isActive == true) dialog!.navigator?.removeRoute(dialog);
      final review = _reviewRoute;
      if (review?.isActive == true) review!.navigator?.removeRoute(review);
      setState(() {
        _buys = [];
        _actions = [];
        _error = null;
      });
      _load();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final buys = await _store.getInvestmentTransactionsOnce(uid),
          events = await _events.getCorporateActions(uid);
      if (mounted && _auth.currentUser?.uid == uid) {
        setState(() {
          _buys = buys
              .where((b) => b.isBuy && b.isReviewed && !b.isVoided)
              .toList();
          _actions = events;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to load special-case records.');
      }
    }
  }

  Future<T?> _showDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) async {
    final route = DialogRoute<T>(context: context, builder: builder);
    _dialogRoute = route;
    try {
      final result = await Navigator.of(
        context,
        rootNavigator: true,
      ).push(route);
      await route.completed;
      return result;
    } finally {
      if (identical(_dialogRoute, route)) _dialogRoute = null;
    }
  }

  Future<void> _split([CorporateActionDecision? old]) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final date = TextEditingController(text: old?.date),
        before = TextEditingController(text: old?.oldUnits),
        after = TextEditingController(text: old?.newUnits),
        evidence = TextEditingController(text: old?.evidenceReference);
    String? parcel = old?.parcelId;
    bool reviewed = old?.reviewed ?? false;
    final result = await _showDialog<CorporateActionDecision>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Reviewed split / consolidation'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Same owner/security only, without cash, fractional entitlement disposal, rollover or demerger. The existing basis is conserved. Old units means remaining units immediately before this action.',
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: parcel,
                    items: [
                      for (final b in _buys)
                        DropdownMenuItem(
                          value: b.id,
                          child: Text(
                            '${b.ticker} ${b.tradeDate.toIso8601String().split('T').first} / ${b.id}',
                          ),
                        ),
                    ],
                    onChanged: (v) => set(() => parcel = v),
                    decoration: const InputDecoration(
                      labelText: 'Acquisition parcel',
                    ),
                  ),
                  for (final p in [
                    (date, 'Action date YYYY-MM-DD'),
                    (before, 'Units before action'),
                    (after, 'Units after action'),
                    (evidence, 'Issuer / adviser evidence reference'),
                  ])
                    TextField(
                      controller: p.$1,
                      decoration: InputDecoration(labelText: p.$2),
                    ),
                  CheckboxListTile(
                    value: reviewed,
                    onChanged: (v) => set(() => reviewed = v!),
                    title: const Text(
                      'I verified the eligible action and exact parcel units',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final d = CorporateActionDecision(
                  id:
                      old?.id ??
                      SourceFingerprint.text(
                        jsonEncode([parcel, date.text, evidence.text]),
                      ),
                  userId: uid,
                  date: date.text.trim(),
                  parcelId: parcel ?? '',
                  oldUnits: before.text.trim(),
                  newUnits: after.text.trim(),
                  evidenceReference: evidence.text.trim(),
                  revision: old?.revision ?? 0,
                  reviewed: reviewed,
                );
                if (d.validation().isEmpty) {
                  Navigator.pop(context, d);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(d.validation().join('; '))),
                  );
                }
              },
              child: const Text('Save reviewed action'),
            ),
          ],
        ),
      ),
    );
    for (final c in [date, before, after, evidence]) {
      c.dispose();
    }
    if (result == null || _auth.currentUser?.uid != uid) return;
    try {
      await _events.saveCorporateAction(result);
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Action not saved. Check active reviewed acquisition, later event date and current revision.',
        );
      }
    }
  }

  Future<void> _fx() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final fields = [for (var i = 0; i < 9; i++) TextEditingController()];
    fields[0].text = 'USD';
    bool reviewed = false, forex = false;
    final result = await _showDialog<ForeignCurrencyConversion>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Evidenced AUD conversion'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Convert one gross acquisition cost or disposal amount using its own dated evidence. Review brokerage separately in AUD. Currency gains, elections and other assessable amounts need a separate reviewed workpaper.',
                  ),
                  for (var i = 0; i < fields.length; i++)
                    TextField(
                      controller: fields[i],
                      decoration: InputDecoration(
                        labelText: [
                          'Foreign currency code',
                          'Foreign gross amount',
                          'AUD per one foreign unit',
                          'Conversion / trade date YYYY-MM-DD',
                          'Rate and forex review evidence reference',
                          'Account',
                          'Ticker',
                          'Broker confirmation / trade reference',
                          'Existing broker parser namespace (CommSec or exact existing sourceParser)',
                        ][i],
                      ),
                    ),
                  CheckboxListTile(
                    value: reviewed,
                    onChanged: (v) => set(() => reviewed = v!),
                    title: const Text(
                      'I reviewed this dated rate and conversion',
                    ),
                  ),
                  CheckboxListTile(
                    value: forex,
                    onChanged: (v) => set(() => forex = v!),
                    title: const Text(
                      'Separate forex realisations and elections were reviewed',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final c = ForeignCurrencyConversion(
                  currency: fields[0].text.trim().toUpperCase(),
                  foreignAmount: fields[1].text.trim(),
                  audPerUnit: fields[2].text.trim(),
                  date: fields[3].text.trim(),
                  evidenceReference: fields[4].text.trim(),
                  reviewed: reviewed,
                  separateForexReviewed: forex,
                );
                if (c.validation().isEmpty &&
                    fields[5].text.trim().isNotEmpty &&
                    fields[6].text.trim().isNotEmpty &&
                    fields[7].text.trim().isNotEmpty &&
                    fields[8].text.trim().isNotEmpty) {
                  Navigator.pop(context, c);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Complete all source fields and both review confirmations.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Review AUD trade draft'),
            ),
          ],
        ),
      ),
    );
    final account = fields[5].text.trim(),
        ticker = fields[6].text.trim().toUpperCase(),
        reference = fields[7].text.trim(),
        broker = fields[8].text.trim();
    for (final c in fields) {
      c.dispose();
    }
    if (result == null || _auth.currentUser?.uid != uid || !mounted) return;
    final gross = result.audAmount!;
    final extraction = InvestmentExtractionResult(
      draft: InvestmentTransactionDraft(
        ticker: ticker,
        securityName: ticker,
        transactionType: InvestmentTransactionType.buy,
        tradeDate: parseDocumentDate(result.date),
        settlementDate: null,
        units: null,
        averagePrice: null,
        consideration: double.parse(gross.toString()),
        brokerage: null,
        gst: null,
        totalCost: null,
        confirmationNumber: reference,
        accountNumber: account,
        sourceFileName: null,
        sourceParser: broker.toLowerCase() == 'commsec'
            ? CommsecTradeConfirmationParser.parserName
            : broker,
        parserVersion: 'fx-v1',
        notes:
            'Reviewed gross AUD conversion: ${jsonEncode(result.toMap())}. Brokerage and total settlement require separate AUD review. Record separate forex/election outcome in workspace evidence.',
        needsReview: true,
        directionNeedsReview: true,
        considerationExact: gross.toString(),
      ),
      confidence: 0,
      missingFields: const [
        'direction',
        'units',
        'AUD brokerage',
        'AUD settlement',
      ],
      warnings: const [
        'Converted amounts alone do not determine forex income or liability.',
      ],
      rawText: '',
    );
    final route = MaterialPageRoute<InvestmentTransaction>(
      builder: (_) => InvestmentTransactionReviewScreen(
        userId: uid,
        extraction: extraction,
      ),
    );
    _reviewRoute = route;
    final trade = await Navigator.of(context).push(route);
    if (identical(_reviewRoute, route)) _reviewRoute = null;
    if (trade == null || _auth.currentUser?.uid != uid) return;
    try {
      final duplicate = await _store.findInvestmentDuplicate(uid, trade);
      if (duplicate != null) throw StateError('Trade already exists');
      if (_auth.currentUser?.uid != uid) return;
      await _store.saveInvestmentTransaction(trade);
      if (mounted) {
        setState(
          () => _error =
              'Reviewed AUD trade saved. Record any separate forex amounts and evidence in the tax-year workspace.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Trade not saved. Check existing duplicates and review all exact AUD fields.',
        );
      }
    }
  }

  Future<void> _void(CorporateActionDecision action) async {
    final uid = _auth.currentUser?.uid;
    if (uid != action.userId) return;
    try {
      await _events.saveCorporateAction(
        CorporateActionDecision.fromMap({
          ...action.toMap(),
          'isVoided': true,
        }, id: action.id),
      );
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Action was not voided. Reload to check its current revision.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Investment special cases')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton(
          onPressed: () => _split(),
          child: const Text('Record reviewed split / consolidation'),
        ),
        OutlinedButton(
          onPressed: _fx,
          child: const Text('Create reviewed AUD conversion draft'),
        ),
        TextButton(
          onPressed: () => Navigator.pushNamed(context, '/tax-years'),
          child: const Text(
            'Adviser workpaper decisions in tax-year workspace',
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'Indexed gains, demergers, scrip rollovers and other complex treatments require adviser decisions with independent evidence. Ordinary calculations must not be used as a substitute. No automatic CPI indexation or currency-gain determination is applied here.',
          ),
        ),
        if (_error != null) Text(_error!),
        for (final d in _actions)
          ListTile(
            title: Text('${d.date}: ${d.oldUnits} → ${d.newUnits} units'),
            subtitle: Text('${d.parcelId} · revision ${d.revision}'),
            onTap: () => _split(d),
            trailing: IconButton(
              onPressed: () => _void(d),
              icon: const Icon(Icons.block),
              tooltip: 'Void action (retain history)',
            ),
          ),
      ],
    ),
  );
}
