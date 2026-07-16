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

INSERT INTO persons (display_name, email, ssn_last4) VALUES ('Alice Borrower', 'alice.borrower@example.com', '1234') RETURNING person_id as borrower_person_id \gset
INSERT INTO persons (display_name, email, ssn_last4) VALUES ('Bob Loanofficer', 'bob.loanofficer@example.com', '5678') RETURNING person_id as loan_officer_person_id \gset
INSERT INTO persons (display_name, email, ssn_last4) VALUES ('Carol Loanprocessor', 'carol.loanprocessor@example.com', '9012') RETURNING person_id as loan_processor_person_id \gset
INSERT INTO persons (display_name, email, ssn_last4) VALUES ('Dave Titleagent', 'dave.titleagent@example.com', '3456') RETURNING person_id as title_agent_person_id \gset
INSERT INTO persons (display_name, email, ssn_last4) VALUES ('Same Notary', 'same.notary@example.com', '3456') RETURNING person_id as notary_person_id \gset
INSERT INTO persons (display_name, email, ssn_last4) VALUES ('Jamie Countyrecorder', 'jamie.countyrecorder@example.com', '3456') RETURNING person_id as county_recorder_person_id \gset
INSERT INTO persons (display_name, email, ssn_last4) VALUES ('Autoclose System', 'autoclose@example.com', 'SYSM') RETURNING person_id as system_person_id \gset

INSERT INTO parties (file_id, role, person_id) VALUES (:file_id, 'BORROWER', :borrower_person_id);
INSERT INTO parties (file_id, role, person_id) VALUES (:file_id, 'LOAN_OFFICER', :loan_officer_person_id);
INSERT INTO parties (file_id, role, person_id) VALUES (:file_id, 'LOAN_PROCESSOR', :loan_processor_person_id);
INSERT INTO parties (file_id, role, person_id) VALUES (:file_id, 'TITLE_AGENT', :title_agent_person_id);
INSERT INTO parties (file_id, role, person_id) VALUES (:file_id, 'NOTARY', :notary_person_id);
INSERT INTO parties (file_id, role, person_id) VALUES (:file_id, 'COUNTY_RECORDER', :county_recorder_person_id);

INSERT INTO users (person_id, team_name, is_external_vendor_flag) VALUES (:borrower_person_id, NULL, false) RETURNING user_id as borrower_user_id \gset
INSERT INTO users (person_id, team_name, is_external_vendor_flag) VALUES (:loan_officer_person_id, 'Acme Bank Loan Ops', false) RETURNING user_id as loan_officer_user_id \gset
INSERT INTO users (person_id, team_name, is_external_vendor_flag) VALUES (:loan_processor_person_id, 'Acme Bank Loan Ops', false) RETURNING user_id as loan_processor_user_id \gset
INSERT INTO users (person_id, team_name, is_external_vendor_flag) VALUES (:title_agent_person_id, 'Acme Title', true) RETURNING user_id as title_agent_user_id \gset
INSERT INTO users (person_id, team_name, is_external_vendor_flag) VALUES (:notary_person_id, 'Acme Title', true) RETURNING user_id as notary_user_id \gset
INSERT INTO users (person_id, team_name, is_external_vendor_flag) VALUES (:county_recorder_person_id, 'Los Angeles County Recorder', true) RETURNING user_id as county_recorder_user_id \gset
INSERT INTO users (person_id, team_name, is_external_vendor_flag) VALUES (:system_person_id, 'AMOD', true) RETURNING user_id as system_user_id \gset

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
