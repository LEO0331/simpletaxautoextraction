import 'package:flutter/material.dart';

import '../models/investment_transaction.dart';
import '../services/parsers/commsec_trade_confirmation_parser.dart';
import '../utils/investment_cgt_utils.dart';

class InvestmentTransactionReviewScreen extends StatefulWidget {
  final String userId;
  final InvestmentExtractionResult extraction;
  final InvestmentTransaction? existing;

  const InvestmentTransactionReviewScreen({
    super.key,
    required this.userId,
    required this.extraction,
    this.existing,
  });

  @override
  State<InvestmentTransactionReviewScreen> createState() =>
      _InvestmentTransactionReviewScreenState();
}

class _InvestmentTransactionReviewScreenState
    extends State<InvestmentTransactionReviewScreen> {
  late final TextEditingController _ticker;
  late final TextEditingController _securityName;
  late final TextEditingController _tradeDate;
  late final TextEditingController _settlementDate;
  late final TextEditingController _units;
  late final TextEditingController _averagePrice;
  late final TextEditingController _consideration;
  late final TextEditingController _brokerage;
  late final TextEditingController _gst;
  late final TextEditingController _totalCost;
  late final TextEditingController _confirmationNo;
  late final TextEditingController _accountNo;
  late final TextEditingController _notes;
  late InvestmentTransactionType _type;
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    final draft = widget.extraction.draft;
    final existing = widget.existing;
    _type = existing?.transactionType ?? draft.transactionType;
    _isLocked = existing?.isLocked ?? false;
    _ticker = TextEditingController(text: existing?.ticker ?? draft.ticker);
    _securityName = TextEditingController(
      text: existing?.securityName ?? draft.securityName,
    );
    _tradeDate = TextEditingController(
      text: _formatDate(existing?.tradeDate ?? draft.tradeDate),
    );
    _settlementDate = TextEditingController(
      text: _formatDate(existing?.settlementDate ?? draft.settlementDate),
    );
    _units = TextEditingController(
      text: (existing?.units ?? draft.units ?? 0) == 0
          ? ''
          : (existing?.units ?? draft.units ?? 0).toString(),
    );
    _averagePrice = TextEditingController(
      text: (existing?.averagePrice ?? draft.averagePrice ?? 0) == 0
          ? ''
          : (existing?.averagePrice ?? draft.averagePrice ?? 0).toString(),
    );
    _consideration = TextEditingController(
      text: (existing?.consideration ?? draft.consideration ?? 0) == 0
          ? ''
          : (existing?.consideration ?? draft.consideration ?? 0).toString(),
    );
    _brokerage = TextEditingController(
      text: (existing?.brokerage ?? draft.brokerage ?? 0) == 0
          ? ''
          : (existing?.brokerage ?? draft.brokerage ?? 0).toString(),
    );
    _gst = TextEditingController(
      text: (existing?.gst ?? draft.gst ?? 0) == 0
          ? ''
          : (existing?.gst ?? draft.gst ?? 0).toString(),
    );
    _totalCost = TextEditingController(
      text: (existing?.totalCost ?? draft.totalCost ?? 0) == 0
          ? ''
          : (existing?.totalCost ?? draft.totalCost ?? 0).toString(),
    );
    _confirmationNo = TextEditingController(
      text: existing?.confirmationNumber ?? draft.confirmationNumber ?? '',
    );
    _accountNo = TextEditingController(
      text: existing?.accountNumber ?? draft.accountNumber ?? '',
    );
    _notes = TextEditingController(text: existing?.notes ?? draft.notes);
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return '';
    }
    return '${date.year.toString().padLeft(4, '0')}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _ticker.dispose();
    _securityName.dispose();
    _tradeDate.dispose();
    _settlementDate.dispose();
    _units.dispose();
    _averagePrice.dispose();
    _consideration.dispose();
    _brokerage.dispose();
    _gst.dispose();
    _totalCost.dispose();
    _confirmationNo.dispose();
    _accountNo.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final tradeDate = parseFlexibleDate(_tradeDate.text.trim());
    if (tradeDate == null) {
      _showError('Trade date is required and must be valid.');
      return;
    }
    final units = double.tryParse(_units.text.trim()) ?? 0;
    final averagePrice = double.tryParse(_averagePrice.text.trim()) ?? 0;
    final consideration = parseMoney(_consideration.text.trim());
    final brokerage = parseMoney(_brokerage.text.trim());
    final parsedTotalCost = parseMoney(_totalCost.text.trim());
    final totalCost = parsedTotalCost > 0
        ? parsedTotalCost
        : consideration + brokerage;

    if (_ticker.text.trim().isEmpty ||
        _securityName.text.trim().isEmpty ||
        units <= 0 ||
        averagePrice <= 0 ||
        totalCost <= 0) {
      _showError(
        'Ticker, name, units, average price, and total cost are required.',
      );
      return;
    }

    final settlement = parseFlexibleDate(_settlementDate.text.trim());
    final gstValue = _gst.text.trim().isEmpty
        ? null
        : parseMoney(_gst.text.trim());

    final tx = InvestmentTransaction(
      id: widget.existing?.id,
      userId: widget.userId,
      ticker: _ticker.text.trim().toUpperCase(),
      securityName: _securityName.text.trim(),
      transactionType: _type,
      tradeDate: tradeDate,
      settlementDate: settlement,
      units: units,
      averagePrice: averagePrice,
      consideration: consideration,
      brokerage: brokerage,
      gst: gstValue,
      totalCost: totalCost,
      confirmationNumber: _confirmationNo.text.trim().isEmpty
          ? null
          : _confirmationNo.text.trim(),
      accountNumber: _accountNo.text.trim().isEmpty
          ? null
          : _accountNo.text.trim(),
      sourceFileName:
          widget.existing?.sourceFileName ??
          widget.extraction.draft.sourceFileName,
      sourceParser: widget.extraction.draft.sourceParser,
      parserVersion: widget.extraction.draft.parserVersion,
      notes: _notes.text.trim(),
      isLocked: _isLocked,
      createdAt: widget.existing?.createdAt,
      updatedAt: widget.existing?.updatedAt,
    );
    Navigator.pop(context, tx);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final warnings = [
      ...widget.extraction.missingFields.map((m) => 'Missing field: $m'),
      ...widget.extraction.warnings,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Review Investment Transaction')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (warnings.isNotEmpty)
            Card(
              color: const Color(0xFFFFF2D8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: warnings.map((w) => Text('• $w')).toList(),
                ),
              ),
            ),
          const SizedBox(height: 8),
          DropdownButtonFormField<InvestmentTransactionType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Transaction Type'),
            items: const [
              DropdownMenuItem(
                value: InvestmentTransactionType.buy,
                child: Text('BUY'),
              ),
              DropdownMenuItem(
                value: InvestmentTransactionType.sell,
                child: Text('SELL'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _type = value;
                });
              }
            },
          ),
          const SizedBox(height: 8),
          _field('Ticker', _ticker),
          _field('Security name', _securityName),
          _field('Trade date (YYYY/MM/DD or DD/MM/YYYY)', _tradeDate),
          _field('Settlement date', _settlementDate),
          _field('Units', _units),
          _field('Average price', _averagePrice),
          _field('Consideration', _consideration),
          _field('Brokerage', _brokerage),
          _field('GST', _gst),
          _field('Total cost', _totalCost),
          _field('Confirmation number', _confirmationNo),
          _field('Account number', _accountNo),
          _field('Notes', _notes, maxLines: 3),
          SwitchListTile(
            value: _isLocked,
            onChanged: (v) {
              setState(() {
                _isLocked = v;
              });
            },
            title: const Text('Lock transaction'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
