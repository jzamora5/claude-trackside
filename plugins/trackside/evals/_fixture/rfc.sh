#!/usr/bin/env bash
# Adds docs/rfc.md to the demo project: a long RFC (about 150 KB) whose answers sit in a few known places, one of them
# overridden by a later decision, and makes it a source doc of the demo feature. Run after sandbox.sh.
set -euo pipefail
awk 'BEGIN {
  print "# Checkout Platform RFC"; print ""
  print "## 1. Overview"; print "The checkout platform lets members pay with a stored balance."; print ""
  print "## 4. KYC"; print "Members verify their identity once, before their first balance."
  print "### 4.1 Who must verify"; print "Every member who opens a balance."
  print "### 4.2 The KYC form"; print "The form collects name, email, date of birth, address and the last four digits of the SSN."
  print "### 4.3 Where the form runs"; print "In our own page, with the SSN typed into an isolated field."; print ""
  print "## 9. Withdrawals"; print "Members move money out to their bank."
  print "### 9.3 Payout bank"; print "The payout bank is collected at the member'"'"'s first withdrawal, through the embedded account component, not during onboarding."; print ""
  for (s = 10; s <= 49; s++) {
    printf "## %d. Area %d\n", s, s
    for (p = 1; p <= 3; p++) {
      printf "### %d.%d Topic %d\n", s, p, p
      for (l = 1; l <= 10; l++) print "This paragraph describes area " s ", topic " p ", with the reasoning, the constraints and the open points a reader may need later on."
    }
  }
  print ""; print "## After-RFC Decisions"; print "Newer decisions override older sections."
  print "| ID | Date | Decision | Rejected |"; print "| --- | --- | --- | --- |"
  for (i = 1; i <= 30; i++) {
    if (i == 7) print "| AD-07 | 2026-09-02 | Build our own KYC form instead of the embedded onboarding component. | The embedded component can'"'"'t isolate the SSN field from our page, and its look doesn'"'"'t match the brand. |"
    else if (i == 12) print "| AD-12 | 2026-10-01 | The KYC form collects the full SSN, not the last four: the provider requires it for this account type. Overrides 4.2. | Last four only. |"
    else printf "| AD-%02d | 2026-09-%02d | Decision %d about area %d. | Another option for area %d. |\n", i, (i % 28) + 1, i, i + 9, i + 9
  }
}' > docs/rfc.md
awk '{ if ($0 ~ /^\*\*Source docs:\*\*/) print "**Source docs:** `docs/spec.md`, `docs/rfc.md`"; else if ($0 ~ /^\*\*Decisions:\*\*/) print "**Decisions:** the RFC'"'"'s After-RFC Decisions table, and `DECISIONS.md` in this folder"; else print }' .trackside/demo/FEATURE.md > .trackside/demo/FEATURE.tmp
mv .trackside/demo/FEATURE.tmp .trackside/demo/FEATURE.md
git -C .trackside commit -qam "Add the RFC as a source doc"
