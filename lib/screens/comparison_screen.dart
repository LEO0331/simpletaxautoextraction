import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/tax_record.dart';
import '../services/anomaly_service.dart';
import '../services/firestore_service.dart';
import '../widgets/stage_background.dart';
import 'auth_screen.dart';

class ComparisonScreen extends StatefulWidget {
  final FirestoreService? firestoreService;
  final String? userId;
  final String? propertyId;
  final String? propertyName;

  const ComparisonScreen({
    super.key,
    this.firestoreService,
    this.userId,
    this.propertyId,
    this.propertyName,
  });

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  late final FirestoreService _firestoreService;
  final AnomalyService _anomalyService = AnomalyService();

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
      appBar: AppBar(
        title: Text(
          'Yearly Comparison',
          style: GoogleFonts.dmSerifDisplay(
            fontSize: 34,
            color: Theme.of(context).colorScheme.primary,
            height: 1.0,
          ),
        ),
      ),
      body: StageBackground(
        child: SelectionArea(
          child: StreamBuilder<List<TaxRecord>>(
            stream: _firestoreService.getUserTaxRecords(safeUserId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: AppPanel(
                    child: Text(
                      'No data available for comparison.',
                      style: GoogleFonts.workSans(color: Colors.grey[700]),
                    ),
                  ),
                );
              }

              final records = (snapshot.data ?? const <TaxRecord>[])
                  .where(
                    (record) =>
                        widget.propertyId == null ||
                        record.propertyId == widget.propertyId,
                  )
                  .toList();
              final anomalies = _anomalyService.detectYearlyAnomalies(records);
              // Sort records by financialYear ascending
              records.sort(
                (a, b) => a.financialYear.compareTo(b.financialYear),
              );

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Income vs Expenses vs Net Position${widget.propertyName == null ? '' : ' (${widget.propertyName})'}',
                          style: GoogleFonts.dmSerifDisplay(
                            fontSize: 38,
                            height: 1.0,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (anomalies.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          AppPanel(
                            color: const Color(0xFFFFF0D9),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Anomaly Alerts',
                                  style: GoogleFonts.workSans(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ...anomalies.map(
                                  (alert) => Text(
                                    '• $alert',
                                    style: GoogleFonts.workSans(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        _buildLegend(),
                        const SizedBox(height: 24),
                        Expanded(
                          child: AppPanel(
                            padding: const EdgeInsets.only(
                              right: 24,
                              top: 24,
                              left: 8,
                              bottom: 12,
                            ),
                            child: BarChart(_buildChartData(records)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegendItem(const Color(0xFF2D6A4F), 'Income'),
        const SizedBox(width: 16),
        _buildLegendItem(const Color(0xFFBA3A3A), 'Expenses'),
        const SizedBox(width: 16),
        _buildLegendItem(const Color(0xFF102A43), 'Net Position'),
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
              color: const Color(0xFF2D6A4F),
              width: 16,
              borderRadius: BorderRadius.circular(4),
            ),
            BarChartRodData(
              toY: expense,
              color: const Color(0xFFBA3A3A),
              width: 16,
              borderRadius: BorderRadius.circular(4),
            ),
            BarChartRodData(
              toY: net,
              color: const Color(0xFF102A43),
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
