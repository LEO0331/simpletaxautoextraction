# Tax source register

Version 1.0 - accessed/reviewed for architecture on 13 October 2026. These references support planning, not a certified or complete taxpayer-specific ruleset. No tax calculation engine has been implemented. The supplied plan's historical links remain unchanged; this register records their limits.

| ID | Source / topic | Access and applicability | Implementation gate |
|---|---|---|---|
| R01 | [ATO discount method](https://smallbusiness.taxsuperandyou.gov.au/capital-gains-tax/the-discount-method) | Full page retrieved; calendar holding period, losses and residency restrictions. Guidance alone does not cover future-year transitions | Independently reviewed fixtures for first supported historical years; no 365-day shortcut |
| R02 | [ITAA 1997, July 2026 compilation](https://www.legislation.gov.au/C2004A05138/2026-07-01/2026-07-01/text/original/epub/OEBPS/document_3/document_3.html), ss 104-107A-E | Retrieved during Phase 0; AMIT basis/E10 and adjustment timing provisions | Confirm applicable-year law and issuer-to-parcel attribution before definitive results |
| R03 | Same compilation, ss 104-160/165 | Event I1 and individual election provisions inspected for architecture | Confirm exemptions, temporary-resident treatment, asset classification and election scope; no automatic legal outcome |
| R04 | [ATO managed-fund CGT guidance](https://www.ato.gov.au/law/view/document?DocID=SAV%2FPIG%2F00008&PiT=99991231235958) | Indexed guidance available; full-page retrieval failed; historical 2024 guide | Revalidate for each year, including statement gross-up/component meaning and double-count prevention |
| R05 | [ATO historical AMIT payments guidance](https://www.ato.gov.au/forms-and-instructions/capital-gains-tax-guide-2021/whats-new/trust-distributions/non-assessable-payments-from-a-trust) | Supplied baseline reference; full-page retry returned access error | Historical starting point only; not independently approved for FY2025-26 |
| R06 | [ATO historical CGT recordkeeping](https://www.ato.gov.au/forms-and-instructions/capital-gains-tax-guide-2022/part-a-about-capital-gains-tax/keeping-records) | Supplied baseline reference; current applicability not verified | Check relevant-year acquisition/disposal and retention requirements |
| R07 | [ATO attribution to AMIT members](https://www.ato.gov.au/businesses-and-organisations/trusts/in-detail/managed-investment-trusts/managed-investment-trusts-overview/attribution-managed-investment-trusts/attribution-method-for-managed-investment-trusts/attributing-amounts-to-members) | Supplied baseline reference; full content not verified in this consolidation | Confirm statement requirements and each issuer/year mapping |
| R08 | [Treasury Laws Amendment (Tax Reform No. 1) Act 2026](https://www.legislation.gov.au/C2026A00049/asmade/2026-06-26/text/original/epub/OEBPS/document_1/document_1.html) | Full text retrieved and rechecked; application provisions include FY2027-28 CGT changes | Separate reviewed rule coverage for future years; do not apply historical ordering/discounts universally |
| R09 | [Treasury 2026-27 overview](https://treasury.gov.au/policy-topics/taxation/budget2026-27) | Retrieved during Phase 0; policy overview, not a substitute for enacted application provisions | Review effective dates and rental/CGT transitions before new-year support |

## Required rule-record fields

Rule ID/version; specific proposition and exceptions; financial years and event-date applicability; authoritative URL and section; access date and retrieval status; reviewed interpretation; reviewer and approval date; engine/fixture versions; known exclusions. Recheck the applicable compilation and amendments when approving a pack. A publication date or reachable URL is not approval.

Open coverage includes first target years, acquisition/disposal fee and GST treatment, reduced cost bases, leap-day boundaries, AMIT attribution/timing/E10, non-AMIT payments, DRP acquisition/residual cash, corporate actions/rollovers, loss origins and restrictions, residency transitions, foreign currency, rental deductibility and future reforms. Unsupported facts/rules return NeedsTaxReview.

Change log: 2026-10-13 - initial register distinguishes retrieved, indexed-only and unverified sources; functional rule approval remains outstanding.
