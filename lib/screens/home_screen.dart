import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/pdf_extraction_service.dart';
import '../models/tax_record.dart';
import 'worksheet_screen.dart';
import 'comparison_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final PdfExtractionService _pdfExtractionService = PdfExtractionService();
  
  bool _isProcessing = false;

  Future<void> _pickAndProcessPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );

    if (result != null && result.files.single.bytes != null) {
      final bytes = result.files.single.bytes!;
      
      // Prompt for financial year
      final year = await _showYearDialog();
      if (year == null || year.isEmpty) return;

      setState(() {
        _isProcessing = true;
      });

      try {
        final userId = FirebaseAuth.instance.currentUser!.uid;
        final record = await _pdfExtractionService.extractFromPdf(bytes, userId, year);
        
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => WorksheetScreen(record: record),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to process PDF: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
      }
    }
  }

  Future<String?> _showYearDialog() {
    String selectedYear = '2024-2025';
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Select Financial Year', style: GoogleFonts.inter()),
          content: TextField(
            onChanged: (val) => selectedYear = val,
            decoration: const InputDecoration(
              hintText: 'e.g., 2024-2025',
              border: OutlineInputBorder(),
            ),
            controller: TextEditingController(text: selectedYear),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, selectedYear),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

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
                  builder: (context) => const ComparisonScreen(),
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
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
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
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
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
          color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
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
              _isProcessing ? 'Extracting Data...' : 'Upload Property Summary PDF',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Supports Forge Real Estate layout',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey[600],
              ),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
              builder: (context) => WorksheetScreen(record: record),
            ),
          );
        },
      ),
    );
  }
}
