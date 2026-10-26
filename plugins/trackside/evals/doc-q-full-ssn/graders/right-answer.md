---
type: llm
---

The RFC's section 4.2 says the KYC form takes the last four SSN digits, but decision AD-12, which is newer and overrides 4.2, says it takes the full SSN.
PASS if the reply says the form collects the full SSN.
FAIL if it says only the last four, or that it's unclear.
