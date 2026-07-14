-- Seeds one closed file with the truncated 4-step workflow (Apply, Process,
-- Sign, Record and close). Applied explicitly via `make seed` -- deliberately
-- not part of Postgres's auto-init (ods/ddl/), so it never mixes with
-- simulator-generated data. See design/Milestones.md M1.2 and the RACI
-- assignments in design/Home-Refinance-Workflow.md (steps 1, 3, 9, 12).

-- Captured once so files.closed_at and the terminal step's received_at are
-- derived from the exact same value, not two separate now() calls.
SELECT now() AS base_ts \gset

INSERT INTO files (file_number, status, opened_at, closed_at, county_fips, product_type)
VALUES (
  'SEED-0001',
  'CLOSED',
  :'base_ts'::timestamptz - interval '14 days',
  :'base_ts',
  '06037',
  'REFINANCE'
)
RETURNING file_id \gset

INSERT INTO parties (file_id, role, user_id) VALUES
  (:file_id, 'BORROWER', 101),
  (:file_id, 'LOAN_OFFICER', 102),
  (:file_id, 'LOAN_PROCESSOR', 103),
  (:file_id, 'TITLE_AGENT', 104),
  (:file_id, 'NOTARY', 105),
  (:file_id, 'COUNTY_RECORDER', 106);

-- Sender/receiver per Home-Refinance-Workflow.md:
--   1  Apply             borrower -> loan_officer
--   3  Process the loan  borrower -> loan_processor
--   9  Sign              borrower -> title_agent
--   12 Record & close    title_agent -> system (Autoclose auto-closes; no receiver)
INSERT INTO file_actions (file_id, action_code, action_type, sent_at, received_at, sent_user_id, received_user_id) VALUES
  (:file_id, 'APPLICATION_SUBMIT', 'COMPLETE', :'base_ts'::timestamptz - interval '14 days',        :'base_ts'::timestamptz - interval '13 days 22 hours', 101, 102),
  (:file_id, 'LOAN_PROCESS',       'COMPLETE', :'base_ts'::timestamptz - interval '13 days',         :'base_ts'::timestamptz - interval '10 days',          101, 103),
  (:file_id, 'SIGNING',            'COMPLETE', :'base_ts'::timestamptz - interval '2 days',          :'base_ts'::timestamptz - interval '1 day',            101, 104),
  (:file_id, 'RECORDING',          'COMPLETE', :'base_ts'::timestamptz - interval '1 day',           :'base_ts',                                             104, NULL);
