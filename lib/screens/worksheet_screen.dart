import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/tax_record.dart';
import '../services/draft_sync_service.dart';
import '../services/firestore_service.dart';

class WorksheetScreen extends StatefulWidget {
  final TaxRecord record;
  final FirestoreService? firestoreService;

  const WorksheetScreen({
    super.key,
    required this.record,
    this.firestoreService,
  });

  @override
  State<WorksheetScreen> createState() => _WorksheetScreenState();
}

class _WorksheetScreenState extends State<WorksheetScreen> {
  static final RegExp _financialYearRegex = RegExp(r'^\d{4}-\d{4}$');

  late TaxRecord _activeRecord;
  late final FirestoreService _firestoreService;
  late final TextEditingController _notesController;
  late bool _isLocked;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _activeRecord = widget.record;
    _firestoreService = widget.firestoreService ?? FirestoreService();
    _notesController = TextEditingController(text: _activeRecord.notes);
    _isLocked = _activeRecord.isLocked;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _updateIncome(String category, String value) {
    if (_isLocked) {
      return;
    }
    final doubleAmount = double.tryParse(value) ?? 0.0;
    setState(() {
      _activeRecord.income[category] = doubleAmount;
    });
  }

  void _updateExpense(String category, String value) {
    if (_isLocked) {
      return;
    }
    final doubleAmount = double.tryParse(value) ?? 0.0;
    setState(() {
      _activeRecord.expenses[category] = doubleAmount;
    });
  }

  Future<void> _saveRecord({bool saveAsNewYear = false}) async {
    if (_isLocked && !saveAsNewYear) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This record is locked. Use Save As New Year to create a copy.',
          ),
        ),
      );
      return;
    }

    String? targetYear;
    if (saveAsNewYear) {
      targetYear = await _showSaveAsNewYearDialog();
      if (targetYear == null) {
        return;
      }
    }

    setState(() {
      _isSaving = true;
    });

    final recordToSave = _activeRecord.copyWith(
      notes: _notesController.text.trim(),
      isLocked: _isLocked,
      financialYear: targetYear ?? _activeRecord.financialYear,
    );

    try {
      SaveTaxRecordResult result;
      if (saveAsNewYear) {
        result = await _firestoreService.saveTaxRecordWithStrategy(
          recordToSave,
          saveAsNewYear: true,
          overrideFinancialYear: targetYear,
        );
      } else {
        await _firestoreService.saveTaxRecord(recordToSave);
        result = SaveTaxRecordResult(
          documentId: recordToSave.id ?? '',
          replacedExistingYear: false,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _activeRecord = recordToSave.copyWith(
          id: result.documentId.isEmpty ? recordToSave.id : result.documentId,
        );
      });

      final message = saveAsNewYear
          ? 'Saved as FY ${targetYear ?? _activeRecord.financialYear}.'
          : result.replacedExistingYear
          ? 'Updated existing record for FY ${_activeRecord.financialYear}.'
          : 'Tax record saved successfully!';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      if (!saveAsNewYear) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      DraftSyncService.instance.queueDraft(recordToSave);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed, draft queued for sync: $e'),
          action: SnackBarAction(
            label: 'Retry now',
            onPressed: () => _saveRecord(saveAsNewYear: saveAsNewYear),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<String?> _showSaveAsNewYearDialog() {
    final currentYearStart =
        int.tryParse(_activeRecord.financialYear.split('-').first) ??
        DateTime.now().year;
    String inputYear = '${currentYearStart + 1}-${currentYearStart + 2}';
    String? errorText;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                'Save As New Financial Year',
                style: GoogleFonts.inter(),
              ),
              content: SizedBox(
                width: 360,
                child: TextField(
                  controller: TextEditingController(text: inputYear),
                  onChanged: (value) {
                    setDialogState(() {
                      inputYear = value.trim();
                      errorText = null;
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'Financial Year',
                    hintText: 'YYYY-YYYY',
                    border: const OutlineInputBorder(),
                    errorText: errorText,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final normalized = inputYear.trim();
                    if (!_isValidFinancialYear(normalized)) {
                      setDialogState(() {
                        errorText =
                            'Use YYYY-YYYY and ensure end year is start+1.';
                      });
                      return;
                    }
                    Navigator.pop(context, normalized);
                  },
                  child: const Text('Save Copy'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _isValidFinancialYear(String value) {
    if (!_financialYearRegex.hasMatch(value)) {
      return false;
    }
    final years = value.split('-');
    final start = int.tryParse(years[0]);
    final end = int.tryParse(years[1]);
    return start != null && end != null && end == start + 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Tax Worksheet ${_activeRecord.financialYear}',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.content_copy),
              tooltip: 'Save As New Year',
              onPressed: () => _saveRecord(saveAsNewYear: true),
            ),
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Save Record',
              onPressed: _saveRecord,
            ),
          ],
        ],
      ),
      body: SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: SizedBox(
              width: 800,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSummaryCard(),
                  const SizedBox(height: 16),
                  Card(
                    child: SwitchListTile(
                      title: const Text('Lock this financial year'),
                      subtitle: const Text(
                        'Locked records can only be copied to a new year.',
                      ),
                      value: _isLocked,
                      onChanged: (val) {
                        setState(() {
                          _isLocked = val;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    readOnly: _isLocked,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      hintText: 'Add explanation for accountant/audit trail',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildLineItemsCard(),
                  const SizedBox(height: 24),
                  Text(
                    'Income',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildCategoryList(_activeRecord.income, _updateIncome),
                  const SizedBox(height: 24),
                  Text(
                    'Expenses',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildCategoryList(_activeRecord.expenses, _updateExpense),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _saveRecord,
        icon: const Icon(Icons.check),
        label: Text('Save Data', style: GoogleFonts.inter()),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Income', style: GoogleFonts.inter(fontSize: 16)),
                Text(
                  '\$${_activeRecord.totalIncome.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Expenses', style: GoogleFonts.inter(fontSize: 16)),
                Text(
                  '\$${_activeRecord.totalExpenses.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.red[700],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Net Position',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '\$${_activeRecord.netPosition.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _activeRecord.netPosition >= 0
                        ? Colors.green[800]
                        : Colors.red[800],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryList(
    Map<String, double> categories,
    Function(String, String) onChanged,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: categories.keys.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final category = categories.keys.elementAt(index);
          final value = categories[category]!;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(category, style: GoogleFonts.inter(fontSize: 14)),
                ),
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    enabled: !_isLocked,
                    initialValue: value == 0.0 ? '' : value.toStringAsFixed(2),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (val) => onChanged(category, val),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLineItemsCard() {
    if (_activeRecord.lineItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Extracted Transaction Details',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: ListView.separated(
                itemCount: _activeRecord.lineItems.length,
                separatorBuilder: (_, _) => const Divider(height: 12),
                itemBuilder: (context, index) {
                  final item = _activeRecord.lineItems[index];
                  final source = item['sourceCategory'] ?? 'Unknown';
                  final amount = item['amount'] ?? 0.0;
                  final mapped = item['mappedCategory'] ?? 'UNMAPPED';
                  return Text(
                    '$source -> $mapped  (\$${(amount as num).toStringAsFixed(2)})',
                    style: GoogleFonts.inter(fontSize: 13),
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
