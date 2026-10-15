import 'dart:async';
import 'package:flutter/material.dart';
import '../models/document_coverage.dart';
import '../services/document_coverage_service.dart';
import '../services/auth_service.dart';

class DocumentCoverageScreen extends StatefulWidget {
  final AuthService? authService;
  final DocumentCoverageService? coverageService;
  const DocumentCoverageScreen({
    super.key,
    this.authService,
    this.coverageService,
  });
  @override
  State<DocumentCoverageScreen> createState() => _DocumentCoverageScreenState();
}

class _DocumentCoverageScreenState extends State<DocumentCoverageScreen> {
  late final AuthService _auth;
  late final DocumentCoverageService _service;
  DialogRoute<DocumentCoverage>? _dialogRoute;
  var _year = 2024;
  List<DocumentCoverage> _records = [];
  String? _error;
  StreamSubscription<dynamic>? _authSubscription;
  @override
  void initState() {
    super.initState();
    _auth = widget.authService ?? AuthService();
    _service = widget.coverageService ?? DocumentCoverageService();
    _load();
    _authSubscription = _auth.authStateChanges.listen((_) {
      if (!mounted) return;
      if (_dialogRoute?.isCurrent == true) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      setState(() {
        _records = [];
        _error = null;
      });
      _load();
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _auth.currentUser?.uid;
    final year = _year;
    if (uid == null) return;
    try {
      final r = await _service.getCoverage(uid, year);
      if (mounted && _auth.currentUser?.uid == uid && _year == year) {
        setState(() => _records = r);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Cannot load evidence inventory.');
    }
  }

  Future<void> _edit([DocumentCoverage? old]) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final account = TextEditingController(text: old?.account),
        ticker = TextEditingController(text: old?.ticker),
        evidence = TextEditingController(text: old?.evidenceReference),
        hash = TextEditingController(text: old?.sourceHash),
        firstPage = TextEditingController(text: old?.firstPage?.toString()),
        lastPage = TextEditingController(text: old?.lastPage?.toString()),
        domain = TextEditingController(text: old?.linkedDomain),
        recordId = TextEditingController(text: old?.linkedRecordId),
        units = TextEditingController(text: old?.unitsExact),
        date = TextEditingController(text: old?.observationDateIso);
    var family = old?.family ?? 'fundAnnual',
        state = old?.state ?? 'missing',
        required = old?.required ?? true;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<DocumentCoverage>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Document evidence'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const Key('document-account'),
                    controller: account,
                    readOnly: old != null,
                    decoration: const InputDecoration(labelText: 'Account'),
                  ),
                  TextField(
                    key: const Key('document-ticker'),
                    controller: ticker,
                    readOnly: old != null,
                    decoration: const InputDecoration(
                      labelText: 'Ticker / property',
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: family,
                    items: [
                      for (final v in DocumentCoverage.families)
                        DropdownMenuItem(value: v, child: Text(v)),
                    ],
                    onChanged: old == null
                        ? (v) => set(() => family = v!)
                        : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: state,
                    key: const Key('document-state'),
                    items: [
                      for (final v in DocumentCoverage.states)
                        DropdownMenuItem(value: v, child: Text(v)),
                    ],
                    onChanged: (v) => set(() => state = v!),
                  ),
                  CheckboxListTile(
                    value: required,
                    onChanged: (v) => set(() => required = v!),
                    title: const Text('Required evidence'),
                  ),
                  TextField(
                    controller: evidence,
                    decoration: const InputDecoration(
                      labelText: 'Evidence reference / reason not applicable',
                    ),
                  ),
                  TextField(
                    controller: hash,
                    decoration: const InputDecoration(
                      labelText: 'Local PDF SHA-256 fingerprint (optional)',
                    ),
                  ),
                  TextField(
                    controller: firstPage,
                    decoration: const InputDecoration(
                      labelText: 'First source page (optional)',
                    ),
                  ),
                  TextField(
                    controller: lastPage,
                    decoration: const InputDecoration(
                      labelText: 'Last source page (optional)',
                    ),
                  ),
                  TextField(
                    controller: domain,
                    decoration: const InputDecoration(
                      labelText:
                          'Linked collection (investment_transactions / managed_fund_statements / tax_records)',
                    ),
                  ),
                  TextField(
                    controller: recordId,
                    decoration: const InputDecoration(
                      labelText: 'Linked record ID (optional)',
                    ),
                  ),
                  if (family.endsWith('Holdings')) ...[
                    TextField(
                      controller: units,
                      decoration: const InputDecoration(
                        labelText: 'Observed units (exact)',
                      ),
                    ),
                    TextField(
                      controller: date,
                      decoration: const InputDecoration(
                        labelText: 'Observation date YYYY-MM-DD',
                      ),
                    ),
                  ],
                  const Text(
                    'PDF files remain local. Missing or insufficient required evidence prevents finalisation.',
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
              key: const Key('document-save'),
              onPressed: () {
                final r = DocumentCoverage(
                  id: old?.id,
                  userId: uid,
                  taxYearStart: _year,
                  account: account.text.trim(),
                  ticker: ticker.text.trim().toUpperCase(),
                  family: family,
                  state: state,
                  required: required,
                  evidenceReference: evidence.text.trim(),
                  unitsExact: units.text.trim(),
                  observationDateIso: date.text.trim(),
                  revision: old?.revision ?? 0,
                  sourceHash: hash.text.trim(),
                  firstPage: firstPage.text.trim().isEmpty
                      ? null
                      : int.tryParse(firstPage.text.trim()) ?? -1,
                  lastPage: lastPage.text.trim().isEmpty
                      ? null
                      : int.tryParse(lastPage.text.trim()) ?? -1,
                  linkedDomain: domain.text.trim(),
                  linkedRecordId: recordId.text.trim(),
                );
                if (r.validation().isEmpty) {
                  Navigator.pop(context, r);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(r.validation().join(' '))),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    _dialogRoute = route;
    final result = await navigator.push(route);
    // Popping resolves before the closing transition removes the form.
    await route.completed;
    _dialogRoute = null;
    for (final c in [
      account,
      ticker,
      evidence,
      units,
      date,
      hash,
      firstPage,
      lastPage,
      domain,
      recordId,
    ]) {
      c.dispose();
    }
    if (!mounted || result == null || _auth.currentUser?.uid != uid) return;
    try {
      await _service.save(result, expectedRevision: old?.revision ?? 0);
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Save failed or evidence changed. Reload and try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Document inventory')),
    floatingActionButton: FloatingActionButton(
      key: const Key('document-add'),
      onPressed: _edit,
      child: const Icon(Icons.add),
    ),
    body: _auth.currentUser == null
        ? const Center(child: Text('Sign in to access document evidence.'))
        : ListView(
            children: [
              DropdownButton<int>(
                value: _year,
                items: [
                  for (var y = 1900; y <= 2199; y++)
                    DropdownMenuItem(value: y, child: Text('FY $y–${y + 1}')),
                ],
                onChanged: (v) {
                  setState(() {
                    _year = v!;
                    _records = [];
                    _error = null;
                  });
                  _load();
                },
              ),
              if (_error != null) Text(_error!),
              for (final r in _records)
                ListTile(
                  title: Text('${r.account} / ${r.ticker}: ${r.family}'),
                  subtitle: Text(
                    '${r.state}${r.required ? ' · required' : ''}',
                  ),
                  onTap: () => _edit(r),
                ),
              if (_records.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Add expected documents for each account, fund and year, including missing documents.',
                  ),
                ),
            ],
          ),
  );
}
