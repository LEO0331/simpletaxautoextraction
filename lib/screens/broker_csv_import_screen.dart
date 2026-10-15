import 'dart:convert';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/parsers/broker_csv_parser.dart';
import '../services/parsers/commsec_trade_confirmation_parser.dart';
import '../models/investment_transaction.dart';
import '../utils/source_fingerprint.dart';
import 'investment_transaction_review_screen.dart';

class BrokerCsvImportScreen extends StatefulWidget {
  const BrokerCsvImportScreen({super.key});
  @override
  State<BrokerCsvImportScreen> createState() => _BrokerCsvImportScreenState();
}

class _BrokerCsvImportScreenState extends State<BrokerCsvImportScreen> {
  final _auth = AuthService(), _store = FirestoreService();
  List<InvestmentExtractionResult> _drafts = [];
  String? _uid, _hash, _error;
  bool _aud = false, _busy = false;
  final Set<int> _saved = {};
  StreamSubscription<dynamic>? _subscription;
  MaterialPageRoute<InvestmentTransaction>? _reviewRoute;
  String? _owner;
  @override
  void initState() {
    super.initState();
    _owner = _auth.currentUser?.uid;
    _subscription = _auth.authStateChanges.listen((user) {
      if (mounted && user?.uid != _owner) {
        _owner = user?.uid;
        final route = _reviewRoute;
        if (route?.isActive == true) route!.navigator?.removeRoute(route);
        setState(() {
          _drafts = [];
          _saved.clear();
          _uid = null;
          _hash = null;
          _error = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _pick() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final f = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (f == null) return;
    if (!mounted || _auth.currentUser?.uid != uid) return;
    setState(() {
      _drafts = [];
      _saved.clear();
      _hash = null;
      _uid = null;
    });
    try {
      final bytes = f.files.single.bytes;
      if (bytes == null) throw const FormatException('Cannot read CSV.');
      final drafts = BrokerCsvParser().parse(
        utf8.decode(bytes).replaceFirst('\uFEFF', ''),
        sourceFileName: f.files.single.name,
        confirmedAud: _aud,
      );
      if (mounted && _auth.currentUser?.uid == uid) {
        setState(() {
          _uid = uid;
          _hash = SourceFingerprint.sha256(bytes);
          _drafts = drafts;
          _saved.clear();
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unsupported CSV. Use the documented exact-column format and confirm AUD. No rows were saved.',
        );
      }
    }
  }

  Future<void> _review(int i) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid != _uid || _busy) return;
    final extraction = _drafts[i];
    final route = MaterialPageRoute<InvestmentTransaction>(
      builder: (_) => InvestmentTransactionReviewScreen(
        userId: uid,
        extraction: extraction,
      ),
    );
    _reviewRoute = route;
    final tx = await Navigator.of(context).push(route);
    if (identical(_reviewRoute, route)) _reviewRoute = null;
    if (tx == null || _auth.currentUser?.uid != uid || !mounted) return;
    setState(() => _busy = true);
    try {
      final candidate = tx.copyWith(sourceHash: _hash);
      final duplicate = await _store.findInvestmentDuplicate(uid, candidate);
      if (duplicate != null) {
        if (mounted) {
          setState(
            () => _error =
                'Matching trade already exists. Review it in the transaction list; this CSV row was not added.',
          );
        }
        return;
      }
      if (_auth.currentUser?.uid != uid) return;
      await _store.saveInvestmentTransaction(candidate);
      if (mounted) setState(() => _saved.add(i));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Trade could not be saved. Reload to check for a duplicate or changed record.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Review broker CSV')),
    body: ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Required columns: tradeDate (YYYY-MM-DD or DD/MM/YYYY), direction (BUY/SELL), ticker, account, confirmationNumber, units, consideration, brokerage, totalCost, currency. Optional broker=CommSec matches PDF confirmations. Sales totalCost means net settlement. Each row requires review.',
          ),
        ),
        CheckboxListTile(
          value: _aud,
          onChanged: (v) => setState(() => _aud = v!),
          title: const Text('I confirm missing currency columns are AUD'),
        ),
        FilledButton(
          onPressed: _busy ? null : _pick,
          child: const Text('Choose local CSV'),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
        for (var i = 0; i < _drafts.length; i++)
          ListTile(
            title: Text('Row ${i + 1}: ${_drafts[i].draft.ticker}'),
            subtitle: Text(
              _saved.contains(i)
                  ? 'Saved'
                  : _drafts[i].missingFields.isEmpty
                  ? 'Ready for review'
                  : 'Review: ${_drafts[i].missingFields.join(', ')}',
            ),
            trailing: TextButton(
              onPressed: _busy || _saved.contains(i) ? null : () => _review(i),
              child: const Text('Review'),
            ),
          ),
      ],
    ),
  );
}
