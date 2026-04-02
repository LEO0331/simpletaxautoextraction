import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/tax_record.dart';
import '../services/auth_service.dart';
import '../services/draft_sync_service.dart';
import '../services/export_service.dart';
import '../services/firestore_service.dart';
import '../services/pdf_extraction_service.dart';
import '../utils/file_exporter.dart';
import '../widgets/stage_background.dart';
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
  final ExportService _exportService = ExportService();

  bool _isProcessing = false;
  bool _isSyncingDrafts = false;
  String _selectedPropertyId = 'default';
  String _selectedPropertyName = 'Primary Property';
  List<TaxRecord> _latestRecords = const [];
  Map<String, String> _customIncomeMappings = const {};
  Map<String, String> _customExpenseMappings = const {};

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _firestoreService = widget.firestoreService ?? FirestoreService();
    _pdfExtractionService =
        widget.pdfExtractionService ?? PdfExtractionService();
    _loadCustomMappings();
    _syncQueuedDrafts();
    _ensureDefaultPropertyExists();
  }

  Future<void> _ensureDefaultPropertyExists() async {
    final user = _authService.currentUser;
    if (user == null) {
      return;
    }
    try {
      await _firestoreService.saveProperty(
        user.uid,
        const PropertyInfo(id: 'default', name: 'Primary Property'),
      );
    } catch (_) {
      // Some tests/mock services do not implement property persistence.
    }
  }

  Future<void> _loadCustomMappings() async {
    final user = _authService.currentUser;
    if (user == null) {
      return;
    }
    Map<String, Map<String, String>> mappings;
    try {
      mappings = await _firestoreService.getCustomMappings(user.uid);
    } catch (_) {
      mappings = const {'income': {}, 'expense': {}};
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _customIncomeMappings = mappings['income'] ?? const {};
      _customExpenseMappings = mappings['expense'] ?? const {};
    });
  }

  Future<void> _syncQueuedDrafts() async {
    if (_isSyncingDrafts) {
      return;
    }
    setState(() {
      _isSyncingDrafts = true;
    });
    final synced = await DraftSyncService.instance.syncAll(_firestoreService);
    if (mounted && synced > 0) {
      _showSnackBar('Synced $synced offline draft(s).');
    }
    if (mounted) {
      setState(() {
        _isSyncingDrafts = false;
      });
    }
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
        propertyId: _selectedPropertyId,
        propertyName: _selectedPropertyName,
        sourceFileName: file.name,
        customIncomeMappings: _customIncomeMappings,
        customExpenseMappings: _customExpenseMappings,
      );

      final reviewedRecord = await _showImportPreviewDialog(preview);
      if (reviewedRecord == null || !mounted) {
        return;
      }

      final continueImport = await _showOverwriteDiffIfNeeded(
        refreshedUser.uid,
        reviewedRecord,
      );
      if (!continueImport || !mounted) {
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

  Future<bool> _showOverwriteDiffIfNeeded(
    String userId,
    TaxRecord candidate,
  ) async {
    final existing = await _firestoreService.findRecordByYear(
      userId,
      candidate.financialYear,
      propertyId: candidate.propertyId,
    );

    if (existing == null || !mounted) {
      return true;
    }

    final diffs = <String>[];
    if (existing.totalIncome != candidate.totalIncome) {
      diffs.add(
        'Income: \$${existing.totalIncome.toStringAsFixed(2)} -> \$${candidate.totalIncome.toStringAsFixed(2)}',
      );
    }
    if (existing.totalExpenses != candidate.totalExpenses) {
      diffs.add(
        'Expenses: \$${existing.totalExpenses.toStringAsFixed(2)} -> \$${candidate.totalExpenses.toStringAsFixed(2)}',
      );
    }
    if (existing.lineItems.length != candidate.lineItems.length) {
      diffs.add(
        'Transaction line items: ${existing.lineItems.length} -> ${candidate.lineItems.length}',
      );
    }

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Existing Record Found', style: GoogleFonts.inter()),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FY ${candidate.financialYear} already exists for ${candidate.propertyName}.',
                    style: GoogleFonts.inter(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Potential changes:',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (diffs.isEmpty)
                    Text(
                      'No numeric difference detected.',
                      style: GoogleFonts.inter(),
                    )
                  else
                    ...diffs.map(
                      (diff) => Text('• $diff', style: GoogleFonts.inter()),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showMappingRulesDialog() async {
    final user = _authService.currentUser;
    if (user == null) {
      _showSnackBar('Please sign in again.');
      return;
    }

    final incomeController = TextEditingController(
      text: _customIncomeMappings.entries
          .map((e) => '${e.key}=${e.value}')
          .join('\n'),
    );
    final expenseController = TextEditingController(
      text: _customExpenseMappings.entries
          .map((e) => '${e.key}=${e.value}')
          .join('\n'),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Custom Mapping Rules', style: GoogleFonts.inter()),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Format: keyword=ATO Category', style: GoogleFonts.inter()),
              const SizedBox(height: 10),
              Text(
                'Income Rules',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: incomeController,
                maxLines: 6,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Text(
                'Expense Rules',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: expenseController,
                maxLines: 8,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) {
      return;
    }

    final income = _parseMappings(incomeController.text);
    final expense = _parseMappings(expenseController.text);

    await _firestoreService.saveCustomMappings(user.uid, income, expense);
    if (!mounted) {
      return;
    }

    setState(() {
      _customIncomeMappings = income;
      _customExpenseMappings = expense;
    });

    _showSnackBar('Custom mappings saved.');
  }

  Map<String, String> _parseMappings(String text) {
    final mappings = <String, String>{};
    final lines = text.split('\n');
    for (final line in lines) {
      if (!line.contains('=')) {
        continue;
      }
      final split = line.split('=');
      if (split.length < 2) {
        continue;
      }
      final key = split.first.trim();
      final value = split.sublist(1).join('=').trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      mappings[key] = value;
    }
    return mappings;
  }

  Future<void> _showAddPropertyDialog() async {
    final user = _authService.currentUser;
    if (user == null) {
      return;
    }
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Property', style: GoogleFonts.inter()),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Property Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (created != true) {
      return;
    }

    final name = controller.text.trim();
    if (name.isEmpty) {
      return;
    }

    final id = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    await _firestoreService.saveProperty(
      user.uid,
      PropertyInfo(id: id, name: name),
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _selectedPropertyId = id;
      _selectedPropertyName = name;
    });
  }

  Future<void> _exportCsv({bool excelFriendly = false}) async {
    if (_latestRecords.isEmpty) {
      _showSnackBar('No records to export.');
      return;
    }

    final content = excelFriendly
        ? _exportService.buildExcelFriendlyContent(_latestRecords)
        : _exportService.buildCsv(_latestRecords);

    final saved = await saveTextFile(
      '${_selectedPropertyId}_${excelFriendly ? 'excel' : 'records'}.csv',
      content,
    );

    if (!saved && mounted) {
      await Clipboard.setData(ClipboardData(text: content));
      _showSnackBar('Export copied to clipboard (save dialog unavailable).');
      return;
    }

    _showSnackBar(
      excelFriendly ? 'Excel-friendly CSV exported.' : 'CSV exported.',
    );
  }

  Future<void> _exportSummaryPdf() async {
    if (_latestRecords.isEmpty) {
      _showSnackBar('No records to export.');
      return;
    }

    final bytes = _exportService.buildSummaryPdf(
      _latestRecords,
      title: 'Tax Summary - $_selectedPropertyName',
    );
    final saved = await saveBinaryFile(
      '${_selectedPropertyId}_summary.pdf',
      bytes,
    );
    if (!saved) {
      _showSnackBar('Unable to save PDF on this platform.');
      return;
    }
    _showSnackBar('Summary PDF exported.');
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
                      const SizedBox(height: 6),
                      Text(
                        'Parsed transactions: ${preview.record.lineItems.length}',
                        style: GoogleFonts.inter(color: Colors.grey[700]),
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
    final primary = Theme.of(context).colorScheme.primary;
    final accent = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Tax Auto Extraction',
          style: GoogleFonts.dmSerifDisplay(
            fontSize: 34,
            color: primary,
            height: 1.0,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'compare':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ComparisonScreen(
                        firestoreService: _firestoreService,
                        userId: user?.uid,
                        propertyId: _selectedPropertyId,
                        propertyName: _selectedPropertyName,
                      ),
                    ),
                  );
                  break;
                case 'csv':
                  _exportCsv();
                  break;
                case 'excel':
                  _exportCsv(excelFriendly: true);
                  break;
                case 'pdf':
                  _exportSummaryPdf();
                  break;
                case 'mapping':
                  _showMappingRulesDialog();
                  break;
                case 'property':
                  _showAddPropertyDialog();
                  break;
                case 'sync':
                  _syncQueuedDrafts();
                  break;
                default:
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'compare',
                child: Text('Trends & Comparison'),
              ),
              PopupMenuItem(value: 'csv', child: Text('Export CSV')),
              PopupMenuItem(value: 'excel', child: Text('Export Excel CSV')),
              PopupMenuItem(value: 'pdf', child: Text('Export Summary PDF')),
              PopupMenuItem(
                value: 'mapping',
                child: Text('Custom Mapping Rules'),
              ),
              PopupMenuItem(value: 'property', child: Text('Add Property')),
              PopupMenuItem(value: 'sync', child: Text('Sync Offline Drafts')),
            ],
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
      body: StageBackground(
        child: SelectionArea(
          child: user == null
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildPropertySelector(user.uid),
                          if (DraftSyncService.instance.hasPendingDrafts)
                            Card(
                              color: const Color(0xFFFFF2D8),
                              child: ListTile(
                                title: Text(
                                  '${DraftSyncService.instance.pendingDrafts.length} offline draft(s) pending sync.',
                                ),
                                trailing: _isSyncingDrafts
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : TextButton(
                                        onPressed: _syncQueuedDrafts,
                                        child: const Text('Sync now'),
                                      ),
                              ),
                            ),
                          _buildUploadSection(),
                          const SizedBox(height: 22),
                          Row(
                            children: [
                              Text(
                                'Saved Records',
                                style: GoogleFonts.dmSerifDisplay(
                                  fontSize: 33,
                                  color: primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.20),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _selectedPropertyName,
                                  style: GoogleFonts.workSans(
                                    fontWeight: FontWeight.w600,
                                    color: primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: StreamBuilder<List<TaxRecord>>(
                              stream: _firestoreService.getUserTaxRecords(
                                user.uid,
                              ),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                final records = (snapshot.data ?? const [])
                                    .where(
                                      (record) =>
                                          record.propertyId ==
                                          _selectedPropertyId,
                                    )
                                    .toList();
                                _latestRecords = records;

                                if (records.isEmpty) {
                                  return Center(
                                    child: AppPanel(
                                      child: Text(
                                        'No records found. Upload a PDF to begin.',
                                        style: GoogleFonts.workSans(
                                          color: const Color(0xFF486581),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                return ListView.separated(
                                  itemCount: records.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 12),
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
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildPropertySelector(String userId) {
    return StreamBuilder<List<PropertyInfo>>(
      stream: _safePropertyStream(userId),
      builder: (context, snapshot) {
        final properties = snapshot.data ?? const [];
        final options = properties.isEmpty
            ? const [PropertyInfo(id: 'default', name: 'Primary Property')]
            : properties;

        final selectedExists = options.any((p) => p.id == _selectedPropertyId);
        if (!selectedExists) {
          _selectedPropertyId = options.first.id;
          _selectedPropertyName = options.first.name;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              Expanded(
                child: AppPanel(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedPropertyId,
                    decoration: const InputDecoration(
                      labelText: 'Property',
                      isDense: true,
                    ),
                    items: options
                        .map(
                          (property) => DropdownMenuItem<String>(
                            value: property.id,
                            child: Text(property.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      final selected = options.firstWhere(
                        (property) => property.id == value,
                      );
                      setState(() {
                        _selectedPropertyId = selected.id;
                        _selectedPropertyName = selected.name;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _showAddPropertyDialog,
                icon: const Icon(Icons.add_home_outlined),
                label: const Text('Add'),
              ),
            ],
          ),
        );
      },
    );
  }

  Stream<List<PropertyInfo>> _safePropertyStream(String userId) {
    try {
      return _firestoreService.getUserProperties(userId);
    } catch (_) {
      return Stream.value(const [
        PropertyInfo(id: 'default', name: 'Primary Property'),
      ]);
    }
  }

  Widget _buildUploadSection() {
    return InkWell(
      onTap: _isProcessing ? null : _pickAndProcessPdf,
      borderRadius: BorderRadius.circular(16),
      child: AppPanel(
        padding: const EdgeInsets.all(26),
        color: Colors.white.withValues(alpha: 0.72),
        border: Border.all(
          color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.4),
          width: 1.5,
        ),
        child: Column(
          children: [
            if (_isProcessing)
              const CircularProgressIndicator()
            else
              Icon(
                Icons.upload_file_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
            const SizedBox(height: 12),
            Text(
              _isProcessing
                  ? 'Extracting Data...'
                  : 'Upload Property Summary PDF',
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 34,
                color: Theme.of(context).colorScheme.primary,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Supports Forge + generic layouts, with custom mapping rules',
              style: GoogleFonts.workSans(
                fontSize: 14,
                color: const Color(0xFF486581),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Only your account can access saved records. Review before saving.',
              style: GoogleFonts.workSans(
                fontSize: 12,
                color: const Color(0xFF334E68),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
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
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        title: Text(
          'FY ${record.financialYear}',
          style: GoogleFonts.dmSerifDisplay(
            fontSize: 30,
            color: Theme.of(context).colorScheme.primary,
            height: 1.0,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Income: \$${record.totalIncome.toStringAsFixed(2)}',
                style: GoogleFonts.workSans(fontWeight: FontWeight.w500),
              ),
              Text(
                'Expenses: \$${record.totalExpenses.toStringAsFixed(2)}',
                style: GoogleFonts.workSans(fontWeight: FontWeight.w500),
              ),
              Text('Property: ${record.propertyName}'),
              Text('Transactions: ${record.lineItems.length}'),
              if (record.sourceFileName != null)
                Text('Source: ${record.sourceFileName}'),
              if (record.isLocked)
                Text('Locked', style: TextStyle(color: Colors.orange[700])),
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
