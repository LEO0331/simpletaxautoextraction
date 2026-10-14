import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/document_coverage.dart';
import '../models/investment_transaction.dart';
import '../models/tax_decimal.dart';
import '../services/auth_service.dart';
import '../services/document_coverage_service.dart';
import '../services/firestore_service.dart';
import '../services/parsers/drp_advice_parser.dart';
import '../utils/source_fingerprint.dart';

/// Records advice evidence against an existing reviewed acquisition, never a new lot.
class DrpAdviceScreen extends StatefulWidget {
  const DrpAdviceScreen({super.key});
  @override
  State<DrpAdviceScreen> createState() => _DrpAdviceScreenState();
}

class _DrpAdviceScreenState extends State<DrpAdviceScreen> {
  final _auth = AuthService(),
      _store = FirestoreService(),
      _coverage = DocumentCoverageService();
  final _first = TextEditingController(text: '1'),
      _last = TextEditingController(text: '1'),
      _units = TextEditingController(),
      _amount = TextEditingController(),
      _residual = TextEditingController(),
      _date = TextEditingController();
  List<InvestmentTransaction> _buys = [];
  String? _selected, _hash, _uid, _error;
  int? _sourceFirst, _sourceLast;
  bool _confirmed = false;
  StreamSubscription<dynamic>? _subscription;
  @override
  void initState() {
    super.initState();
    _load();
    _subscription = _auth.authStateChanges.listen((_) {
      if (!mounted) return;
      setState(() {
        _buys = [];
        _selected = null;
        _uid = null;
        _hash = null;
        _error = null;
        _confirmed = false;
        for (final c in [_units, _amount, _residual, _date]) {
          c.clear();
        }
      });
      _load();
    });
  }

  Future<void> _load() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final t = await _store.getInvestmentTransactionsOnce(uid);
      if (mounted && _auth.currentUser?.uid == uid) {
        setState(
          () => _buys = t
              .where((t) => t.isBuy && t.isReviewed && !t.isVoided)
              .toList(),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Cannot load reviewed acquisitions.');
      }
    }
  }

  Future<void> _pick() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null) return;
    if (!mounted || _auth.currentUser?.uid != uid) return;
    setState(() {
      _uid = null;
      _hash = null;
      _confirmed = false;
      _selected = null;
    });
    PdfDocument? pdf;
    try {
      final bytes = result.files.single.bytes;
      if (bytes == null || bytes.length > 10 * 1024 * 1024) {
        throw const FormatException('Invalid PDF');
      }
      pdf = PdfDocument(inputBytes: bytes);
      final first = int.parse(_first.text), last = int.parse(_last.text);
      if (first < 1 ||
          last < first ||
          last > pdf.pages.count ||
          last - first > 1) {
        throw const FormatException('Select up to two advice pages');
      }
      final text = PdfTextExtractor(
        pdf,
      ).extractText(startPageIndex: first - 1, endPageIndex: last - 1);
      final draft = DrpAdviceParser().parse(text);
      if (mounted && _auth.currentUser?.uid == uid) {
        setState(() {
          _uid = uid;
          _hash = SourceFingerprint.sha256(bytes);
          _sourceFirst = first;
          _sourceLast = last;
          _units.text = draft.units ?? '';
          _amount.text = draft.reinvestedAmount ?? '';
          _residual.text = draft.residualCash ?? '';
          _date.text = draft.paymentDate ?? '';
          _confirmed = false;
          _error = draft.issues.join(' ');
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unreadable PDF or invalid page range. Select only the advice pages.',
        );
      }
    } finally {
      pdf?.dispose();
    }
  }

  Future<void> _save() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null ||
        uid != _uid ||
        _hash == null ||
        !_confirmed ||
        _selected == null) {
      return;
    }
    try {
      final tx = _buys.singleWhere((t) => t.id == _selected);
      final units = TaxDecimal.parse(_units.text),
          amount = TaxDecimal.parse(_amount.text),
          residual = TaxDecimal.parse(_residual.text),
          date = parseDocumentDate(_date.text);
      if (date == null ||
          residual.isNegative ||
          units != TaxDecimal.parse(tx.unitsExact!) ||
          amount != TaxDecimal.parse(tx.considerationExact!) ||
          date.year != tx.tradeDate.year ||
          date.month != tx.tradeDate.month ||
          date.day != tx.tradeDate.day) {
        throw const FormatException(
          'Advice must match acquisition units, date and consideration.',
        );
      }
      final year = date.month >= 7 ? date.year : date.year - 1;
      final existing = await _coverage.getCoverage(uid, year);
      final records = existing
          .where(
            (r) =>
                r.family == 'drpAdvice' &&
                r.account == tx.accountNumber &&
                r.ticker == tx.ticker &&
                r.linkedRecordId == tx.id,
          )
          .toList();
      final old = records.isEmpty ? null : records.single;
      if (old != null &&
          old.linkedRecordId.isNotEmpty &&
          old.linkedRecordId != tx.id) {
        throw const FormatException(
          'A different advice is already linked. Use fund statement DRP rows for multiple acquisitions.',
        );
      }
      if (_auth.currentUser?.uid != uid) return;
      await _coverage.save(
        DocumentCoverage(
          id: old?.id,
          userId: uid,
          taxYearStart: year,
          account: tx.accountNumber!,
          ticker: tx.ticker,
          family: 'drpAdvice',
          state: 'reviewed',
          evidenceReference:
              'Local advice pages $_sourceFirst–$_sourceLast; reinvested ${amount.toString()}; residual ${residual.toString()}',
          sourceHash: _hash!,
          firstPage: _sourceFirst,
          lastPage: _sourceLast,
          linkedDomain: 'investment_transactions',
          linkedRecordId: tx.id!,
          unitsExact: units.toString(),
          observationDateIso: _date.text,
          revision: old?.revision ?? 0,
        ),
        expectedRevision: old?.revision ?? 0,
      );
      if (mounted) {
        setState(
          () => _error =
              'Advice linked. No additional acquisition parcel was created. Add the existing trade reference to the annual fund statement DRP reconciliation.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Link failed. Verify exact units, consideration, payment date and selected acquisition. Multiple DRPs use the annual statement DRP list.',
        );
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    for (final c in [_first, _last, _units, _amount, _residual, _date]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DRP advice review')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Select advice pages from a local PDF. Betashares/Link labels are supported conservatively. Unclear fields require manual entry. Existing reviewed acquisitions are reused.',
        ),
        TextField(
          controller: _first,
          decoration: const InputDecoration(labelText: 'First PDF page'),
        ),
        TextField(
          controller: _last,
          decoration: const InputDecoration(labelText: 'Last PDF page'),
        ),
        FilledButton(onPressed: _pick, child: const Text('Choose local PDF')),
        for (final pair in [
          (_date, 'Payment / acquisition date YYYY-MM-DD'),
          (_units, 'Units allotted'),
          (_amount, 'Amount reinvested'),
          (_residual, 'Residual cash'),
        ])
          TextField(
            controller: pair.$1,
            decoration: InputDecoration(labelText: pair.$2),
          ),
        DropdownButtonFormField<String>(
          initialValue: _selected,
          items: [
            for (final t in _buys)
              DropdownMenuItem(
                value: t.id,
                child: Text(
                  '${t.ticker} ${t.tradeDate.toIso8601String().split('T').first} ${t.unitsExact}',
                ),
              ),
          ],
          onChanged: (v) => setState(() => _selected = v),
          decoration: const InputDecoration(labelText: 'Existing reviewed BUY'),
        ),
        CheckboxListTile(
          value: _confirmed,
          onChanged: (v) => setState(() => _confirmed = v!),
          title: const Text(
            'I checked the source and matched this acquisition',
          ),
        ),
        FilledButton(onPressed: _save, child: const Text('Link evidence')),
        if (_error != null) Text(_error!),
      ],
    ),
  );
}
