# Home Refinance Closing Workflow

This workflow covers a typical U.S. residential mortgage refinance from application through post-closing. Requirements and timing vary by lender, loan program, and state.

## Parties

| Party | Definition |
|---|---|
| Borrower (B) | Homeowner refinancing the existing mortgage. |
| Loan officer (LO) | Lender representative who originates the loan and guides the borrower. |
| Loan processor (P) | Lender representative who assembles the file, coordinates conditions, and prepares it for closing. |
| Underwriter (U) | Lender risk approver who determines whether the loan meets credit, collateral, and compliance requirements. |
| Appraiser (AP) | Independent professional or valuation provider who establishes property value. |
| Title/settlement agent (TS) | Company or agent that completes title work, coordinates settlement, disburses funds, and manages recording. |
| Notary (N) | Authorized person who verifies identity and witnesses notarized signatures. |
| County recorder (CR) | Public office that records the mortgage or deed of trust; its outcome is recorded in Autoclose by the title/settlement agent. |

**RACI:** **R** = performs the work; **A** = ultimately answerable for the outcome; **C** = consulted; **I** = informed. More than one party may be Responsible, but each step has one Accountable party.

| Step | Activity | B | LO | P | U | AP | TS | N | CR |
|---|---|---|---|---|---|---|---|---|---|
| 1. Apply | Submit application and authorize verification. | R | A | C |  |  |  |  |  |
| 2. Disclose | Issue required disclosures; borrower reviews and acknowledges. | R | R/A | I |  |  |  |  |  |
| 3. Process | Collect and validate income, assets, insurance, mortgage, and property information. | C | I | R/A | I |  |  |  |  |
| 4. Appraise | Determine the property's value when a valuation is required. | C | C | A | I | R |  |  |  |
| 5. Title | Identify title issues and obtain payoff information. | C |  | C | I |  | R/A |  |  |
| 6. Underwrite | Evaluate the loan and issue approval or conditions. | I | I | C | R/A |  |  |  |  |
| 7. Clear conditions | Resolve underwriting and title requirements; confirm clear to close. | C | I | R | A |  | C |  |  |
| 8. Prepare closing | Finalize figures, deliver the Closing Disclosure, and schedule signing. | R | C | R/A |  |  | R | I |  |
| 9. Sign | Verify identity, sign documents, and provide required funds. | R |  | I |  |  | A | R |  |
| 10. Rescission | Monitor the applicable right-to-cancel period before funding. | I | I | R/A |  |  | C |  |  |
| 11. Fund and disburse | Fund the loan, pay approved obligations, and release proceeds. | I | I | R/A |  |  | R |  |  |
| 12. Record and close | Record the security instrument, confirm payoff, and issue final documents. | I | I | I |  |  | R/A |  | R |


## Refinance workflow (per-step model)

One `file_action` per step, keyed to the steps below. Roles are party
identifiers (`parties.role`). RACI: **R** performs · **A** owns the outcome · **C** supplies
audited inputs · **I** is notified. The accountable party is nudged for a late open step
(see Requirements.md A4). (CD = Closing Disclosure.) R / A / C / I assignments are proposed; confirm with
app eng.

**1 — Apply** · `APPLICATION_SUBMIT`
The borrower submits the loan application and authorizes credit, income, asset, and
property verification.
*Complete when:* the application is submitted and the loan officer has acknowledged intake.
- **Responsible:** `borrower` (R)
- **Accountable:** `loan_officer` (A)
- **Consulted:** `loan_processor` (C) — intake-completeness support
- **Informed:** none
- **Sender:** `borrower`
- **Receiver:** `loan_officer`

**2 — Disclose & acknowledge** · `DISCLOSURES_ACK`
The loan officer issues the Loan Estimate and required disclosures; the borrower reviews
and acknowledges receipt.
*Complete when:* the borrower has acknowledged receipt within the required window.
- **Responsible:** `loan_officer` (R) — issues disclosures; `borrower` (R) — reviews and acknowledges
- **Accountable:** `loan_officer` (A)
- **Consulted:** none
- **Informed:** `loan_processor` (I) — disclosures acknowledged; processing may proceed
- **Sender:** `loan_officer`
- **Receiver:** `borrower`

**3 — Process the loan** · `LOAN_PROCESS`
The loan processor collects and validates income, asset, insurance, and property
information.
*Complete when:* all requested documentation is supplied and validated; the file is ready
for underwriting.
- **Responsible:** `loan_processor` (R)
- **Accountable:** `loan_processor` (A)
- **Consulted:** `borrower` (C) — income, assets, and insurance (for example W-2,
  paychecks, bank statements), supplied as audited uploads
- **Informed:** `loan_officer` (I), `underwriter` (I) — file progressing toward underwriting
- **Sender:** `borrower`
- **Receiver:** `loan_processor`


**4 — Appraise the property** · `APPRAISAL_COMPLETE`
The lender orders an appraisal; a licensed appraiser determines the property's current
market value.
*Complete when:* a completed appraisal is received and attached to the file.
- **Responsible:** `appraiser` (R)
- **Accountable:** `loan_processor` (A) — lender owner of the appraisal outcome
- **Consulted:** `borrower` (C) — property access for the inspection; `loan_officer` (C) — order support
- **Informed:** `underwriter` (I) — valuation available
- **Sender:** `loan_processor`
- **Receiver:** `appraiser`


**5 — Complete title work** · `TITLE_COMPLETE`
The title/settlement company searches title, identifies liens or ownership issues, obtains
payoff information, and prepares the title commitment.
*Complete when:* the title search is complete, payoff obtained, and the commitment issued.
- **Responsible:** `title_agent` (R)
- **Accountable:** `title_agent` (A)
- **Consulted:** `borrower` (C) — existing mortgage / payoff details and any known liens or HOA;
  `loan_processor` (C) — coordination on payoff and file status
- **Informed:** `underwriter` (I) — title commitment ready for review
- **Sender:** `appraiser`
- **Receiver:** `title_agent`


**6 — Underwrite** · `UNDERWRITE`
The lender's underwriter evaluates credit, capacity, collateral, and compliance and issues
conditions or approval.
*Complete when:* an underwriting decision (conditional approval or approval) is issued.
- **Responsible:** `underwriter` (R)
- **Accountable:** `underwriter` (A)
- **Consulted:** `loan_processor` (C) — clarifications on file contents
- **Informed:** `loan_officer` (I), `borrower` (I) — the decision and any conditions
- **Sender:** `title_agent`
- **Receiver:** `underwriter`


**7 — Clear conditions** · `CONDITIONS_CLEAR`
The loan processor coordinates resolution of underwriting and title conditions and confirms
the loan is clear to close.
*Complete when:* all conditions are satisfied and the loan is marked clear to close.
- **Responsible:** `loan_processor` (R)
- **Accountable:** `underwriter` (A)
- **Consulted:** `borrower` (C) — borrower-side condition items (updated documents, letters
  of explanation); `title_agent` (C) — title condition items
- **Informed:** `loan_officer` (I) — clear to close achieved
- **Sender:** `underwriter`
- **Receiver:** `loan_processor`


**8 — Prepare closing** · `CD_DELIVER`
The lender and title/settlement company set the signing date, finalize figures, and deliver
the Closing Disclosure for the borrower to review within the required timeframe.
*Complete when:* the CD is delivered and acknowledged by the borrower and signing is scheduled.
- **Responsible:** `loan_processor` (R) — lender delivery; `title_agent` (R) — settlement coordination;
  `borrower` (R) — review and acknowledgment
- **Accountable:** `loan_processor` (A)
- **Consulted:** `loan_officer` (C) — final fees and figures
- **Informed:** `notary` (I) — signing scheduled
- **Sender:** `loan_processor`
- **Receiver:** `borrower`


**9 — Sign** · `SIGNING`
The borrower verifies identity, signs the loan and security documents, and provides any
required funds; a notary or settlement agent conducts the signing.
*Complete when:* all closing documents are signed and any required funds are provided.
- **Responsible:** `borrower` (R) — signs and provides funds; `notary` (R) — verifies identity and notarizes
- **Accountable:** `title_agent` (A)
- **Consulted:** none
- **Informed:** `loan_processor` (I) — documents executed; proceed to funding
- **Sender:** `borrower`
- **Receiver:** `title_agent`


**10 — Rescission period** · `RESCISSION` *(timer, not an SLA-bearing action)*
For an eligible refinance of a primary residence, the borrower has a right-to-cancel period
before disbursement; the settlement company monitors it.
*Complete when:* the rescission window elapses without cancellation (or the borrower cancels).
- **Responsible:** `loan_processor` (R) — monitors the clock and records its outcome
- **Accountable:** `loan_processor` (A)
- **Consulted:** `title_agent` (C) — settlement coordination
- **Informed:** `borrower` (I), `loan_officer` (I) — the rescission window and deadline
- **Sender:** `title_agent`
- **Receiver:** `loan_processor`


**11 — Fund & disburse** · `DISBURSE`
The lender funds the new loan; the title/settlement company disburses — paying off the
existing mortgage and other obligations and sending any proceeds to the borrower.
*Complete when:* the loan is funded and all disbursements are sent.
- **Responsible:** `title_agent` (R) — disburses; `loan_processor` (R) — releases lender funds
- **Accountable:** `loan_processor` (A)
- **Consulted:** none
- **Informed:** `borrower` (I), `loan_officer` (I) — funded; proceeds sent
- **Sender:** `loan_processor`
- **Receiver:** `title_agent`


**12 — Record & close** · `RECORDING`
The title/settlement company records the new security instrument, confirms payoff, issues
the lender's title policy, and retains the final documents; the county recorder records.
*Complete when:* the security instrument is recorded, the title policy issued, and the file closed.
- **Responsible:** `title_agent` (R) — submits and records the outcome; `county_recorder` (R) — records the instrument
- **Accountable:** `title_agent` (A)
- **Consulted:** none
- **Informed:** `borrower` (I) — loan closed and recorded; `loan_officer` (I), `loan_processor` (I) — policy issued
- **Sender:** `title_agent`
- **Receiver:** `system` — Autoclose closes the step and the file automatically on receipt (see A5)


## 9. Open questions

The load-bearing unknowns that shape everything above. Each resolves into a
recorded decision.

- **Stack — moved to design.** Component choices (CDC tool,
  warehouse / transform engine, metric layer, consumer surfaces) are design
  decisions. Requirements fix only: open source (NFR-5) and PostgreSQL as the ODS.
- **Open-step modeling — resolved (semantic).** The step / RACI model is defined in
  [§8](#8-assumptions-and-workflow-model): a step is open between start and completion;
  its Accountable party owns resolution. U2 keeps these open steps. The *physical* shape (one
  step fact over open and closed steps, status computed at read time) is design-side;
  a file-grain accumulating snapshot stays deferred.
- **Freshness budget — resolved.** ≤ 10 minutes end to end (source commit → viewable
  metric); see [§7](#7-success-metrics) and NFR-1.