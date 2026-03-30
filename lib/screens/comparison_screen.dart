import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/tax_record.dart';
import '../services/firestore_service.dart';
import 'auth_screen.dart';

class ComparisonScreen extends StatefulWidget {
  final FirestoreService? firestoreService;
  final String? userId;

  const ComparisonScreen({super.key, this.firestoreService, this.userId});

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  late final FirestoreService _firestoreService;

  @override
  void initState() {
    super.initState();
    _firestoreService = widget.firestoreService ?? FirestoreService();
  }

  @override
  Widget build(BuildContext context) {
    // IMPORTANT: In widget tests (and some non-Firebase contexts), Firebase may
    // not be initialized. Accessing FirebaseAuth.instance would throw. We only
    // consult FirebaseAuth when we actually need it, and we guard access.
    String? currentUid;
    try {
      currentUid = FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      currentUid = null;
    }

    // Prefer an explicitly provided userId (tests pass this in, and it avoids
    // touching FirebaseAuth if Firebase isn't initialized).
    String? safeUserId = widget.userId;

    // If no userId was provided, require an authenticated user.
    if (safeUserId == null) {
      if (currentUid == null) {
        // If user navigates here via browser history after sign-out, block access.
        return const AuthScreen();
      }
      safeUserId = currentUid;
    }

    // Defense-in-depth: if both are available but differ, always use the
    // authenticated user's uid.
    if (currentUid != null && safeUserId != currentUid) {
      safeUserId = currentUid;
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Yearly Comparison',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      body: SelectionArea(
        child: StreamBuilder<List<TaxRecord>>(
          stream: _firestoreService.getUserTaxRecords(safeUserId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(
                child: Text(
                  'No data available for comparison.',
                  style: GoogleFonts.inter(color: Colors.grey[600]),
                ),
              );
            }

            final records = snapshot.data!;
            // Sort records by financialYear ascending
            records.sort((a, b) => a.financialYear.compareTo(b.financialYear));

            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Income vs Expenses vs Net Position',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _buildLegend(),
                  const SizedBox(height: 32),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.only(right: 24, top: 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: BarChart(_buildChartData(records)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegendItem(Colors.green[400]!, 'Income'),
        const SizedBox(width: 16),
        _buildLegendItem(Colors.red[400]!, 'Expenses'),
        const SizedBox(width: 16),
        _buildLegendItem(Colors.blue[600]!, 'Net Position'),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      children: [
        Container(width: 16, height: 16, color: color),
        const SizedBox(width: 8),
        Text(text, style: GoogleFonts.inter(fontSize: 14)),
      ],
    );
  }

  BarChartData _buildChartData(List<TaxRecord> records) {
    double maxY = 0;
    List<BarChartGroupData> barGroups = [];

    for (int i = 0; i < records.length; i++) {
      final record = records[i];
      final income = record.totalIncome;
      final expense = record.totalExpenses;
      final net = record.netPosition;

      if (income > maxY) maxY = income;
      if (expense > maxY) maxY = expense;
      if (net.abs() > maxY) maxY = net.abs();

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: income,
              color: Colors.green[400],
              width: 16,
              borderRadius: BorderRadius.circular(4),
            ),
            BarChartRodData(
              toY: expense,
              color: Colors.red[400],
              width: 16,
              borderRadius: BorderRadius.circular(4),
            ),
            BarChartRodData(
              toY: net,
              color: Colors.blue[600],
              width: 16,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: maxY * 1.2,
      minY: 0,
      barGroups: barGroups,
      titlesData: FlTitlesData(
        show: true,
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (double value, TitleMeta meta) {
              int index = value.toInt();
              if (index >= 0 && index < records.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    records[index].financialYear,
                    style: GoogleFonts.inter(fontSize: 12),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
            reservedSize: 32,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (double value, TitleMeta meta) {
              if (value == 0) return const SizedBox.shrink();
              return Text(
                '\$${(value / 1000).toStringAsFixed(0)}k',
                style: GoogleFonts.inter(fontSize: 12),
              );
            },
            reservedSize: 40,
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY > 0 ? maxY / 4 : 1,
        getDrawingHorizontalLine: (value) {
          return FlLine(color: Colors.grey[300], strokeWidth: 1);
        },
      ),
      borderData: FlBorderData(show: false),
    );
  }
}
