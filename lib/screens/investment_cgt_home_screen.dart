import 'package:flutter/material.dart';

import '../widgets/stage_background.dart';
import 'investment_cgt_routes.dart';

class InvestmentCgtHomeScreen extends StatelessWidget {
  const InvestmentCgtHomeScreen({super.key});

  static const disclaimer =
      'This is an estimate only and does not constitute tax advice. '
      'Please confirm with a qualified accountant or tax adviser.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Investment CGT Tracker')),
      body: StageBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const AppPanel(
                  child: Text(
                    'Track broker PDF trades, review extracted transaction '
                    'details, and estimate unrealised gain/loss with potential '
                    'CGT discount eligibility indicators.',
                  ),
                ),
                const SizedBox(height: 16),
                _ActionCard(
                  title: 'Upload trade confirmation PDFs',
                  onTap: () =>
                      Navigator.pushNamed(context, InvestmentCgtRoutes.upload),
                ),
                const SizedBox(height: 12),
                _ActionCard(
                  title: 'View saved transactions',
                  onTap: () => Navigator.pushNamed(
                    context,
                    InvestmentCgtRoutes.transactions,
                  ),
                ),
                const SizedBox(height: 12),
                _ActionCard(
                  title: 'Run CGT estimate',
                  onTap: () => Navigator.pushNamed(
                    context,
                    InvestmentCgtRoutes.calculate,
                  ),
                ),
                const SizedBox(height: 16),
                const AppPanel(
                  color: Color(0xFFFFF7E6),
                  child: Text(
                    disclaimer,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _ActionCard({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: ListTile(
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
