#!/usr/bin/env bash
# Builds the demo project every trackside eval starts from, in the run's empty workspace: two repos (api, web), a
# design doc, and a trackside folder with one feature (demo) and two tracks (tickets, research). tests/live.sh starts
# each journey from it too.
set -euo pipefail
mkdir -p api web docs .trackside/demo/tickets .trackside/demo/research

cat > api/app.js <<'EOF'
function applyDiscount(total, code) {
  return total;
}
module.exports = { applyDiscount };
EOF

cat > web/index.html <<'EOF'
<!doctype html>
<title>Shop</title>
<p>Cart total: <span id="total"></span></p>
EOF

cat > docs/spec.md <<'EOF'
# Shop discounts: design doc

## Goal
Let shoppers apply one discount code at checkout.

## Rules
- One code per order.
- A code never makes the total negative.
- The web shows the discounted total before payment.

## API
`applyDiscount(total, code)` in `api/app.js` returns the new total.

## Open questions
- Do codes expire?
EOF

cat > .trackside/demo/FEATURE.md <<'EOF'
# Feature: demo

**Goal:** Shoppers can apply one discount code at checkout.

**Source docs:** `docs/spec.md`

**Decisions:** `DECISIONS.md` in this folder

**Repos:** api, web

**Planning:** none

**Rules for this feature:**
- A discount never makes the total negative.
EOF

cat > .trackside/demo/DECISIONS.md <<'EOF'
# Decisions: demo

## D-001 · 2026-10-20 · Only one discount code per order
- **Status:** accepted
- **Rejected:** stacking codes, because totals get hard to explain at checkout
- **Reasoning:** simplest rule that matches the design doc
- **Affects:** demo/tickets, api/app.js
EOF

cat > .trackside/demo/tickets/CONTEXT.md <<'EOF'
# Track: demo/tickets

**Goal:** Build the discount feature, one ticket at a time.

**Not here:** Open product questions (that's demo/research).

**Rules for this track:**
- Run `node -e "require('./api/app.js')"` after each change.
EOF

cat > .trackside/demo/research/CONTEXT.md <<'EOF'
# Track: demo/research

**Goal:** Answer the open questions in the design doc.

**Not here:** Code changes (that's demo/tickets).

**Rules for this track:**
- Record answers as decisions in DECISIONS.md.
EOF

state() {
  cat <<EOF
# State: $1

## Inbox

## Current
- $2

## Next step

## Tickets
$3

## Done log

## Dead ends

## Gotchas

## Open questions / Blocked
EOF
}
state demo/tickets "Ticket: none [verified]" '- [ ] T-1: apply a percentage code in applyDiscount — acceptance: applyDiscount(100, "TEN") returns 90
- [ ] T-2: never return a negative total — acceptance: applyDiscount(5, "BIG") returns 0
- [ ] T-3: show the discounted total on the web page — acceptance: index.html shows it' > .trackside/demo/tickets/STATE.md
state demo/research "Ticket: none" '- [ ] Q-1: do discount codes expire? — acceptance: a decision in DECISIONS.md' > .trackside/demo/research/STATE.md
printf '# Notes: demo/tickets\n' > .trackside/demo/tickets/NOTES.md
printf '# Notes: demo/research\n' > .trackside/demo/research/NOTES.md

for r in api web .trackside; do
  git -C "$r" init -q -b main
  git -C "$r" config user.name eval
  git -C "$r" config user.email eval@example.com
  git -C "$r" add -A
  git -C "$r" commit -q -m "Start $r"
done
