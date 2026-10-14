import '../../models/investment_transaction.dart';
import '../../models/tax_decimal.dart';
import '../../models/document_coverage.dart';
import 'commsec_trade_confirmation_parser.dart';

/// Explicit-column CSV only. Never infers direction, currency or fees.
class BrokerCsvParser {
  List<InvestmentExtractionResult> parse(
    String text, {
    String? sourceFileName,
    bool confirmedAud = false,
  }) {
    if (text.length > 5 * 1024 * 1024) {
      throw const FormatException('CSV exceeds 5 MB.');
    }
    final rows = _rows(text);
    if (rows.length < 2) {
      throw const FormatException('CSV needs a header and transactions.');
    }
    if (rows.length > 1001) {
      throw const FormatException('Import up to 1,000 rows at once.');
    }
    final h = rows.first
        .map((v) => v.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .toList();
    String get(List<String> row, List<String> names) {
      final indices = [
        for (var i = 0; i < h.length; i++)
          if (names.contains(h[i])) i,
      ];
      if (indices.length != 1) return '';
      return row[indices.single].trim();
    }

    String? exact(String value) {
      try {
        final clean = value.replaceAll(r'$', '').replaceAll(',', '');
        final n = TaxDecimal.parse(clean);
        return n.isNegative ? null : n.toString();
      } catch (_) {
        return null;
      }
    }

    return [
      for (final row
          in rows.skip(1).where((r) => r.any((v) => v.trim().isNotEmpty)))
        (() {
          if (row.length != h.length) {
            throw const FormatException(
              'CSV row width differs from its header.',
            );
          }
          final dir = get(row, [
            'direction',
            'type',
            'buysell',
            'transactiontype',
          ]).toUpperCase();
          final currency = get(row, ['currency']).toUpperCase();
          if (currency != 'AUD' && !(currency.isEmpty && confirmedAud)) {
            throw const FormatException(
              'Only explicitly confirmed AUD imports are supported.',
            );
          }
          final dateRaw = get(row, ['tradedate', 'date']);
          DateTime? date = parseDocumentDate(dateRaw);
          final dm = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(dateRaw);
          if (dm != null) {
            date = parseDocumentDate('${dm[3]}-${dm[2]}-${dm[1]}');
          }
          final units = exact(get(row, ['units', 'quantity'])),
              gross = exact(
                get(row, [
                  'consideration',
                  'grossamount',
                  'grossconsideration',
                ]),
              ),
              fee = exact(get(row, ['brokerage', 'fees'])),
              total = exact(
                get(row, ['totalcost', 'netamount', 'netsettlement']),
              );
          final missing = <String>[
            if (!['BUY', 'SELL', 'BOUGHT', 'SOLD'].contains(dir))
              'transactionType',
            if (date == null) 'tradeDate',
            if (units == null) 'units',
            if (gross == null) 'consideration',
            if (fee == null) 'brokerage',
            if (total == null) 'totalCost',
          ];
          final ticker = get(row, ['ticker', 'code', 'securitycode']),
              name = get(row, ['securityname', 'description']);
          final account = get(row, ['account', 'accountnumber']),
              conf = get(row, [
                'confirmationnumber',
                'contractnumber',
                'reference',
              ]);
          if (ticker.isEmpty) missing.add('ticker');
          if (account.isEmpty) missing.add('accountNumber');
          if (conf.isEmpty) missing.add('confirmationNumber');
          final buy = ['BUY', 'BOUGHT'].contains(dir);
          if (gross != null &&
              fee != null &&
              total != null &&
              (buy
                      ? TaxDecimal.parse(gross) + TaxDecimal.parse(fee)
                      : TaxDecimal.parse(gross) - TaxDecimal.parse(fee)) !=
                  TaxDecimal.parse(total)) {
            missing.add('settlement reconciliation');
          }
          final broker = get(row, ['broker']).toLowerCase();
          return InvestmentExtractionResult(
            draft: InvestmentTransactionDraft(
              ticker: ticker,
              securityName: name.isEmpty ? ticker : name,
              transactionType: buy
                  ? InvestmentTransactionType.buy
                  : InvestmentTransactionType.sell,
              tradeDate: date,
              settlementDate: null,
              units: units == null ? null : double.parse(units),
              averagePrice:
                  units != null &&
                      gross != null &&
                      !TaxDecimal.parse(units).isZero
                  ? double.parse(
                      TaxDecimal.parse(gross)
                          .divide(TaxDecimal.parse(units), precision: 8)
                          .toString(),
                    )
                  : null,
              consideration: gross == null ? null : double.parse(gross),
              brokerage: fee == null ? null : double.parse(fee),
              gst: null,
              totalCost: total == null ? null : double.parse(total),
              confirmationNumber: conf,
              accountNumber: account,
              sourceFileName: sourceFileName,
              sourceParser: broker == 'commsec'
                  ? CommsecTradeConfirmationParser.parserName
                  : 'Canonical Broker CSV',
              parserVersion: 'csv-v1',
              notes:
                  'CSV source; verify all fields against original trade evidence.',
              needsReview: true,
              directionNeedsReview: ![
                'BUY',
                'SELL',
                'BOUGHT',
                'SOLD',
              ].contains(dir),
              unitsExact: units,
              considerationExact: gross,
              brokerageExact: fee,
              totalCostExact: total,
            ),
            confidence: missing.isEmpty ? 0.9 : 0.0,
            missingFields: missing,
            warnings: const ['Review every transaction before saving.'],
            rawText: '',
          );
        })(),
    ];
  }

  List<List<String>> _rows(String text) {
    final rows = <List<String>>[], row = <String>[];
    var cell = StringBuffer(), quoted = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == '"') {
        if (quoted && i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else if (!quoted && cell.isNotEmpty) {
          throw const FormatException('Malformed CSV quote.');
        } else {
          quoted = !quoted;
        }
      } else if (c == ',' && !quoted) {
        row.add(cell.toString());
        cell = StringBuffer();
      } else if ((c == '\n' || c == '\r') && !quoted) {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString());
        rows.add(List.of(row));
        row.clear();
        cell = StringBuffer();
      } else {
        cell.write(c);
      }
    }
    if (quoted) throw const FormatException('Unclosed CSV quote.');
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }
    return rows;
  }
}
