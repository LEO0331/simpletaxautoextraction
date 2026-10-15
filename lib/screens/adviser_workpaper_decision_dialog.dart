import 'package:flutter/material.dart';
import '../models/adviser_workpaper_decision.dart';
import '../models/tax_workspace.dart' show taxWorkspaceTotals;
import '../services/adviser_workpaper_decision_service.dart';

Future<AdviserWorkpaperDecision?> showAdviserWorkpaperDecisionDialog(
  BuildContext context, {
  required int yearStart,
  required String scopeFingerprint,
  required Map<String, String> categoryTotals,
  required List<String> issues,
  AdviserWorkpaperDecision? existing,
  Future<AdviserWorkpaperDecision?> Function(WidgetBuilder builder)? present,
}) async {
  final adviser = TextEditingController(text: existing?.adviserReference ?? '');
  final evidence = TextEditingController(
    text: existing?.evidenceReference ?? '',
  );
  final rule = TextEditingController(text: existing?.ruleVersion ?? '');
  final losses = TextEditingController(
    text:
        existing?.closingLossBalances
            .map(
              (b) => '${b.originStartYear}|${b.amount}|${b.evidenceReference}',
            )
            .join('\n') ??
        '',
  );
  final totals = {
    for (final key in taxWorkspaceTotals)
      key: TextEditingController(
        text: existing?.totals[key] ?? categoryTotals[key] ?? '0',
      ),
  };
  final covered = <String>{...?existing?.legalIssuesCovered};
  bool reviewed = false, complete = false;
  String? error;
  try {
    Future<AdviserWorkpaperDecision?> presentDialog({
      required WidgetBuilder builder,
    }) async {
      if (present != null) return present(builder);
      final route = DialogRoute<AdviserWorkpaperDecision>(
        context: context,
        builder: builder,
      );
      final result = await Navigator.of(
        context,
        rootNavigator: true,
      ).push(route);
      // Controllers must outlive the TextFields during the route's exit animation.
      await route.completed;
      return result;
    }

    return await presentDialog(
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Adviser-supplied workpaper $yearStart–${yearStart + 1}'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter the complete annual category totals from an evidenced adviser workpaper. These replace all worksheet totals once. They do not calculate tax liability or lodge a return. Missing documents and unreviewed facts still block finalisation.',
                  ),
                  TextField(
                    controller: adviser,
                    onChanged: (_) => setState(() => reviewed = false),
                    decoration: const InputDecoration(
                      labelText: 'Adviser reference',
                    ),
                  ),
                  TextField(
                    controller: evidence,
                    onChanged: (_) => setState(() => reviewed = false),
                    decoration: const InputDecoration(
                      labelText: 'Complete annual workpaper evidence reference',
                    ),
                  ),
                  TextField(
                    controller: rule,
                    onChanged: (_) => setState(() => reviewed = false),
                    decoration: const InputDecoration(
                      labelText:
                          'Adviser rule version / determination reference',
                    ),
                  ),
                  for (final key in taxWorkspaceTotals)
                    TextField(
                      controller: totals[key],
                      onChanged: (_) => setState(() => reviewed = false),
                      decoration: InputDecoration(labelText: key),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                    ),
                  TextField(
                    controller: losses,
                    onChanged: (_) => setState(() => reviewed = false),
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText:
                          'Closing capital losses (one per originating year)',
                      helperText:
                          'YYYY | amount | evidence reference. Leave empty for reviewed zero losses.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Legal issues explicitly covered by this complete workpaper',
                  ),
                  for (final issue in issues.where(adviserCoverableIssue))
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(issue),
                      value: covered.contains(issue),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          covered.add(issue);
                        } else {
                          covered.remove(issue);
                        }
                        reviewed = false;
                      }),
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'The adviser workpaper covers every asset, financial source, residency period and applicable election in this year.',
                    ),
                    value: complete,
                    onChanged: (value) =>
                        setState(() => complete = value == true),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'I reviewed all totals and closing loss balances against the adviser workpaper.',
                    ),
                    value: reviewed,
                    onChanged: (value) =>
                        setState(() => reviewed = value == true),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final balances = <AdviserClosingLossBalance>[];
                  for (final line
                      in losses.text
                          .split('\n')
                          .where((line) => line.trim().isNotEmpty)) {
                    final parts = line.split('|');
                    if (parts.length != 3) {
                      throw const FormatException(
                        'Use YYYY | amount | evidence for each loss balance',
                      );
                    }
                    balances.add(
                      AdviserClosingLossBalance(
                        originStartYear: int.parse(parts[0].trim()),
                        amount: parts[1].trim(),
                        evidenceReference: parts[2].trim(),
                      ),
                    );
                  }
                  final decision = AdviserWorkpaperDecision(
                    yearStart: yearStart,
                    sourceFingerprint: scopeFingerprint,
                    adviserReference: adviser.text.trim(),
                    evidenceReference: evidence.text.trim(),
                    ruleVersion: rule.text.trim(),
                    totals: totals.map(
                      (key, controller) =>
                          MapEntry(key, controller.text.trim()),
                    ),
                    closingLossBalances: balances,
                    legalIssuesCovered: covered.toList(),
                    reviewed: reviewed,
                    completeSources: complete,
                  );
                  final invalid = decision.validation();
                  if (invalid.isNotEmpty) {
                    throw FormatException(invalid.join('\n'));
                  }
                  Navigator.pop(context, decision);
                } on FormatException catch (problem) {
                  setState(() => error = problem.message);
                }
              },
              child: const Text('Save reviewed adviser workpaper'),
            ),
          ],
        ),
      ),
    );
  } finally {
    for (final controller in [
      adviser,
      evidence,
      rule,
      losses,
      ...totals.values,
    ]) {
      controller.dispose();
    }
  }
}
