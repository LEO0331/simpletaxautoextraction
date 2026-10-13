import 'package:flutter/material.dart';

import '../models/investment_transaction.dart';
import '../models/tax_decimal.dart';
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
  InvestmentTransactionType? _type;
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    final draft = widget.extraction.draft;
    final existing = widget.existing;
    _type = existing != null && !existing.isReviewed
        ? null
        : existing?.transactionType ??
              (draft.directionNeedsReview ? null : draft.transactionType);
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
      text:
          existing?.unitsExact ??
          draft.unitsExact ??
          ((existing?.units ?? draft.units ?? 0) == 0
              ? ''
              : (existing?.units ?? draft.units ?? 0).toString()),
    );
    _averagePrice = TextEditingController(
      text: (existing?.averagePrice ?? draft.averagePrice ?? 0) == 0
          ? ''
          : (existing?.averagePrice ?? draft.averagePrice ?? 0).toString(),
    );
    _consideration = TextEditingController(
      text:
          existing?.considerationExact ??
          draft.considerationExact ??
          ((existing?.consideration ?? draft.consideration ?? 0) == 0
              ? ''
              : (existing?.consideration ?? draft.consideration ?? 0)
                    .toString()),
    );
    _brokerage = TextEditingController(
      text:
          existing?.brokerageExact ??
          draft.brokerageExact ??
          (existing?.brokerage ?? draft.brokerage ?? 0).toString(),
    );
    _gst = TextEditingController(
      text: (existing?.gst ?? draft.gst ?? 0) == 0
          ? ''
          : (existing?.gst ?? draft.gst ?? 0).toString(),
    );
    _totalCost = TextEditingController(
      text:
          existing?.totalCostExact ??
          draft.totalCostExact ??
          ((existing?.totalCost ?? draft.totalCost ?? 0) == 0
              ? ''
              : (existing?.totalCost ?? draft.totalCost ?? 0).toString()),
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
    if (_type == null) {
      _showError('Explicitly select BUY or SELL.');
      return;
    }
    final tradeDate = parseFlexibleDate(_tradeDate.text.trim());
    if (tradeDate == null) {
      _showError('Trade date is required and must be valid.');
      return;
    }
    final exactTexts = [
      _units.text,
      _averagePrice.text,
      _consideration.text,
      _brokerage.text,
      _totalCost.text,
    ].map((text) => text.trim()).toList();
    final decimals = <TaxDecimal>[];
    try {
      for (var i = 0; i < exactTexts.length; i++) {
        final decimal = TaxDecimal.parse(exactTexts[i]);
        if (decimal.scale > (i < 2 ? 12 : 2)) throw const FormatException();
        decimals.add(decimal);
      }
    } on FormatException {
      _showError(
        'Enter valid decimals: units and price up to 12 places, money up to 2 places.',
      );
      return;
    }
    final units = double.parse(exactTexts[0]);
    final averagePrice = double.parse(exactTexts[1]);
    final consideration = double.parse(exactTexts[2]);
    final brokerage = double.parse(exactTexts[3]);
    final totalCost = double.parse(exactTexts[4]);

    if (_ticker.text.trim().isEmpty ||
        _securityName.text.trim().isEmpty ||
        !units.isFinite ||
        units <= 0 ||
        !averagePrice.isFinite ||
        averagePrice <= 0 ||
        !consideration.isFinite ||
        consideration <= 0 ||
        !brokerage.isFinite ||
        brokerage < 0 ||
        !totalCost.isFinite ||
        totalCost <= 0) {
      _showError(
        'Ticker, name, units, average price, and total cost are required.',
      );
      return;
    }

    final settlement = parseFlexibleDate(_settlementDate.text.trim());
    if (_settlementDate.text.trim().isNotEmpty && settlement == null) {
      _showError('Settlement date must be a valid calendar date.');
      return;
    }
    final expectedTotal = _type == InvestmentTransactionType.sell
        ? decimals[2] - decimals[3]
        : decimals[2] + decimals[3];
    if (decimals[4] != expectedTotal) {
      _showError(
        'Total must equal gross consideration ${_type == InvestmentTransactionType.sell ? 'minus' : 'plus'} brokerage (GST included).',
      );
      return;
    }
    final gstValue = _gst.text.trim().isEmpty
        ? null
        : parseMoney(_gst.text.trim());
    if (_gst.text.trim().isNotEmpty &&
        (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(_gst.text.trim()) ||
            gstValue == null ||
            !gstValue.isFinite ||
            gstValue < 0 ||
            gstValue > brokerage)) {
      _showError('GST must be a valid amount included in brokerage.');
      return;
    }

    final tx = InvestmentTransaction(
      // Source identity is required for audited parcel calculations.
      id: widget.existing?.id,
      userId: widget.userId,
      ticker: _ticker.text.trim().toUpperCase(),
      securityName: _securityName.text.trim(),
      transactionType: _type!,
      tradeDate: tradeDate,
      settlementDate: settlement,
      units: units,
      averagePrice: averagePrice,
      consideration: consideration,
      brokerage: brokerage,
      gst: gstValue,
      totalCost: totalCost,
      unitsExact: exactTexts[0],
      considerationExact: exactTexts[2],
      brokerageExact: exactTexts[3],
      totalCostExact: exactTexts[4],
      sourceHash: widget.existing?.sourceHash,
      isReviewed: true,
      isVoided: false,
      revision: widget.existing?.revision ?? 0,
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
    if (_accountNo.text.trim().isEmpty ||
        (widget.extraction.draft.sourceParser == 'Manual entry' &&
            _confirmationNo.text.trim().isEmpty)) {
      _showError(
        'Account identifier and a manual source reference are required.',
      );
      return;
    }
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
          _field('Gross consideration', _consideration),
          _field('Brokerage (GST included)', _brokerage),
          _field('GST included in brokerage', _gst),
          _field(
            _type == InvestmentTransactionType.sell
                ? 'Net proceeds'
                : 'Total cost',
            _totalCost,
          ),
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
