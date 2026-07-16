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
  CONCAT('SEED-',uuidv7()::varchar),
  'CLOSED',
  :'base_ts'::timestamptz - interval '14 days',
  :'base_ts',
  '06037',
  'REFINANCE'
)
RETURNING file_id \gset

INSERT INTO persons (display_name, email, ssn_last4)
SELECT 'Alice Borrower', 'alice.borrower@example.com', '1234'
WHERE NOT EXISTS (SELECT 1 FROM persons WHERE email = 'alice.borrower@example.com');

SELECT person_id as borrower_person_id FROM persons WHERE email = 'alice.borrower@example.com' \gset

INSERT INTO persons (display_name, email, ssn_last4)
SELECT 'Bob Loanofficer', 'bob.loanofficer@example.com', '5678'
WHERE NOT EXISTS (SELECT 1 FROM persons WHERE email = 'bob.loanofficer@example.com');

SELECT person_id as loan_officer_person_id FROM persons WHERE email = 'bob.loanofficer@example.com' \gset

INSERT INTO persons (display_name, email, ssn_last4)
SELECT 'Carol Loanprocessor', 'carol.loanprocessor@example.com', '9012'
WHERE NOT EXISTS (SELECT 1 FROM persons WHERE email = 'carol.loanprocessor@example.com');

SELECT person_id as loan_processor_person_id FROM persons WHERE email = 'carol.loanprocessor@example.com' \gset

INSERT INTO persons (display_name, email, ssn_last4)
SELECT 'Dave Titleagent', 'dave.titleagent@example.com', '3456'
WHERE NOT EXISTS (SELECT 1 FROM persons WHERE email = 'dave.titleagent@example.com');

SELECT person_id as title_agent_person_id FROM persons WHERE email = 'dave.titleagent@example.com' \gset

INSERT INTO persons (display_name, email, ssn_last4)
SELECT 'Same Notary', 'same.notary@example.com', '3456'
WHERE NOT EXISTS (SELECT 1 FROM persons WHERE email = 'same.notary@example.com');

SELECT person_id as notary_person_id FROM persons WHERE email = 'same.notary@example.com' \gset

INSERT INTO persons (display_name, email, ssn_last4)
SELECT 'Jamie Countyrecorder', 'jamie.countyrecorder@example.com', '3456'
WHERE NOT EXISTS (SELECT 1 FROM persons WHERE email = 'jamie.countyrecorder@example.com');

SELECT person_id as county_recorder_person_id FROM persons WHERE email = 'jamie.countyrecorder@example.com' \gset

INSERT INTO persons (display_name, email, ssn_last4)
SELECT 'Autoclose System', 'autoclose@example.com', 'SYSM'
WHERE NOT EXISTS (SELECT 1 FROM persons WHERE email = 'autoclose@example.com');

SELECT person_id as system_person_id FROM persons WHERE email = 'autoclose@example.com' \gset

INSERT INTO parties (file_id, role, person_id) VALUES (:file_id, 'BORROWER', :borrower_person_id);
INSERT INTO parties (file_id, role, person_id) VALUES (:file_id, 'LOAN_OFFICER', :loan_officer_person_id);
INSERT INTO parties (file_id, role, person_id) VALUES (:file_id, 'LOAN_PROCESSOR', :loan_processor_person_id);
INSERT INTO parties (file_id, role, person_id) VALUES (:file_id, 'TITLE_AGENT', :title_agent_person_id);
INSERT INTO parties (file_id, role, person_id) VALUES (:file_id, 'NOTARY', :notary_person_id);
INSERT INTO parties (file_id, role, person_id) VALUES (:file_id, 'COUNTY_RECORDER', :county_recorder_person_id);

INSERT INTO users (person_id, team_name, is_external_vendor_flag)
SELECT :borrower_person_id, NULL, false
WHERE NOT EXISTS (SELECT 1 FROM users WHERE person_id = :borrower_person_id);

SELECT user_id as borrower_user_id FROM users WHERE person_id = :borrower_person_id \gset

INSERT INTO users (person_id, team_name, is_external_vendor_flag)
SELECT :loan_officer_person_id, 'Acme Bank Loan Ops', false
WHERE NOT EXISTS (SELECT 1 FROM users WHERE person_id = :loan_officer_person_id);

SELECT user_id as loan_officer_user_id FROM users WHERE person_id = :loan_officer_person_id \gset

INSERT INTO users (person_id, team_name, is_external_vendor_flag)
SELECT :loan_processor_person_id, 'Acme Bank Loan Ops', false
WHERE NOT EXISTS (SELECT 1 FROM users WHERE person_id = :loan_processor_person_id);

SELECT user_id as loan_processor_user_id FROM users WHERE person_id = :loan_processor_person_id \gset

INSERT INTO users (person_id, team_name, is_external_vendor_flag)
SELECT :title_agent_person_id, 'Acme Title', true
WHERE NOT EXISTS (SELECT 1 FROM users WHERE person_id = :title_agent_person_id);

SELECT user_id as title_agent_user_id FROM users WHERE person_id = :title_agent_person_id \gset

INSERT INTO users (person_id, team_name, is_external_vendor_flag)
SELECT :notary_person_id, 'Acme Title', true
WHERE NOT EXISTS (SELECT 1 FROM users WHERE person_id = :notary_person_id);

SELECT user_id as notary_user_id FROM users WHERE person_id = :notary_person_id \gset

INSERT INTO users (person_id, team_name, is_external_vendor_flag)
SELECT :county_recorder_person_id, 'Los Angeles County Recorder', true
WHERE NOT EXISTS (SELECT 1 FROM users WHERE person_id = :county_recorder_person_id);

SELECT user_id as county_recorder_user_id FROM users WHERE person_id = :county_recorder_person_id \gset

INSERT INTO users (person_id, team_name, is_external_vendor_flag)
SELECT :system_person_id, 'AMOD', true
WHERE NOT EXISTS (SELECT 1 FROM users WHERE person_id = :system_person_id);

SELECT user_id as system_user_id FROM users WHERE person_id = :system_person_id \gset

-- Sender/receiver per Home-Refinance-Workflow.md:
--   1  Apply             borrower -> loan_officer
--   3  Process the loan  borrower -> loan_processor
--   9  Sign              borrower -> title_agent
--   12 Record & close    title_agent -> system (Autoclose auto-closes;)
INSERT INTO file_actions (file_id, action_code, action_type, sent_at, received_at, sent_user_id, received_user_id) VALUES
  (:file_id, 'APPLICATION_SUBMIT', 'COMPLETE', :'base_ts'::timestamptz - interval '14 days',        :'base_ts'::timestamptz - interval '13 days 22 hours', :borrower_user_id, :loan_officer_user_id),
  (:file_id, 'LOAN_PROCESS',       'COMPLETE', :'base_ts'::timestamptz - interval '13 days',         :'base_ts'::timestamptz - interval '10 days',          :borrower_user_id, :loan_processor_user_id),
  (:file_id, 'SIGNING',            'COMPLETE', :'base_ts'::timestamptz - interval '2 days',          :'base_ts'::timestamptz - interval '1 day',            :borrower_user_id, :title_agent_user_id),
  (:file_id, 'RECORDING',          'COMPLETE', :'base_ts'::timestamptz - interval '1 day',           :'base_ts',           :title_agent_user_id, :system_user_id);
