import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/services/tax_rule_registry.dart';

void main() {
  test(
    'Historical years are explicit and future reforms do not inherit rules',
    () {
      expect(TaxRuleRegistry.supportedYearStarts, [
        2020,
        2021,
        2022,
        2023,
        2024,
        2025,
      ]);
      expect(TaxRuleRegistry.supports(2019), isFalse);
      expect(TaxRuleRegistry.supports(2026), isFalse);
      expect(TaxRuleRegistry.supports(2027), isFalse);
      expect(
        TaxRuleRegistry.version(2024),
        'AU-individual-resident-2024-2025-v1',
      );
    },
  );
}
