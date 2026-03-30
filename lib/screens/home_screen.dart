import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/tax_record.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/pdf_extraction_service.dart';
import 'comparison_screen.dart';
import 'worksheet_screen.dart';

class HomeScreen extends StatefulWidget {
  final AuthService? authService;
  final FirestoreService? firestoreService;
  final PdfExtractionService? pdfExtractionService;

  const HomeScreen({
    super.key,
    this.authService,
    this.firestoreService,
    this.pdfExtractionService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final RegExp _financialYearRegex = RegExp(r'^\d{4}-\d{4}$');

  late final AuthService _authService;
  late final FirestoreService _firestoreService;
  late final PdfExtractionService _pdfExtractionService;

  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _firestoreService = widget.firestoreService ?? FirestoreService();
    _pdfExtractionService =
        widget.pdfExtractionService ?? PdfExtractionService();
  }

  Future<void> _pickAndProcessPdf() async {
    final user = _authService.currentUser;
    if (user == null) {
      _showSnackBar('Session expired. Please sign in again.');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );

    if (result == null) {
      return;
    }

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _showSnackBar('Unable to read PDF bytes. Please try another file.');
      return;
    }

    final selectedYear = await _showYearDialog();
    if (selectedYear == null) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final refreshedUser = _authService.currentUser;
      if (refreshedUser == null) {
        throw StateError('Authentication expired while importing.');
      }

      final preview = await _pdfExtractionService.extractPreviewFromPdf(
        bytes,
        refreshedUser.uid,
        selectedYear,
      );
      final reviewedRecord = await _showImportPreviewDialog(preview);
      if (reviewedRecord == null || !mounted) {
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WorksheetScreen(
            record: reviewedRecord,
            firestoreService: _firestoreService,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        'Failed to process PDF: $e',
        actionLabel: 'Retry',
        onAction: _pickAndProcessPdf,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<String?> _showYearDialog() {
    String selectedYear = _defaultFinancialYear();
    String customYear = selectedYear;
    String? errorText;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final options = _financialYearOptions();
            return AlertDialog(
              title: Text('Select Financial Year', style: GoogleFonts.inter()),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: options.contains(selectedYear)
                          ? selectedYear
                          : options.first,
                      items: options
                          .map(
                            (year) => DropdownMenuItem<String>(
                              value: year,
                              child: Text(year),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          selectedYear = value;
                          customYear = value;
                          errorText = null;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'Suggested years',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: TextEditingController(text: customYear),
                      onChanged: (value) {
                        setDialogState(() {
                          customYear = value.trim();
                          selectedYear = customYear;
                          errorText = null;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'YYYY-YYYY',
                        border: const OutlineInputBorder(),
                        errorText: errorText,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final normalized = customYear.trim();
                    if (!_isValidFinancialYear(normalized)) {
                      setDialogState(() {
                        errorText =
                            'Use YYYY-YYYY and ensure end year is start+1.';
                      });
                      return;
                    }
                    Navigator.pop(context, normalized);
                  },
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<TaxRecord?> _showImportPreviewDialog(PdfExtractionResult preview) {
    final selectedMappings = <int, String?>{};

    return showDialog<TaxRecord>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final confidencePercent = (preview.confidence * 100)
                .clamp(0, 100)
                .toStringAsFixed(0);
            return AlertDialog(
              title: Text(
                'Import Preview',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Parser: ${preview.parserName}',
                        style: GoogleFonts.inter(),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Confidence: $confidencePercent% (${preview.mappedEntryCount}/${preview.totalEntryCount} mapped)',
                        style: GoogleFonts.inter(),
                      ),
                      const SizedBox(height: 12),
                      if (preview.unmappedEntries.isEmpty)
                        Text(
                          'All extracted lines were mapped automatically.',
                          style: GoogleFonts.inter(color: Colors.green[700]),
                        )
                      else ...[
                        Text(
                          'Unmapped lines (choose destination categories):',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 280,
                          child: ListView.separated(
                            itemCount: preview.unmappedEntries.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 12),
                            itemBuilder: (context, index) {
                              final item = preview.unmappedEntries[index];
                              final options = item.isIncome
                                  ? TaxRecord.incomeCategoryOptions
                                  : TaxRecord.expenseCategoryOptions;
                              final selectedValue =
                                  selectedMappings[index] ??
                                  (!item.isIncome
                                      ? 'Sundry rental expenses'
                                      : null);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item.sourceCategory}  (\$${item.amount.toStringAsFixed(2)})',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    initialValue: selectedValue,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    hint: const Text('Select category'),
                                    items: options
                                        .map(
                                          (category) =>
                                              DropdownMenuItem<String>(
                                                value: category,
                                                child: Text(category),
                                              ),
                                        )
                                        .toList(),
                                    onChanged: (value) {
                                      setDialogState(() {
                                        selectedMappings[index] = value;
                                      });
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ],
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
                    final adjustedRecord = preview.record.copyWith(
                      income: Map<String, double>.from(preview.record.income),
                      expenses: Map<String, double>.from(
                        preview.record.expenses,
                      ),
                    );

                    for (int i = 0; i < preview.unmappedEntries.length; i++) {
                      final item = preview.unmappedEntries[i];
                      final mappedCategory =
                          selectedMappings[i] ??
                          (!item.isIncome ? 'Sundry rental expenses' : null);

                      if (mappedCategory == null) {
                        continue;
                      }

                      if (item.isIncome) {
                        adjustedRecord.income[mappedCategory] =
                            (adjustedRecord.income[mappedCategory] ?? 0.0) +
                            item.amount;
                      } else {
                        adjustedRecord.expenses[mappedCategory] =
                            (adjustedRecord.expenses[mappedCategory] ?? 0.0) +
                            item.amount;
                      }
                    }

                    Navigator.pop(context, adjustedRecord);
                  },
                  child: const Text('Continue to Worksheet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _defaultFinancialYear() {
    final now = DateTime.now();
    final startYear = now.month >= 7 ? now.year : now.year - 1;
    return '$startYear-${startYear + 1}';
  }

  List<String> _financialYearOptions() {
    final defaultYear = _defaultFinancialYear();
    final start = int.parse(defaultYear.split('-').first);
    return List.generate(7, (index) {
      final year = start - index;
      return '$year-${year + 1}';
    });
  }

  bool _isValidFinancialYear(String value) {
    if (!_financialYearRegex.hasMatch(value)) {
      return false;
    }
    final years = value.split('-');
    final start = int.tryParse(years[0]);
    final end = int.tryParse(years[1]);
    if (start == null || end == null) {
      return false;
    }
    return end == start + 1;
  }

  void _showSnackBar(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Tax Auto Extraction',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Trends & Comparison',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ComparisonScreen(
                    firestoreService: _firestoreService,
                    userId: user?.uid,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await _authService.signOut();
            },
          ),
        ],
      ),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildUploadSection(),
                  const SizedBox(height: 32),
                  Text(
                    'Saved Records',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: StreamBuilder<List<TaxRecord>>(
                      stream: _firestoreService.getUserTaxRecords(user.uid),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return Center(
                            child: Text(
                              'No records found. Upload a PDF to begin.',
                              style: GoogleFonts.inter(color: Colors.grey[600]),
                            ),
                          );
                        }

                        final records = snapshot.data!;
                        return ListView.separated(
                          itemCount: records.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final record = records[index];
                            return _buildRecordCard(record);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildUploadSection() {
    return InkWell(
      onTap: _isProcessing ? null : _pickAndProcessPdf,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            width: 2,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            if (_isProcessing)
              const CircularProgressIndicator()
            else
              Icon(
                Icons.upload_file_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            const SizedBox(height: 16),
            Text(
              _isProcessing
                  ? 'Extracting Data...'
                  : 'Upload Property Summary PDF',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Supports Forge + generic property statement layouts',
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordCard(TaxRecord record) {
    final net = record.netPosition;
    final isPositive = net >= 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        title: Text(
          'FY ${record.financialYear}',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Income: \$${record.totalIncome.toStringAsFixed(2)}'),
              Text('Expenses: \$${record.totalExpenses.toStringAsFixed(2)}'),
            ],
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Net Position',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
            ),
            Text(
              '\$${net.toStringAsFixed(2)}',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isPositive ? Colors.green[700] : Colors.red[700],
              ),
            ),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => WorksheetScreen(
                record: record,
                firestoreService: _firestoreService,
              ),
            ),
          );
        },
      ),
    );
  }
}
