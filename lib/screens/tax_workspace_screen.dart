import '../models/i1_adviser_decision.dart';
import '../services/tax_rule_registry.dart';
import '../services/accountant_workpaper_export.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../models/managed_fund_statement.dart';
import '../models/tax_record.dart';
import '../models/tax_workspace.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/tax_workspace_calculator.dart';
import '../services/tax_workspace_service.dart';
import '../services/tax_workspace_coordinator.dart';
import '../utils/file_exporter.dart';

/// Reviewed workpapers only: section review never implies lodgment or liability.
class TaxWorkspaceScreen extends StatefulWidget {
  final AuthService? authService;
  final TaxWorkspaceService? workspaceService;
  final FirestoreService? firestoreService;
  const TaxWorkspaceScreen({
    super.key,
    this.authService,
    this.workspaceService,
    this.firestoreService,
  });

  @override
  State<TaxWorkspaceScreen> createState() => _TaxWorkspaceScreenState();
}

class _TaxWorkspaceScreenState extends State<TaxWorkspaceScreen> {
  late final AuthService _auth;
  late final TaxWorkspaceService _store;
  late final FirestoreService _sources;
  late final TaxWorkspaceCoordinator _coordinator;
  TaxWorkspaceBundle? _bundle;
  String? _owner;
  int _year = 2025;
  int _generation = 0;
  int _investmentGeneration = 0;
  bool _loading = true;
  bool _busy = false;
  bool _stale = false;
  String? _error;
  TaxWorkspace? _workspace;
  TaxWorkspaceReport? _report;
  List<TaxWorkspaceItem> _items = [];
  List<TaxRecord> _rentals = [];
  List<ManagedFundStatement> _funds = [];
  List<Map<String, dynamic>> _cgt = [];
  List<Map<String, dynamic>> _snapshots = [];
  StreamSubscription<dynamic>? _authChanges;
  StreamSubscription<int>? _workspaceChanges;
  StreamSubscription<int>? _investmentChanges;
  StreamSubscription<List<TaxRecord>>? _rentalChanges;
  int _loadToken = 0;
  DialogRoute<dynamic>? _dialogRoute;

  bool get _authorised => _owner != null && _auth.currentUser?.uid == _owner;
  bool get _editable =>
      _authorised &&
      !_busy &&
      !_loading &&
      !_stale &&
      _workspace?.status != 'finalised';

  @override
  void initState() {
    super.initState();
    _auth = widget.authService ?? AuthService();
    _store = widget.workspaceService ?? TaxWorkspaceService();
    _sources = widget.firestoreService ?? FirestoreService();
    _coordinator = TaxWorkspaceCoordinator(
      workspaces: _store,
      sources: _sources,
    );
    _owner = _auth.currentUser?.uid;
    _authChanges = _auth.authStateChanges.listen((user) {
      if (user?.uid != _owner && mounted) {
        _loadToken++;
        if (_dialogRoute?.isCurrent == true && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _workspaceChanges?.cancel();
        _investmentChanges?.cancel();
        _rentalChanges?.cancel();
        setState(() {
          _workspace = null;
          _bundle = null;
          _report = null;
          _items = [];
          _rentals = [];
          _funds = [];
          _cgt = [];
          _snapshots = [];
          _stale = true;
          _loading = false;
        });
      }
    });
    _subscribe();
    _load();
  }

  void _subscribe() {
    _workspaceChanges?.cancel();
    _investmentChanges?.cancel();
    _rentalChanges?.cancel();
    final owner = _owner;
    if (owner == null) return;
    void changed() {
      if (mounted && !_loading) {
        setState(() {
          _stale = true;
          _report = null;
        });
      }
    }

    _workspaceChanges = _store.watchGeneration(owner).listen((value) {
      if (value != _generation) changed();
    }, onError: (_) => changed());
    _investmentChanges = _sources.watchInvestmentLedgerGeneration(owner).listen(
      (value) {
        if (value != _investmentGeneration) changed();
      },
      onError: (_) => changed(),
    );
    _rentalChanges = _sources.getUserTaxRecords(owner).listen((records) {
      final relevant = records
          .where((r) => r.financialYear == '$_year-${_year + 1}')
          .toList();
      if (canonicalTaxFingerprint(
            relevant.map(taxRecordFingerprint).toList(),
          ) !=
          canonicalTaxFingerprint(
            _rentals.map(taxRecordFingerprint).toList(),
          )) {
        changed();
      }
    }, onError: (_) => changed());
  }

  @override
  void dispose() {
    _authChanges?.cancel();
    _workspaceChanges?.cancel();
    _investmentChanges?.cancel();
    _rentalChanges?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final owner = _owner;
    if (!_authorised || owner == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final token = ++_loadToken;
    final year = _year;
    setState(() {
      _loading = true;
      _error = null;
      _report = null;
    });
    try {
      final bundle = await _coordinator.load(owner, year);
      final snapshots = await _store.getSnapshots(owner, year);
      if (bundle.workspaceGeneration != await _store.getGeneration(owner) ||
          bundle.investmentGeneration !=
              await _sources.getInvestmentLedgerGeneration(owner)) {
        throw StateError('Sources changed while loading historical snapshots');
      }
      if (!mounted || !_authorised || token != _loadToken) return;
      setState(() {
        _bundle = bundle;
        _workspace = bundle.workspace;
        _items = bundle.items;
        _rentals = bundle.rentals;
        _funds = bundle.fundStatements;
        _cgt = bundle.cgtSnapshots;
        _snapshots = snapshots;
        _generation = bundle.workspaceGeneration;
        _investmentGeneration = bundle.investmentGeneration;
        _loading = false;
        _stale = false;
      });
    } catch (_) {
      if (mounted && _authorised && token == _loadToken) {
        setState(() {
          _loading = false;
          _stale = true;
          _error =
              'Unable to load current sources. Reload before editing or calculating.';
        });
      }
    }
  }

  void _message(String message) {
    if (mounted && _authorised) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!_authorised || _busy) return;
    setState(() {
      _busy = true;
      _report = null;
    });
    try {
      await action();
      if (_authorised) await _load();
    } catch (_) {
      _message(
        'Unable to save. Reload and check the evidence and current revision.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveWorkspace(TaxWorkspace workspace) => _run(() async {
    await _store.saveWorkspace(workspace);
  });

  Future<void> _calculate() async {
    if (!_authorised || _workspace == null || _stale || _busy) return;
    setState(() => _busy = true);
    try {
      final bundle = await _coordinator.load(_owner!, _year);
      if (mounted && _authorised) {
        setState(() {
          _bundle = bundle;
          _workspace = bundle.workspace;
          _report = bundle.report;
          _items = bundle.items;
          _rentals = bundle.rentals;
          _funds = bundle.fundStatements;
          _cgt = bundle.cgtSnapshots;
          _generation = bundle.workspaceGeneration;
          _investmentGeneration = bundle.investmentGeneration;
        });
      }
    } catch (_) {
      _message('Unable to calculate. Check the source data and reload.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finalise() async {
    final bundle = _bundle;
    if (bundle == null || !(_report?.canFinalise ?? false) || !_editable) {
      return;
    }
    await _run(() async {
      await _coordinator.finalise(bundle);
    });
  }

  Future<void> _amend() async {
    final result = await _textDialog(
      'Amend finalised workpaper',
      'Reason for amendment',
    );
    if (result == null || result.trim().isEmpty || !_authorised) return;
    await _run(() async {
      await _store.amendWorkspace(
        _owner!,
        _year,
        _workspace!.revision,
        result.trim(),
      );
    });
  }

  Future<T?> _showDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<T>(context: context, builder: builder);
    _dialogRoute = route;
    try {
      final result = await navigator.push(route);
      // A pop returns before the fade-out is disposed. Keep form controllers
      // alive until the route's widgets are actually removed.
      await route.completed;
      return result;
    } finally {
      _dialogRoute = null;
    }
  }

  Future<String?> _textDialog(
    String title,
    String label, {
    String value = '',
  }) async {
    final controller = TextEditingController(text: value);
    final result = await _showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLength: 1000,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _section(String section) async {
    final workspace = _workspace;
    if (!_editable || workspace == null) return;
    var state = workspace.sectionStates[section] ?? 'notStarted';
    final evidence = TextEditingController(
      text: workspace.sectionEvidence[section] ?? '',
    );
    final saved = await _showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('${_label(section)} review'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: state,
                  decoration: const InputDecoration(
                    labelText: 'Section status',
                  ),
                  items: taxWorkspaceStates
                      .map(
                        (v) =>
                            DropdownMenuItem(value: v, child: Text(_label(v))),
                      )
                      .toList(),
                  onChanged: (v) => update(() => state = v!),
                ),
                TextField(
                  controller: evidence,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Evidence or reason not applicable',
                  ),
                ),
                const Text(
                  'Reconciled is a review assertion. Source gaps and inconsistent totals still block finalisation.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final text = evidence.text.trim();
    evidence.dispose();
    if (saved == true && _editable) {
      await _saveWorkspace(
        workspace.copyWith(
          sectionStates: {...workspace.sectionStates, section: state},
          sectionEvidence: {...workspace.sectionEvidence, section: text},
        ),
      );
    }
  }

  Future<void> _item({TaxWorkspaceItem? existing, TaxRecord? rental}) async {
    if (!_editable) return;
    var category = rental != null
        ? 'rentalReview'
        : existing?.category ?? 'salary';
    var reviewed = existing?.isReviewed ?? false;
    final values = <String, TextEditingController>{
      'sourceReference': TextEditingController(
        text: existing?.sourceReference ?? '',
      ),
      'amount': TextEditingController(text: existing?.amount ?? '0'),
      'deductions': TextEditingController(text: existing?.deductions ?? '0'),
      'withholding': TextEditingController(text: existing?.withholding ?? '0'),
      'frankingCredits': TextEditingController(
        text: existing?.frankingCredits ?? '0',
      ),
      'taxOffset': TextEditingController(text: existing?.taxOffset ?? '0'),
      'ownershipPercent': TextEditingController(
        text: existing?.ownershipPercent ?? '100',
      ),
    };
    String? error;
    TaxWorkspaceItem buildItem() => TaxWorkspaceItem(
      id: existing?.id,
      userId: _owner!,
      yearStart: _year,
      revision: existing?.revision ?? 0,
      category: category,
      sourceReference: values['sourceReference']!.text.trim(),
      amount: values['amount']!.text.trim(),
      deductions: values['deductions']!.text.trim(),
      withholding: values['withholding']!.text.trim(),
      frankingCredits: values['frankingCredits']!.text.trim(),
      taxOffset: values['taxOffset']!.text.trim(),
      ownershipPercent: values['ownershipPercent']!.text.trim(),
      isReviewed: reviewed,
      rentalRecordId: rental?.id ?? existing?.rentalRecordId ?? '',
      rentalFingerprint: rental != null
          ? taxRecordFingerprint(rental)
          : existing?.rentalFingerprint ?? '',
    );
    final result = await _showDialog<TaxWorkspaceItem>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            rental == null
                ? 'Review source item'
                : 'Review rental contribution',
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (category != 'rentalReview')
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items:
                          [
                                'salary',
                                'interest',
                                'dividends',
                                'otherIncome',
                                'deductions',
                                'offsets',
                              ]
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(_label(v)),
                                ),
                              )
                              .toList(),
                      onChanged: existing != null
                          ? null
                          : (v) => update(() {
                              category = v!;
                              if (category == 'deductions') {
                                values['deductions']!.text = '0';
                              }
                              if (category == 'offsets') {
                                values['taxOffset']!.text = '0';
                              }
                              reviewed = false;
                            }),
                    ),
                  if (rental != null)
                    Text(
                      '${rental.propertyName}: income ${rental.totalIncome.toStringAsFixed(2)}, deductions ${rental.totalExpenses.toStringAsFixed(2)}. Verify deductibility and ownership. Use 100% if these figures already represent your share.',
                    ),
                  if (category == 'dividends')
                    const Text(
                      'Amount is assessable dividend income, including the franking credit gross-up where applicable. Enter franking credits separately as offsets; they are not added to income automatically.',
                    ),
                  if (category == 'deductions' || category == 'offsets')
                    const Text(
                      'Enter the deduction or offset once in Amount. Use separate evidence-backed items for additional claims.',
                    ),
                  for (final entry in values.entries)
                    if (entry.key == 'sourceReference' ||
                        (category == 'rentalReview'
                                ? entry.key == 'ownershipPercent'
                                : entry.key != 'ownershipPercent') &&
                            !(category == 'deductions' &&
                                entry.key == 'deductions') &&
                            !(category == 'offsets' &&
                                entry.key == 'taxOffset'))
                      TextField(
                        key: ValueKey('item-${entry.key}'),
                        controller: entry.value,
                        readOnly:
                            existing != null && entry.key == 'sourceReference',
                        maxLength: entry.key == 'sourceReference' ? 1000 : 128,
                        decoration: InputDecoration(
                          labelText: _label(entry.key),
                        ),
                        onChanged: (_) => update(() => reviewed = false),
                      ),
                  CheckboxListTile(
                    key: const Key('item-reviewed'),
                    value: reviewed,
                    title: const Text(
                      'I reviewed these figures against the source',
                    ),
                    onChanged: (v) => update(() => reviewed = v!),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
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
              key: const Key('item-save'),
              onPressed: () {
                final item = buildItem();
                final issues = item.validation();
                if (issues.isNotEmpty) {
                  update(() => error = issues.join('\n'));
                  return;
                }
                Navigator.pop(context, item);
              },
              child: const Text('Save item'),
            ),
          ],
        ),
      ),
    );
    for (final controller in values.values) {
      controller.dispose();
    }
    if (result != null && _editable) {
      await _run(() async {
        if (_workspace!.revision == 0) await _store.saveWorkspace(_workspace!);
        await _store.saveItem(result);
      });
    }
  }

  Future<void> _voidItem(TaxWorkspaceItem item) async {
    if (!_editable) return;
    await _run(() async {
      await _store.saveItem(item.copyWith(isVoided: true));
    });
  }

  Future<void> _prefill() async {
    final workspace = _workspace;
    if (!_editable || workspace == null) return;
    final values = {
      for (final key in taxWorkspaceTotals)
        key: TextEditingController(text: workspace.prefill[key] ?? ''),
    };
    String? error;
    final result = await _showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Prefill comparison'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Optional comparison only. Leave absent fields blank; prefill never adds another income source.',
                  ),
                  for (final entry in values.entries)
                    TextField(
                      controller: entry.value,
                      decoration: InputDecoration(labelText: _label(entry.key)),
                    ),
                  if (error != null) Text(error!),
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
                final prefill = {
                  for (final entry in values.entries)
                    if (entry.value.text.trim().isNotEmpty)
                      entry.key: entry.value.text.trim(),
                };
                if (prefill.entries.any(
                  (e) => !workspaceMoney(e.value, signed: e.key == 'rentalNet'),
                )) {
                  update(
                    () => error =
                        'Use valid amounts with at most two decimal places.',
                  );
                  return;
                }
                Navigator.pop(context, prefill);
              },
              child: const Text('Save comparison'),
            ),
          ],
        ),
      ),
    );
    for (final controller in values.values) {
      controller.dispose();
    }
    if (result != null && _editable) {
      await _saveWorkspace(workspace.copyWith(prefill: result));
    }
  }

  Future<void> _residency({int? index}) async {
    final workspace = _workspace;
    if (!_editable || workspace == null) return;
    final existing = index == null ? null : workspace.residencyPeriods[index];
    final start = TextEditingController(
      text: existing?.start ?? '$_year-07-01',
    );
    final end = TextEditingController(
      text: existing?.endExclusive ?? '${_year + 1}-07-01',
    );
    final evidence = TextEditingController(text: existing?.evidence ?? '');
    var classification = existing?.classification ?? 'unknown';
    var reviewed = existing?.reviewed ?? false;
    String? error;
    final result = await _showDialog<ResidencyPeriod>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Tax residency period'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Tax residency and temporary resident treatment require evidence. Visa status alone does not decide either. End date is exclusive; include relevant investment holding history.',
                  ),
                  TextField(
                    controller: start,
                    onChanged: (_) => update(() => reviewed = false),
                    decoration: const InputDecoration(
                      labelText: 'Start YYYY-MM-DD',
                    ),
                  ),
                  TextField(
                    controller: end,
                    onChanged: (_) => update(() => reviewed = false),
                    decoration: const InputDecoration(
                      labelText: 'End exclusive YYYY-MM-DD',
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: classification,
                    items: ['resident', 'foreign', 'temporary', 'unknown']
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(_label(v)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => update(() {
                      classification = v!;
                      reviewed = false;
                    }),
                  ),
                  TextField(
                    controller: evidence,
                    onChanged: (_) => update(() => reviewed = false),
                    maxLength: 1000,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Evidence and tax determination reference',
                    ),
                  ),
                  CheckboxListTile(
                    value: reviewed,
                    title: const Text('Tax classification and period reviewed'),
                    onChanged: (v) => update(() => reviewed = v!),
                  ),
                  if (error != null) Text(error!),
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
                final value = ResidencyPeriod(
                  start: start.text.trim(),
                  endExclusive: end.text.trim(),
                  classification: classification,
                  evidence: evidence.text.trim(),
                  reviewed: reviewed,
                );
                final issues = value.validation();
                if (issues.isNotEmpty) {
                  update(() => error = issues.join('\n'));
                  return;
                }
                Navigator.pop(context, value);
              },
              child: const Text('Save period'),
            ),
          ],
        ),
      ),
    );
    start.dispose();
    end.dispose();
    evidence.dispose();
    if (result != null && _editable) {
      final periods = [...workspace.residencyPeriods];
      if (index == null) {
        periods.add(result);
      } else {
        periods[index] = result;
      }
      await _saveWorkspace(workspace.copyWith(residencyPeriods: periods));
    }
  }

  Future<void> _i1({int? index}) async {
    final workspace = _workspace;
    if (!_editable || workspace == null) return;
    final existing = index == null ? null : workspace.i1Reviews[index];
    final values = <String, TextEditingController>{
      'date': TextEditingController(
        text: existing?.date ?? '${_year + 1}-06-30',
      ),
      'assetReference': TextEditingController(
        text: existing?.assetReference ?? '',
      ),
      'marketValue': TextEditingController(text: existing?.marketValue ?? '0'),
      'costBase': TextEditingController(text: existing?.costBase ?? '0'),
      'reducedCostBase': TextEditingController(
        text: existing?.reducedCostBase ?? '0',
      ),
      'evidence': TextEditingController(text: existing?.evidence ?? ''),
      'adviserReference': TextEditingController(
        text: existing?.adviserReference ?? '',
      ),
    };
    final decisionValues = <String, TextEditingController>{
      'decisionReference': TextEditingController(
        text: existing?.adviserDecision?.decisionReference ?? '',
      ),
      'coveredAssets': TextEditingController(
        text: existing?.adviserDecision?.coveredAssets.join('\n') ?? '',
      ),
      'scopeEvidence': TextEditingController(
        text: existing?.adviserDecision?.scopeEvidence ?? '',
      ),
      'annualWorksheetReference': TextEditingController(
        text: existing?.adviserDecision?.annualWorksheetReference ?? '',
      ),
      'gain': TextEditingController(
        text: existing?.adviserDecision?.gain ?? '0',
      ),
      'loss': TextEditingController(
        text: existing?.adviserDecision?.loss ?? '0',
      ),
    };
    var includeDecision = existing?.adviserDecision != null;
    var discountFraction = existing?.adviserDecision?.discountFraction ?? '0';
    var classification = existing?.classification ?? 'unknown';
    var election = existing?.election ?? 'undecided';
    var reviewed = existing?.reviewed ?? false;
    String? error;
    final result = await _showDialog<I1Review>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('I1 transition review and scenarios'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Record an evidenced ceasing-residency event, asset exceptions and valuation. Deferral covers all eligible assets at the event. Include a documented adviser decision only after confirming its complete asset scope and annual CGT treatment.',
                  ),
                  for (final entry in values.entries)
                    TextField(
                      controller: entry.value,
                      maxLength: 1000,
                      onChanged: (_) => update(() => reviewed = false),
                      decoration: InputDecoration(labelText: _label(entry.key)),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: classification,
                    decoration: const InputDecoration(
                      labelText: 'Asset classification',
                    ),
                    items:
                        [
                              'unknown',
                              'nonTAP',
                              'tapExcluded',
                              'preCGT',
                              'temporaryResident',
                            ]
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(_label(v)),
                              ),
                            )
                            .toList(),
                    onChanged: (v) => update(() {
                      classification = v!;
                      reviewed = false;
                    }),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: election,
                    decoration: const InputDecoration(
                      labelText: 'Event-wide election review',
                    ),
                    items: ['undecided', 'recognise', 'deferAllEligible']
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(_label(v)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => update(() {
                      election = v!;
                      reviewed = false;
                    }),
                  ),
                  CheckboxListTile(
                    value: includeDecision,
                    title: const Text('Include documented adviser decision'),
                    onChanged: (v) => update(() {
                      includeDecision = v!;
                      reviewed = false;
                    }),
                  ),
                  if (includeDecision) ...[
                    const Text(
                      'Enter assessed amounts before losses and the discount. Covered assets must list every eligible asset at this event, one reference per line. The annual worksheet must include this decision exactly once.',
                    ),
                    for (final entry in decisionValues.entries)
                      TextField(
                        controller: entry.value,
                        maxLength: entry.key == 'coveredAssets' ? null : 1000,
                        maxLines:
                            entry.key == 'coveredAssets' ||
                                entry.key == 'scopeEvidence'
                            ? 3
                            : 1,
                        onChanged: (_) => update(() => reviewed = false),
                        decoration: InputDecoration(
                          labelText: switch (entry.key) {
                            'gain' =>
                              'Adviser assessed gain AUD (before discount)',
                            'loss' => 'Adviser assessed loss AUD',
                            'coveredAssets' =>
                              'All covered eligible asset references',
                            _ => _label(entry.key),
                          },
                        ),
                      ),
                    DropdownButtonFormField<String>(
                      initialValue: discountFraction,
                      decoration: const InputDecoration(
                        labelText: 'Adviser assessed discount',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: '0',
                          child: Text('No discount'),
                        ),
                        DropdownMenuItem(
                          value: '0.5',
                          child: Text('50% discount'),
                        ),
                      ],
                      onChanged: (v) => update(() {
                        discountFraction = v!;
                        reviewed = false;
                      }),
                    ),
                  ],
                  CheckboxListTile(
                    value: reviewed,
                    title: const Text(
                      'Adviser reviewed event, valuation and election scope',
                    ),
                    onChanged: (v) => update(() => reviewed = v!),
                  ),
                  if (error != null) Text(error!),
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
                final value = I1Review(
                  date: values['date']!.text.trim(),
                  assetReference: values['assetReference']!.text.trim(),
                  marketValue: values['marketValue']!.text.trim(),
                  costBase: values['costBase']!.text.trim(),
                  reducedCostBase: values['reducedCostBase']!.text.trim(),
                  classification: classification,
                  election: election,
                  evidence: values['evidence']!.text.trim(),
                  adviserReference: values['adviserReference']!.text.trim(),
                  reviewed: reviewed,
                  adviserDecision: includeDecision
                      ? I1AdviserDecision.fromMap({
                          'decisionReference':
                              decisionValues['decisionReference']!.text.trim(),
                          'coveredAssets': decisionValues['coveredAssets']!.text
                              .split('\n')
                              .map((v) => v.trim())
                              .where((v) => v.isNotEmpty)
                              .toList(),
                          'scopeEvidence': decisionValues['scopeEvidence']!.text
                              .trim(),
                          'annualWorksheetReference':
                              decisionValues['annualWorksheetReference']!.text
                                  .trim(),
                          'gain': decisionValues['gain']!.text.trim(),
                          'loss': decisionValues['loss']!.text.trim(),
                          'discountFraction': discountFraction,
                          'ruleVersion': TaxRuleRegistry.version(_year),
                        })
                      : null,
                );
                final issues = value.validation();
                if (issues.isNotEmpty) {
                  update(() => error = issues.join('\n'));
                  return;
                }
                Navigator.pop(context, value);
              },
              child: const Text('Save review'),
            ),
          ],
        ),
      ),
    );
    for (final controller in [...values.values, ...decisionValues.values]) {
      controller.dispose();
    }
    if (result != null && _editable) {
      final reviews = [...workspace.i1Reviews];
      if (index == null) {
        reviews.add(result);
      } else {
        reviews[index] = result;
      }
      await _saveWorkspace(workspace.copyWith(i1Reviews: reviews));
    }
  }

  Future<void> _exportReport({String format = 'json'}) async {
    final bundle = _bundle;
    if (!_authorised || _stale || _report == null || bundle == null) return;
    if (_generation != await _store.getGeneration(_owner!) ||
        _investmentGeneration !=
            await _sources.getInvestmentLedgerGeneration(_owner!)) {
      if (mounted) {
        setState(() {
          _stale = true;
          _report = null;
        });
      }
      return;
    }
    if (!_authorised) return;
    if (format == 'pdf') {
      await saveBinaryFile(
        'tax-workpaper-$_year-${_year + 1}.pdf',
        AccountantWorkpaperExport().pdf(bundle),
      );
    } else if (format == 'csv') {
      await saveTextFile(
        'tax-workpaper-$_year-${_year + 1}.csv',
        AccountantWorkpaperExport().csv(bundle),
      );
    } else {
      await saveTextFile(
        'tax-workpaper-$_year-${_year + 1}.json',
        _coordinator.exportWorksheet(bundle),
      );
    }
  }

  Future<void> _exportBackup() async {
    final bundle = _bundle;
    if (!_authorised || _stale || bundle == null || _busy) return;
    setState(() => _busy = true);
    try {
      final text = await _coordinator.exportBackup(bundle);
      if (_authorised) {
        await saveTextFile('tax-workspace-backup-$_year.json', text);
      }
    } catch (_) {
      _message(
        'Sources changed or backup could not be created. Reload and retry.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    if (!_authorised || _busy) return;
    setState(() => _busy = true);
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (!_authorised || selection == null) return;
      final file = selection.files.single;
      final bytes = file.bytes;
      if (bytes == null || file.size > 32 * 1024 * 1024) {
        _message('Choose a JSON backup smaller than 32 MB.');
        return;
      }
      final year = await _coordinator.restoreBackup(
        _owner!,
        utf8.decode(bytes),
      );
      if (!_authorised || !mounted) return;
      setState(() => _year = year);
      _subscribe();
      await _load();
      _message(
        'Restored as an unreviewed draft. Review source links before finalising.',
      );
    } catch (_) {
      _message(
        'Backup could not be restored completely. Check its owner, schema and destination; interrupted drafts can resume from the same file.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _cgtLabel(Map<String, dynamic> snapshot) {
    final annual = snapshot['annualCgt'] as Map? ?? snapshot;
    return '${annual['year'] ?? ''} · ${annual['status'] ?? 'Unreviewed'} · ${snapshot['ledgerGeneration'] == _investmentGeneration ? 'current' : 'stale'}';
  }

  String _snapshotStatus(Map<String, dynamic> snapshot) {
    if (snapshot['kind'] == 'backup-source-audit' ||
        snapshot['kind'] == 'imported') {
      return 'Imported archive · unreviewed historical evidence';
    }
    final savedReport = (snapshot['payload'] as Map?)?['report'] as Map?;
    final current = _bundle?.report.sourceFingerprint;
    return !_stale &&
            current != null &&
            savedReport?['sourceFingerprint'] == current
        ? 'Immutable workpaper · matches current sources'
        : 'Immutable workpaper · stale or current sources not verified';
  }

  static String _label(String value) => value
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase());

  Widget _card(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final workspace = _workspace;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal tax workpaper'),
        actions: [
          IconButton(
            key: const Key('workspace-reload'),
            onPressed: _busy ? null : _load,
            tooltip: 'Reload sources',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !_authorised
          ? const Center(
              child: Text('Sign in again to access your tax workspace.'),
            )
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'For review only. This workpaper does not calculate complete income tax liability or lodge a return.',
                ),
                const Text(
                  'Enter AUD amounts from reviewed evidence. Other currencies and unsupported tax treatments require separate review.',
                ),
                const Text(
                  'This is an estimate only and does not constitute tax advice. Please confirm with a qualified accountant or tax adviser.',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const Key('workspace-year'),
                  initialValue: _year,
                  decoration: const InputDecoration(
                    labelText: 'Financial year',
                  ),
                  items: TaxRuleRegistry.supportedYearStarts
                      .map(
                        (y) => DropdownMenuItem(
                          value: y,
                          child: Text('$y-${y + 1}'),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (y) {
                          if (y != null && y != _year) {
                            setState(() {
                              _year = y;
                              _workspace = null;
                              _report = null;
                            });
                            _subscribe();
                            _load();
                          }
                        },
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_stale)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Sources changed. Reload before calculating, editing or exporting.',
                    ),
                  ),
                if (workspace != null) ...[
                  Text(
                    '${_label(workspace.status)} · revision ${workspace.revision}',
                  ),
                  if (workspace.status == 'finalised')
                    FilledButton(
                      onPressed: _busy ? null : _amend,
                      child: const Text('Amend with reason'),
                    ),
                  _card('Section review', [
                    for (final section in taxWorkspaceSections)
                      ListTile(
                        key: ValueKey('section-$section'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(_label(section)),
                        subtitle: Text(
                          '${_label(workspace.sectionStates[section] ?? 'notStarted')}\n${workspace.sectionEvidence[section] ?? ''}',
                        ),
                        trailing: IconButton(
                          onPressed: _editable ? () => _section(section) : null,
                          icon: const Icon(Icons.edit),
                        ),
                      ),
                  ]),
                  _card('Manual source items', [
                    const Text(
                      'Salary, interest, dividends, other income, deductions and offsets need their own evidence. Fund income and rental totals are loaded from linked sources.',
                    ),
                    FilledButton(
                      key: const Key('workspace-add-item'),
                      onPressed: _editable ? () => _item() : null,
                      child: const Text('Add source item'),
                    ),
                    for (final item in _items.where((i) => !i.isVoided))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${_label(item.category)} · ${item.sourceReference}',
                        ),
                        subtitle: Text(
                          '${item.isReviewed ? 'Reviewed' : 'Needs review'} · amount ${item.amount} · revision ${item.revision}',
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: 'Edit item',
                              onPressed: _editable
                                  ? () => _item(existing: item)
                                  : null,
                              icon: const Icon(Icons.edit),
                            ),
                            IconButton(
                              tooltip: 'Void item',
                              onPressed: _editable
                                  ? () => _voidItem(item)
                                  : null,
                              icon: const Icon(Icons.archive_outlined),
                            ),
                          ],
                        ),
                      ),
                  ]),
                  _card('Rental contributions', [
                    const Text(
                      'Select each property explicitly. Review current amounts, tax deductibility and your ownership share; existing rental worksheets remain unchanged.',
                    ),
                    for (final rental in _rentals)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(rental.propertyName),
                        subtitle: Text(
                          '${rental.financialYear} · net ${rental.netPosition.toStringAsFixed(2)}',
                        ),
                        trailing: TextButton(
                          onPressed: _editable
                              ? () => _item(
                                  rental: rental,
                                  existing: _items
                                      .where(
                                        (i) =>
                                            !i.isVoided &&
                                            i.rentalRecordId == rental.id,
                                      )
                                      .firstOrNull,
                                )
                              : null,
                          child: const Text('Review share'),
                        ),
                      ),
                    if (_rentals.isEmpty)
                      const Text('No rental records for this year.'),
                  ]),
                  _card('Fund and CGT sources', [
                    const Text(
                      'Reviewed fund statement income and credits enter once. Attributed capital gains enter through the selected annual CGT workpaper only.',
                    ),
                    Text(
                      '${_funds.where((s) => s.yearStart == _year && !s.isVoided).length} fund statements for this year. Source gaps still require review.',
                    ),
                    DropdownButtonFormField<String>(
                      key: const Key('workspace-cgt'),
                      initialValue:
                          _cgt.any((s) => s['id'] == workspace.cgtSnapshotId)
                          ? workspace.cgtSnapshotId
                          : '',
                      decoration: const InputDecoration(
                        labelText: 'Annual CGT snapshot',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('No snapshot selected'),
                        ),
                        for (final s in _cgt)
                          DropdownMenuItem(
                            value: s['id'] as String,
                            child: Text(_cgtLabel(s)),
                          ),
                      ],
                      onChanged: _editable
                          ? (id) {
                              if (id != null) {
                                _saveWorkspace(
                                  workspace.copyWith(cgtSnapshotId: id),
                                );
                              }
                            }
                          : null,
                    ),
                  ]),
                  _card('Residency timeline', [
                    const Text(
                      'Use evidenced tax residency periods, including relevant investment history. Unknown, temporary or foreign treatment needs specialist review.',
                    ),
                    for (var i = 0; i < workspace.residencyPeriods.length; i++)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${workspace.residencyPeriods[i].start} to ${workspace.residencyPeriods[i].endExclusive} (exclusive)',
                        ),
                        subtitle: Text(
                          '${_label(workspace.residencyPeriods[i].classification)} · ${workspace.residencyPeriods[i].reviewed ? 'reviewed' : 'unreviewed'}',
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              onPressed: _editable
                                  ? () => _residency(index: i)
                                  : null,
                              icon: const Icon(Icons.edit),
                            ),
                            IconButton(
                              onPressed: _editable
                                  ? () {
                                      final periods = [
                                        ...workspace.residencyPeriods,
                                      ]..removeAt(i);
                                      _saveWorkspace(
                                        workspace.copyWith(
                                          residencyPeriods: periods,
                                        ),
                                      );
                                    }
                                  : null,
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          ],
                        ),
                      ),
                    TextButton(
                      key: const Key('workspace-add-residency'),
                      onPressed: _editable ? () => _residency() : null,
                      child: const Text('Add residency period'),
                    ),
                  ]),
                  _card('I1 residency transition review', [
                    const Text(
                      'Scenarios are provisional and separate from annual totals. Confirm exceptions, valuation and the event-wide election with your adviser.',
                    ),
                    for (var i = 0; i < workspace.i1Reviews.length; i++)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${workspace.i1Reviews[i].date} · ${workspace.i1Reviews[i].assetReference}',
                        ),
                        subtitle: Text(
                          '${_label(workspace.i1Reviews[i].classification)} · ${_label(workspace.i1Reviews[i].election)}',
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              onPressed: _editable ? () => _i1(index: i) : null,
                              icon: const Icon(Icons.edit),
                            ),
                            IconButton(
                              onPressed: _editable
                                  ? () {
                                      final reviews = [...workspace.i1Reviews]
                                        ..removeAt(i);
                                      _saveWorkspace(
                                        workspace.copyWith(i1Reviews: reviews),
                                      );
                                    }
                                  : null,
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          ],
                        ),
                      ),
                    TextButton(
                      key: const Key('workspace-add-i1'),
                      onPressed: _editable ? () => _i1() : null,
                      child: const Text('Add I1 review'),
                    ),
                  ]),
                  _card('Prefill reconciliation', [
                    const Text(
                      'Compare category totals with prefill. Differences require review and do not replace the source facts.',
                    ),
                    Text(
                      '${workspace.prefill.length} comparison values recorded',
                    ),
                    TextButton(
                      onPressed: _editable ? _prefill : null,
                      child: const Text('Edit prefill comparison'),
                    ),
                  ]),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        key: const Key('workspace-calculate'),
                        onPressed: _busy || _stale ? null : _calculate,
                        child: const Text('Calculate workpaper'),
                      ),
                      FilledButton(
                        key: const Key('workspace-finalise'),
                        onPressed: _editable && (_report?.canFinalise ?? false)
                            ? _finalise
                            : null,
                        child: const Text('Finalise reviewed revision'),
                      ),
                      OutlinedButton(
                        onPressed: _report != null && !_stale && !_busy
                            ? _exportReport
                            : null,
                        child: const Text('Export workpaper JSON'),
                      ),
                      for (final format in ['csv', 'pdf'])
                        OutlinedButton(
                          onPressed: _report != null && !_stale && !_busy
                              ? () => _exportReport(format: format)
                              : null,
                          child: Text(
                            'Export accountant ${format.toUpperCase()}',
                          ),
                        ),
                      OutlinedButton(
                        onPressed: !_busy
                            ? () => Navigator.pushNamed(context, '/documents')
                            : null,
                        child: const Text('Document inventory'),
                      ),
                      OutlinedButton(
                        onPressed: !_stale && !_busy ? _exportBackup : null,
                        child: const Text('Export workspace backup'),
                      ),
                      OutlinedButton(
                        onPressed: !_busy ? _restoreBackup : null,
                        child: const Text('Restore draft backup'),
                      ),
                    ],
                  ),
                  if (_report case final report?)
                    _card(
                      report.canFinalise
                          ? 'Ready for review finalisation'
                          : 'Needs tax review',
                      [
                        for (final entry in report.categoryTotals.entries)
                          Text('${_label(entry.key)}: ${entry.value}'),
                        const SizedBox(height: 12),
                        for (final issue in report.issues) Text('• $issue'),
                        for (final scenario in report.i1Scenarios)
                          ExpansionTile(
                            title: const Text('Provisional I1 scenario'),
                            children: [
                              for (final entry in scenario.entries)
                                if (entry.value is! Map && entry.value is! List)
                                  Text('${_label(entry.key)}: ${entry.value}'),
                            ],
                          ),
                        ExpansionTile(
                          title: const Text('Calculation source provenance'),
                          children: [
                            SelectableText(
                              const JsonEncoder.withIndent(
                                '  ',
                              ).convert(report.toMap()),
                            ),
                          ],
                        ),
                      ],
                    ),
                  _card('Saved finalised revisions', [
                    if (_snapshots.isEmpty)
                      const Text('No finalised workpaper revisions saved.'),
                    for (final snapshot in _snapshots)
                      ExpansionTile(
                        title: Text(
                          'Revision ${snapshot['workspaceRevision'] ?? ''} · ${snapshot['createdAt'] ?? ''}',
                        ),
                        subtitle: Text(_snapshotStatus(snapshot)),
                        children: [
                          SelectableText(
                            JsonEncoder.withIndent(
                              '  ',
                              (value) => value.toString(),
                            ).convert(snapshot),
                          ),
                        ],
                      ),
                  ]),
                ],
              ],
            ),
    );
  }
}
