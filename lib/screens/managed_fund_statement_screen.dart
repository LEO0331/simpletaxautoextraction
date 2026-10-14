import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../models/managed_fund_statement.dart';
import '../models/investment_transaction.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/managed_fund_pdf_service.dart';
import '../services/parsers/managed_fund_statement_parser.dart';

/// Reviewed manual/local PDF drafts; original documents are never uploaded.
class ManagedFundStatementScreen extends StatefulWidget {
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final ManagedFundPdfService? pdfService;
  const ManagedFundStatementScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.pdfService,
  });

  @override
  State<ManagedFundStatementScreen> createState() =>
      _ManagedFundStatementScreenState();
}

class _ManagedFundStatementScreenState
    extends State<ManagedFundStatementScreen> {
  late final AuthService _auth;
  late final FirestoreService _store;
  String? _owner;
  StreamSubscription<dynamic>? _authChanges;
  List<ManagedFundStatement> _statements = [];
  bool _loading = true;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _auth = widget.authService ?? AuthService();
    _store = widget.firestoreService ?? FirestoreService();
    _owner = _auth.currentUser?.uid;
    _authChanges = _auth.authStateChanges.listen((user) {
      if (mounted && user?.uid != _owner) {
        setState(() {
          _statements = [];
          _error = null;
          _loading = false;
        });
      }
    });
    _load();
  }

  bool get _signedIn => _owner != null && _auth.currentUser?.uid == _owner;

  Future<void> _load() async {
    if (!_signedIn) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final statements = await _store.getManagedFundStatementsOnce(
        _owner!,
        includeVoided: true,
      );
      if (!mounted || !_signedIn) return;
      statements.sort((a, b) => b.yearStart.compareTo(a.yearStart));
      setState(() {
        _statements = statements;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted && _signedIn) {
        setState(() {
          _loading = false;
          _error = 'Unable to load statements. Try again.';
        });
      }
    }
  }

  Future<void> _edit([
    ManagedFundStatement? statement,
    ManagedFundExtractionResult? extraction,
  ]) async {
    if (!_signedIn) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _StatementEditor(
          owner: _owner!,
          auth: _auth,
          store: _store,
          statement: statement,
          extraction: extraction,
        ),
      ),
    );
    if (mounted && _signedIn) await _load();
  }

  Future<void> _importPdf() async {
    if (!_signedIn || _importing) return;
    setState(() => _importing = true);
    final pages = TextEditingController();
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (!mounted || !_signedIn || selected == null) return;
      final bytes = selected.files.single.bytes;
      if (bytes == null || bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
        throw const FormatException();
      }
      final range = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select annual statement pages'),
          content: TextField(
            key: const Key('fund-pdf-pages'),
            controller: pages,
            decoration: const InputDecoration(
              labelText: 'PDF pages, e.g. 1-2 or 3',
              helperText:
                  'Include summary and components of ONE statement. Up to five pages. Blank uses the whole PDF.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('parse-fund-pdf'),
              onPressed: () => Navigator.pop(context, pages.text.trim()),
              child: const Text('Extract locally'),
            ),
          ],
        ),
      );
      if (!mounted || !_signedIn || range == null) return;
      int? first, last;
      if (range.isNotEmpty) {
        final match = RegExp(r'^(\d+)(?:\s*-\s*(\d+))?$').firstMatch(range);
        if (match == null) throw const FormatException();
        first = int.parse(match[1]!);
        last = int.parse(match[2] ?? match[1]!);
      }
      final extraction = await (widget.pdfService ?? ManagedFundPdfService())
          .extract(bytes, userId: _owner!, firstPage: first, lastPage: last);
      if (!mounted || !_signedIn) return;
      await _edit(extraction.draft, extraction);
    } catch (_) {
      if (mounted && _signedIn) {
        setState(
          () => _error =
              'Unable to extract these pages. Select one statement (up to five pages, PDF under 10 MB) or enter it manually.',
        );
      }
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      pages.dispose();
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  void dispose() {
    _authChanges?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Managed fund statements'),
      actions: [
        IconButton(
          onPressed: _signedIn ? _load : null,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
    ),
    floatingActionButton: _signedIn
        ? FloatingActionButton.extended(
            key: const Key('add-fund-statement'),
            onPressed: _edit,
            icon: const Icon(Icons.add),
            label: const Text('Add statement'),
          )
        : null,
    body: !_signedIn
        ? const Center(child: Text('Please sign in again.'))
        : _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              const Text(
                'Enter the reviewed annual statement for each fund, account and financial year. Keep private PDFs locally. Corrections preserve earlier revisions and invalidate calculations.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('import-fund-pdf'),
                onPressed: _importing ? null : _importPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: Text(
                  _importing
                      ? 'Extracting locally…'
                      : 'Import fund statement PDF (local)',
                ),
              ),
              const Text(
                'This is an estimate only and does not constitute tax advice. Please confirm with a qualified accountant or tax adviser.',
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_statements.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No managed fund statements yet.'),
                ),
              for (final statement in _statements)
                Card(
                  child: ListTile(
                    title: Text(
                      '${statement.ticker} · ${statement.yearStart}–${statement.yearStart + 1}',
                    ),
                    subtitle: Text(
                      '${statement.issuer} · ${statement.accountNumber}\n${statement.isVoided
                          ? 'Voided'
                          : statement.isReviewed
                          ? 'Reviewed'
                          : 'NeedsTaxReview'} · revision ${statement.revision}\nSource: ${statement.sourceReference}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.edit),
                    onTap: () => _edit(statement),
                  ),
                ),
            ],
          ),
  );
}

const _labels = <String, String>{
  'australianIncome': 'Australian income',
  'foreignIncome': 'Foreign income',
  'frankingCredits': 'Franking credits',
  'foreignTaxOffset': 'Foreign income tax offset',
  'withholding': 'Tax withheld',
  'cashDistributions': 'Cash distributions (including DRP)',
  'discountedCapitalGain':
      'Discounted capital gain component (before gross-up)',
  'otherCapitalGain': 'Other capital gain component',
  'grossCapitalGain': 'Total gross capital gains',
  'amitShortfall': 'AMIT cost-base net shortfall (increase)',
  'amitExcess': 'AMIT cost-base net excess (decrease)',
};

class _StatementEditor extends StatefulWidget {
  final String owner;
  final AuthService auth;
  final FirestoreService store;
  final ManagedFundStatement? statement;
  final ManagedFundExtractionResult? extraction;
  const _StatementEditor({
    required this.owner,
    required this.auth,
    required this.store,
    this.statement,
    this.extraction,
  });
  @override
  State<_StatementEditor> createState() => _StatementEditorState();
}

class _StatementEditorState extends State<_StatementEditor> {
  final _fields = <String, TextEditingController>{};
  final _components = <String, TextEditingController>{};
  List<FundCostBaseAdjustment> _adjustments = [];
  List<FundDrpLink> _drp = [];
  String _regime = 'AMIT';
  bool _reviewed = false, _voided = false, _saving = false;
  String? _error;
  List<Map<String, dynamic>>? _revisions;
  List<InvestmentTransaction> _references = [];
  bool _referencesLoading = true;
  bool _referencesFailed = false;
  bool _dialogOpen = false;
  StreamSubscription<dynamic>? _authChanges;
  bool get _signedIn => widget.auth.currentUser?.uid == widget.owner;

  @override
  void initState() {
    super.initState();
    final s = widget.statement;
    final initial = {
      'ticker': s?.ticker ?? '',
      'accountNumber': s?.accountNumber ?? '',
      'issuer': s?.issuer ?? '',
      'layoutVersion': s?.layoutVersion ?? '',
      'yearStart': s?.yearStart == 0 ? '' : '${s?.yearStart ?? 2025}',
      'sourceReference': s?.sourceReference ?? '',
    };
    for (final e in initial.entries) {
      _fields[e.key] = TextEditingController(text: e.value);
    }
    for (final key in ManagedFundStatement.allComponentKeys) {
      _components[key] = TextEditingController(text: s?.components[key] ?? '0');
    }
    _adjustments = [...?s?.adjustments];
    _drp = [...?s?.drpLinks];
    _regime = s?.regime == 'non-AMIT' ? 'NON_AMIT' : s?.regime ?? 'AMIT';
    _voided = s?.isVoided ?? false;
    // Any correction must be deliberately reviewed again.
    _authChanges = widget.auth.authStateChanges.listen((_) {
      if (mounted && !_signedIn) {
        if (_dialogOpen) Navigator.of(context).pop();
        for (final c in [..._fields.values, ..._components.values]) {
          c.clear();
        }
        setState(() {
          _adjustments.clear();
          _drp.clear();
          _revisions = null;
          _references = [];
          _error = null;
        });
      }
    });
    _loadReferences();
  }

  Future<void> _loadReferences() async {
    try {
      final references = await widget.store.getInvestmentTransactionsOnce(
        widget.owner,
      );
      if (!mounted || !_signedIn) return;
      setState(() {
        _references = references
            .where((t) => t.isReviewed && !t.isVoided)
            .toList();
        _referencesLoading = false;
        _referencesFailed = false;
      });
    } catch (_) {
      if (mounted && _signedIn) {
        setState(() {
          _referencesLoading = false;
          _referencesFailed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _authChanges?.cancel();
    for (final c in [..._fields.values, ..._components.values]) {
      c.dispose();
    }
    super.dispose();
  }

  ManagedFundStatement _draft() => ManagedFundStatement(
    id: widget.statement?.id,
    userId: widget.owner,
    ticker: _fields['ticker']!.text.trim().toUpperCase(),
    accountNumber: _fields['accountNumber']!.text.trim(),
    issuer: _fields['issuer']!.text.trim(),
    layoutVersion: _fields['layoutVersion']!.text.trim(),
    yearStart: int.tryParse(_fields['yearStart']!.text) ?? 0,
    sourceReference: _fields['sourceReference']!.text.trim(),
    regime: _regime,
    revision: widget.statement?.revision ?? 0,
    isReviewed: _reviewed,
    isVoided: _voided,
    components: {
      for (final e in _components.entries)
        if (_regime == 'NON_AMIT' ||
            ManagedFundStatement.componentKeys.contains(e.key))
          e.key: e.value.text.trim(),
    },
    adjustments: [..._adjustments],
    drpLinks: [..._drp],
  );

  List<String> _structuralIssues(ManagedFundStatement draft) {
    bool text(String value, int limit) =>
        value.trim().isNotEmpty && value.length <= limit;
    final money = RegExp(r'^[0-9]{1,30}(\.[0-9]{1,2})?$');
    final signedMoney = RegExp(r'^-?[0-9]{1,30}(\.[0-9]{1,2})?$');
    final units = RegExp(r'^[0-9]{1,30}(\.[0-9]{1,12})?$');
    final issues = <String>[];
    if (!text(draft.ticker, 16) ||
        !text(draft.accountNumber, 64) ||
        !text(draft.issuer, 180) ||
        !text(draft.layoutVersion, 64) ||
        !text(draft.sourceReference, 1000) ||
        draft.yearStart < 1900 ||
        draft.yearStart > 2199) {
      issues.add(
        'Statement identity, issuer, layout, year and source are required within field limits',
      );
    }
    if (draft.components.values.any((value) => !money.hasMatch(value))) {
      issues.add(
        'Statement amounts must be nonnegative AUD decimals with at most two decimal places',
      );
    }
    for (final adjustment in draft.adjustments) {
      if (!text(adjustment.parcelId, 128) ||
          !text(adjustment.evidenceReference, 1000) ||
          !signedMoney.hasMatch(adjustment.amount) ||
          (adjustment.reducedAmount != null &&
              !signedMoney.hasMatch(adjustment.reducedAmount!)) ||
          (adjustment.beforeSaleId != null &&
              !text(adjustment.beforeSaleId!, 128)) ||
          (adjustment.units != null && !units.hasMatch(adjustment.units!))) {
        issues.add('Adjustment references and decimal amounts must be valid');
      }
      try {
        parseFundDate(adjustment.date);
      } on FormatException {
        issues.add('Adjustment date must be a valid YYYY-MM-DD date');
      }
    }
    for (final link in draft.drpLinks) {
      if (!text(link.buyTransactionId, 128) ||
          !text(link.evidenceReference, 1000) ||
          ![
            link.cashEntitlement,
            link.reinvestedAmount,
            link.residualCash,
          ].every(money.hasMatch)) {
        issues.add(
          'DRP references and nonnegative AUD decimal amounts must be valid',
        );
      }
    }
    return issues;
  }

  Future<void> _save() async {
    if (!_signedIn || _saving) return;
    final draft = _draft();
    final issues = _structuralIssues(draft);
    if (_reviewed && !_voided) issues.addAll(draft.validation());
    if (issues.isNotEmpty) {
      setState(() => _error = issues.join('\n'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.saveManagedFundStatement(draft);
      if (mounted && _signedIn) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted && _signedIn) {
        setState(
          () => _error =
              'Unable to save. Refresh the statement before correcting it; check source references and linked acquisitions.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Map<String, String>?> _rowDialog(
    String title,
    Map<String, String> labels, {
    Map<String, dynamic>? initial,
  }) async {
    final controllers = {
      for (final key in labels.keys)
        key: TextEditingController(text: '${initial?[key] ?? ''}'),
    };
    _dialogOpen = true;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in labels.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      key: ValueKey('row-${e.key}'),
                      controller: controllers[e.key],
                      decoration: InputDecoration(labelText: e.value),
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
          ElevatedButton(
            onPressed: () => Navigator.pop(context, {
              for (final e in controllers.entries) e.key: e.value.text.trim(),
            }),
            child: const Text('Keep row'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    // Controllers are owned until the dialog's exit animation completes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final c in controllers.values) {
      c.dispose();
    }
    return result;
  }

  Future<void> _adjustment([int? index]) async {
    final row = await _rowDialog('Cost-base adjustment', {
      'parcelId': 'Acquisition transaction ID',
      'amount': _regime == 'NON_AMIT'
          ? 'Cost-base change: negative tax-deferred amount'
          : 'Signed AUD amount: shortfall positive, excess negative',
      if (_regime == 'NON_AMIT')
        'reducedAmount': 'Reduced basis change: negative deferred + tax-free',
      'date': 'Effective date (YYYY-MM-DD)',
      'units': 'Evidenced interest units',
      'evidenceReference': 'Allocation evidence reference',
      'beforeSaleId': 'Sale transaction ID (blank for year end)',
    }, initial: index == null ? null : _adjustments[index].toMap());
    if (row == null || !mounted || !_signedIn) return;
    final value = FundCostBaseAdjustment(
      parcelId: row['parcelId']!,
      amount: row['amount']!,
      reducedAmount: _regime == 'NON_AMIT' ? row['reducedAmount'] : null,
      date: row['date']!,
      units: row['units'],
      evidenceReference: row['evidenceReference']!,
      beforeSaleId: row['beforeSaleId']!.isEmpty ? null : row['beforeSaleId'],
    );
    setState(() {
      if (index == null) {
        _adjustments.add(value);
      } else {
        _adjustments[index] = value;
      }
      _reviewed = false;
    });
  }

  Future<void> _drpLink([int? index]) async {
    final row = await _rowDialog('Link existing DRP acquisition', const {
      'buyTransactionId': 'Existing reviewed BUY transaction ID',
      'cashEntitlement': 'Cash entitlement (AUD)',
      'reinvestedAmount': 'Reinvested amount (AUD)',
      'residualCash': 'Residual cash (AUD)',
      'evidenceReference': 'DRP evidence reference',
    }, initial: index == null ? null : _drp[index].toMap());
    if (row == null || !mounted || !_signedIn) return;
    final value = FundDrpLink.fromMap(row);
    setState(() {
      if (index == null) {
        _drp.add(value);
      } else {
        _drp[index] = value;
      }
      _reviewed = false;
    });
  }

  Future<void> _history() async {
    if (!_signedIn || widget.statement?.id == null) return;
    try {
      final revisions = await widget.store.getManagedFundStatementRevisionsOnce(
        widget.owner,
        widget.statement!.id!,
      );
      if (!mounted || !_signedIn) return;
      setState(() => _revisions = revisions);
    } catch (_) {
      if (mounted && _signedIn) {
        setState(() => _error = 'Unable to load revision history. Try again.');
      }
    }
  }

  Widget _field(String key, String label, {bool enabled = true}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: ValueKey('fund-$key'),
      controller: _fields[key] ?? _components[key],
      enabled: enabled && !_saving,
      onChanged: (_) => setState(() => _reviewed = false),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.statement?.id == null
            ? 'Add annual fund statement'
            : 'Correct annual fund statement',
      ),
    ),
    body: !_signedIn
        ? const Center(child: Text('Please sign in again.'))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.extraction != null) ...[
                const Text(
                  'PDF extraction draft — review required. The original PDF remains on this device.',
                ),
                for (final warning in widget.extraction!.warnings)
                  Text(warning),
                Text(
                  'Enter or explicitly confirm missing fields: ${widget.extraction!.missingFields.join(', ')}',
                ),
                ExpansionTile(
                  title: const Text('Extracted field locations'),
                  children: [
                    for (final reference
                        in widget.extraction!.fieldEvidence.values)
                      Text(reference),
                  ],
                ),
              ],
              if (widget.statement?.id != null)
                Text(
                  'Current revision ${widget.statement!.revision}. Saving a correction retains the previous facts.',
                ),
              _field(
                'ticker',
                'Fund ticker',
                enabled: widget.statement?.id == null,
              ),
              _field(
                'accountNumber',
                'Account reference',
                enabled: widget.statement?.id == null,
              ),
              _field(
                'issuer',
                'Statement issuer',
                enabled: widget.statement?.id == null,
              ),
              _field(
                'yearStart',
                'Financial year start (e.g. 2025 for 2025–2026)',
                enabled: widget.statement?.id == null,
              ),
              _field('layoutVersion', 'Issuer statement layout / version'),
              _field(
                'sourceReference',
                'Source document reference (no private identifiers)',
              ),
              DropdownButtonFormField<String>(
                initialValue: _regime,
                decoration: const InputDecoration(labelText: 'Fund regime'),
                items: const [
                  DropdownMenuItem(value: 'AMIT', child: Text('AMIT')),
                  DropdownMenuItem(value: 'NON_AMIT', child: Text('Non-AMIT')),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                        _regime = v!;
                        _reviewed = false;
                      }),
              ),
              if (_regime == 'NON_AMIT')
                const Text(
                  'Record evidenced tax-deferred and tax-free payments separately. Tax-deferred amounts reduce both bases; tax-free amounts reduce the reduced basis. Tax-exempt amounts do not reduce either basis.',
                ),
              const SizedBox(height: 16),
              const Text(
                'Statement components · AUD',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text(
                'Use the statement component labels, not prefill or net totals. Gross capital gains must equal twice the discounted component plus other gains.',
              ),
              for (final key in ManagedFundStatement.componentKeys)
                _field(key, _labels[key] ?? key),
              if (_regime == 'NON_AMIT')
                for (final key in ManagedFundStatement.nonAmitComponentKeys)
                  _field(key, key),
              ExpansionTile(
                key: const Key('fund-transaction-references'),
                title: const Text('Existing reviewed transaction references'),
                subtitle: const Text(
                  'Copy acquisition and sale IDs for adjustment and DRP links, including historical sold parcels.',
                ),
                children: [
                  if (_referencesLoading)
                    const Text('Loading transaction references…'),
                  if (_referencesFailed)
                    const Text(
                      'Unable to load references. Reopen this statement to retry.',
                    ),
                  if (!_referencesLoading &&
                      !_referencesFailed &&
                      _references.isEmpty)
                    const Text(
                      'No reviewed investment transactions. Record and review acquisitions first.',
                    ),
                  for (final transaction in _references)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: SelectableText(
                        '${transaction.isBuy ? 'BUY' : 'SELL'} ${transaction.ticker} · ${transaction.accountNumber} · ${transaction.tradeDate.year}-${transaction.tradeDate.month.toString().padLeft(2, '0')}-${transaction.tradeDate.day.toString().padLeft(2, '0')} · ${transaction.unitsExact ?? transaction.units} units\nID: ${transaction.id}',
                      ),
                    ),
                ],
              ),
              const Text(
                'Cost-base history',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text(
                'Allocate the issuer adjustment to evidenced interests. Apply just before 30 June, or immediately before the relevant disposal. The received date is not the effective date.',
              ),
              for (var i = 0; i < _adjustments.length; i++)
                ListTile(
                  title: Text(
                    '${_adjustments[i].date} · AUD ${_adjustments[i].amount}',
                  ),
                  subtitle: Text(
                    'Parcel ${_adjustments[i].parcelId}\n${_adjustments[i].units} units · ${_adjustments[i].evidenceReference}',
                  ),
                  onTap: () => _adjustment(i),
                  trailing: IconButton(
                    tooltip: 'Remove adjustment',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() {
                      _adjustments.removeAt(i);
                      _reviewed = false;
                    }),
                  ),
                ),
              OutlinedButton(
                key: const Key('add-fund-adjustment'),
                onPressed: _saving ? null : _adjustment,
                child: const Text('Add parcel adjustment'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Distribution reinvestment links',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text(
                'Record the DRP acquisition through the investment transaction flow first. Link that existing BUY once here so broker imports do not create a second parcel.',
              ),
              for (var i = 0; i < _drp.length; i++)
                ListTile(
                  title: Text('BUY ${_drp[i].buyTransactionId}'),
                  subtitle: Text(
                    'Entitlement ${_drp[i].cashEntitlement} = reinvested ${_drp[i].reinvestedAmount} + cash ${_drp[i].residualCash}\n${_drp[i].evidenceReference}',
                  ),
                  onTap: () => _drpLink(i),
                  trailing: IconButton(
                    tooltip: 'Remove DRP link',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() {
                      _drp.removeAt(i);
                      _reviewed = false;
                    }),
                  ),
                ),
              OutlinedButton(
                key: const Key('add-fund-drp'),
                onPressed: _saving ? null : _drpLink,
                child: const Text('Link existing DRP BUY'),
              ),
              CheckboxListTile(
                key: const Key('fund-reviewed'),
                value: _reviewed,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _reviewed = v!),
                title: const Text(
                  'I checked issuer, year, all components, allocation evidence and linked DRP acquisitions against the source.',
                ),
              ),
              if (widget.statement?.id != null)
                CheckboxListTile(
                  key: const Key('fund-voided'),
                  value: _voided,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() {
                          _voided = v!;
                          _reviewed = false;
                        }),
                  title: const Text(
                    'Void this statement (keep history; exclude from calculations)',
                  ),
                ),
              if (!_reviewed && _draft().validation().isNotEmpty)
                Text(
                  'NeedsTaxReview: ${_draft().validation().join('; ')}. An unreviewed draft is excluded from calculations.',
                ),
              if (_error != null)
                Text(
                  _error!,
                  key: const Key('fund-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ElevatedButton(
                key: const Key('save-fund-statement'),
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving
                      ? 'Saving…'
                      : _reviewed
                      ? 'Save reviewed statement'
                      : 'Save unreviewed draft',
                ),
              ),
              if (widget.statement?.id != null)
                OutlinedButton(
                  onPressed: _history,
                  child: const Text('View immutable revision history'),
                ),
              if (widget.statement?.id != null)
                ExpansionTile(
                  title: const Text('Current source and component audit'),
                  children: [
                    SelectableText(
                      const JsonEncoder.withIndent(
                        '  ',
                      ).convert(widget.statement!.toMap()),
                    ),
                  ],
                ),
              if (_revisions != null)
                ExpansionTile(
                  title: const Text('Immutable revision history'),
                  children: [
                    SelectableText(
                      const JsonEncoder.withIndent('  ').convert(_revisions),
                    ),
                  ],
                ),
              const SizedBox(height: 32),
            ],
          ),
  );
}
