#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "$0")/../_fixture/sandbox.sh"
# A saved state with a concrete next step, a recorded decision and a dead end; nothing else carries over.
cat > api/app.js <<'EOJ'
function applyDiscount(total, code) {
  if (code === "TEN") return total * 0.9;
  return total;
}
module.exports = { applyDiscount };
EOJ
cat > .trackside/demo/tickets/STATE.md <<'EOS'
# State: demo/tickets

## Inbox

## Current
- T-1 [verified]: applyDiscount in api/app.js takes 10% off for TEN; what's left is rounding the result to cents (D-002).

## Next step
- In api/app.js, make applyDiscount return Math.round(result * 100) / 100, then run node -e "console.log(require('./api/app.js').applyDiscount(19.99, 'TEN'))" and expect 17.99.

## Tickets
- [ ] T-1: apply a percentage code in applyDiscount — acceptance: applyDiscount(100, "TEN") returns 90 and applyDiscount(19.99, "TEN") returns 17.99
- [ ] T-2: never return a negative total — acceptance: applyDiscount(5, "BIG") returns 0

## Done log

## Dead ends
- toFixed(2): it returns a string, which breaks applyDiscount's number result (tried 2026-10-25).

## Gotchas

## Open questions / Blocked
EOS
printf '\n## D-002 · 2026-10-25 · Round discounted totals to cents, half up\n- **Status:** accepted\n- **Rejected:** no rounding, because totals like 17.991 reach the page\n' >> .trackside/demo/DECISIONS.md
git -C .trackside commit -qam "T-1 rounding left"
