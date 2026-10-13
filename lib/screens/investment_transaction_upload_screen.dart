import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/investment_transaction.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/investment_draft_sync_service.dart';
import '../services/parsers/commsec_trade_confirmation_parser.dart';
import '../services/pdf_extraction_service.dart';
import '../utils/source_fingerprint.dart';
import 'investment_transaction_review_screen.dart';

class InvestmentTransactionUploadScreen extends StatefulWidget {
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final PdfExtractionService? pdfExtractionService;

  const InvestmentTransactionUploadScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.pdfExtractionService,
  });

  @override
  State<InvestmentTransactionUploadScreen> createState() =>
      _InvestmentTransactionUploadScreenState();
}

class _InvestmentTransactionUploadScreenState
    extends State<InvestmentTransactionUploadScreen> {
  late final AuthService _authService;
  late final FirestoreService _firestoreService;
  late final PdfExtractionService _pdfExtractionService;
  bool _isProcessing = false;
  final List<_ParsedDraftItem> _parsed = [];

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _firestoreService = widget.firestoreService ?? FirestoreService();
    _pdfExtractionService =
        widget.pdfExtractionService ?? PdfExtractionService();
  }

  Future<void> _pickAndParse() async {
    final user = _authService.currentUser;
    if (user == null) {
      _showSnackBar('Please sign in again.');
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null) {
      return;
    }
    setState(() {
      _isProcessing = true;
    });
    try {
      for (final f in result.files) {
        final bytes = f.bytes;
        if (bytes == null) {
          _parsed.add(
            _ParsedDraftItem(
              fileName: f.name,
              status: 'Error',
              error: 'Unable to read file bytes',
            ),
          );
          continue;
        }
        try {
          final extraction = await _pdfExtractionService
              .extractInvestmentTransactionFromPdf(
                bytes,
                sourceFileName: f.name,
              );
          _parsed.add(
            _ParsedDraftItem(
              fileName: f.name,
              status: extraction.draft.needsReview ? 'Needs review' : 'Parsed',
              extraction: extraction,
              sourceHash: SourceFingerprint.sha256(bytes),
            ),
          );
        } catch (e) {
          _parsed.add(
            _ParsedDraftItem(
              fileName: f.name,
              status: 'Error',
              error:
                  'Unsupported or unreadable document. Please review manually.',
            ),
          );
        }
      }
      if (mounted) {
        setState(() {});
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _reviewAndSave(_ParsedDraftItem item) async {
    final user = _authService.currentUser;
    if (user == null || item.extraction == null) {
      return;
    }
    final tx = await Navigator.push<InvestmentTransaction>(
      context,
      MaterialPageRoute(
        builder: (_) => InvestmentTransactionReviewScreen(
          userId: user.uid,
          extraction: item.extraction!,
        ),
      ),
    );
    if (tx == null) return;

    final duplicate = await _firestoreService.findInvestmentDuplicate(
      user.uid,
      tx,
    );
    if (!mounted) return;

    InvestmentTransaction toSave = tx.copyWith(sourceHash: item.sourceHash);
    if (duplicate != null) {
      final action = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Duplicate transaction detected'),
          content: const Text(
            'A transaction with the same confirmation number or fallback keys exists.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, 'replace'),
              child: const Text('Replace existing'),
            ),
          ],
        ),
      );

      if (action == 'cancel' || action == null) {
        return;
      }
      if (action == 'replace') {
        toSave = toSave.copyWith(
          id: duplicate.id,
          revision: duplicate.revision,
        );
      }
    }

    try {
      await _firestoreService.saveInvestmentTransaction(toSave);
      _showSnackBar('Investment transaction saved.');
    } on StateError {
      _showSnackBar(
        'Record changed or is locked. Reload and review before saving.',
      );
    } catch (_) {
      InvestmentDraftSyncService.instance.queueDraft(toSave);
      _showSnackBar(
        'Save failed. Reviewed draft queued for retry in this session.',
      );
    }
  }

  Future<void> _manualEntry() => _reviewAndSave(
    _ParsedDraftItem(
      fileName: 'Manual entry',
      status: 'Needs review',
      extraction: InvestmentExtractionResult(
        draft: const InvestmentTransactionDraft(
          ticker: '',
          securityName: '',
          transactionType: InvestmentTransactionType.buy,
          tradeDate: null,
          settlementDate: null,
          units: null,
          averagePrice: null,
          consideration: null,
          brokerage: null,
          gst: null,
          totalCost: null,
          confirmationNumber: null,
          accountNumber: null,
          sourceFileName: null,
          sourceParser: 'Manual entry',
          parserVersion: 'v1',
          notes: '',
          needsReview: true,
          directionNeedsReview: true,
        ),
        confidence: 0,
        missingFields: const [],
        warnings: const [
          'Enter an account identifier and evidence reference in the confirmation field.',
        ],
        rawText: '',
      ),
    ),
  );

  Future<void> _retryDrafts() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;
    setState(() => _isProcessing = true);
    try {
      final count = await InvestmentDraftSyncService.instance.syncAll(
        _firestoreService,
        userId: uid,
      );
      _showSnackBar(
        '$count reviewed drafts saved. Remaining drafts may require review.',
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Investment PDFs')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _pickAndParse,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
              label: Text(_isProcessing ? 'Parsing...' : 'Upload PDFs'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _isProcessing ? null : _manualEntry,
              child: const Text('Enter transaction manually'),
            ),
            if (InvestmentDraftSyncService.instance.pendingDrafts.any(
              (draft) => draft.userId == _authService.currentUser?.uid,
            ))
              TextButton(
                onPressed: _isProcessing ? null : _retryDrafts,
                child: const Text('Retry this account’s queued drafts'),
              ),
            Expanded(
              child: _parsed.isEmpty
                  ? const Center(
                      child: Text('No PDFs parsed yet. Upload to start.'),
                    )
                  : ListView.separated(
                      itemCount: _parsed.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final item = _parsed[index];
                        return Card(
                          child: ListTile(
                            title: Text(item.fileName),
                            subtitle: Text(
                              item.error != null
                                  ? 'Error: ${item.error}'
                                  : 'Status: ${item.status}'
                                        '${item.extraction == null ? '' : ' | Confidence: ${(item.extraction!.confidence * 100).toStringAsFixed(0)}%'}',
                            ),
                            trailing: item.extraction == null
                                ? null
                                : ElevatedButton(
                                    onPressed: () => _reviewAndSave(item),
                                    child: const Text('Review'),
                                  ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParsedDraftItem {
  final String fileName;
  final String status;
  final InvestmentExtractionResult? extraction;
  final String? error;
  final String? sourceHash;

  _ParsedDraftItem({
    required this.fileName,
    required this.status,
    this.extraction,
    this.error,
    this.sourceHash,
  });
}
