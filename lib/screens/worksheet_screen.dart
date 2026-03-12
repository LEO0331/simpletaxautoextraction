import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/tax_record.dart';
import '../services/firestore_service.dart';

class WorksheetScreen extends StatefulWidget {
  final TaxRecord record;
  final FirestoreService? firestoreService;

  const WorksheetScreen({super.key, required this.record, this.firestoreService});

  @override
  State<WorksheetScreen> createState() => _WorksheetScreenState();
}

class _WorksheetScreenState extends State<WorksheetScreen> {
  late TaxRecord _activeRecord;
  late final FirestoreService _firestoreService;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _activeRecord = widget.record;
    _firestoreService = widget.firestoreService ?? FirestoreService();
  }

  void _updateIncome(String category, String value) {
    final doubleAmount = double.tryParse(value) ?? 0.0;
    setState(() {
      _activeRecord.income[category] = doubleAmount;
    });
  }

  void _updateExpense(String category, String value) {
    final doubleAmount = double.tryParse(value) ?? 0.0;
    setState(() {
      _activeRecord.expenses[category] = doubleAmount;
    });
  }

  Future<void> _saveRecord() async {
    setState(() {
      _isSaving = true;
    });
    try {
      await _firestoreService.saveTaxRecord(_activeRecord);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tax Record saved successfully!')),
        );
        Navigator.of(context).pop(); // Go back to home
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
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
          else
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Save Record',
              onPressed: _saveRecord,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSummaryCard(),
                const SizedBox(height: 24),
                Text(
                  'Income',
                  style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800]),
                ),
                const SizedBox(height: 8),
                _buildCategoryList(_activeRecord.income, _updateIncome),
                const SizedBox(height: 24),
                Text(
                  'Expenses',
                  style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[800]),
                ),
                const SizedBox(height: 8),
                _buildCategoryList(_activeRecord.expenses, _updateExpense),
              ],
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
                      color: Colors.green[700]),
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
                      color: Colors.red[700]),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Net Position',
                    style: GoogleFonts.inter(
                        fontSize: 18, fontWeight: FontWeight.bold)),
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
      Map<String, double> categories, Function(String, String) onChanged) {
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
                  child: Text(
                    category,
                    style: GoogleFonts.inter(fontSize: 14),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    initialValue: value == 0.0 ? '' : value.toStringAsFixed(2),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
}
