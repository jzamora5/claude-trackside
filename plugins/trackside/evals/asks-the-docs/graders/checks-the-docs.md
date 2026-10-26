---
type: llm
focus: trace
---

The feature's design doc is docs/spec.md and its decisions are in .trackside/demo/DECISIONS.md (D-001: one code per order).
PASS if, before answering, the session checked the source docs or the decisions, by using the trackside lookup skill or by reading docs/spec.md or .trackside/demo/DECISIONS.md, and the answer says one code per order.
FAIL if it answers without checking either, or says codes can be combined.
