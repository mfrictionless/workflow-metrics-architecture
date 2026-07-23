-- ODS schema — operational data store (source of truth).
-- Matches the data model in design/Technical-Design.md §3.
-- Tables are ordered by foreign-key dependency: files first, then its children.

CREATE TABLE files (
    file_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    file_number varchar NOT NULL,
    status varchar NOT NULL CHECK (status IN ('WIP', 'CLOSED')),
    opened_at timestamptz NOT NULL,
    closed_at timestamptz,
    county_fips varchar,
    product_type varchar NOT NULL        -- e.g. REFINANCE, PURCHASE — open set, not enumerated here
);

COMMENT ON TABLE files IS 'One row per title/closing file — the core transaction record.';
COMMENT ON COLUMN files.file_id IS 'Surrogate primary key.';
COMMENT ON COLUMN files.file_number IS 'Human-readable file identifier used by Autoclose users.';
COMMENT ON COLUMN files.status IS 'Lifecycle status: WIP (in progress) or CLOSED.';
COMMENT ON COLUMN files.opened_at IS 'Timestamp the file was opened / application accepted.';
COMMENT ON COLUMN files.closed_at IS 'Timestamp the file closed. Set automatically when the '
'terminal step (Record and close) completes — see Requirements.md A5.';
COMMENT ON COLUMN files.county_fips IS 'FIPS code of the county where the property is located.';
COMMENT ON COLUMN files.product_type IS 'Loan product type, e.g. REFINANCE or PURCHASE. '
'This working example seeds REFINANCE only.';

CREATE TABLE persons (
    person_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    display_name varchar NOT NULL,
    email varchar NOT NULL UNIQUE,
    ssn_last4 varchar(4) NOT NULL
);

COMMENT ON TABLE persons IS 'One row per person in the system. This table is used to store '
'information about individuals involved in the workflow, such as borrowers, loan officers, and '
'other parties and segragates personally identifable information.';
COMMENT ON COLUMN persons.person_id IS 'Surrogate primary key.';
COMMENT ON COLUMN persons.display_name IS 'Display name of the person.';
COMMENT ON COLUMN persons.email IS 'Email address of the person.';
COMMENT ON COLUMN persons.ssn_last4 IS 'Last four digits of the person''s Social Security Number.';

CREATE TABLE users (
    user_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    person_id bigint NOT NULL REFERENCES persons (person_id),
    team_name varchar NULL DEFAULT NULL,
    is_external_vendor_flag boolean NOT NULL DEFAULT FALSE
);

CREATE INDEX CONCURRENTLY idx_users_person_id ON users (person_id);

COMMENT ON TABLE users IS 'One row per user of Autoclose. Both internal or external users '
'exists in this table.  The user team is recorded here.';
COMMENT ON COLUMN users.user_id IS 'Surrogate primary key.';
COMMENT ON COLUMN users.person_id IS 'Foreign key to the persons table, which stores personally '
'identifiable information.';
COMMENT ON COLUMN users.team_name IS 'Name of the user''s team, e.g. "Acme Title" or "Acme Bank '
'Loan Ops".';
COMMENT ON COLUMN users.is_external_vendor_flag IS 'True if the user is an external vendor '
'(e.g. title agent, not an internal Autoclose employee).';

CREATE TABLE file_actions (
    file_action_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    file_id bigint NOT NULL REFERENCES files (file_id),
    action_code varchar NOT NULL CHECK (action_code IN (
        'APPLICATION_SUBMIT', 'DISCLOSURES_ACK', 'LOAN_PROCESS',
        'APPRAISAL_COMPLETE', 'TITLE_COMPLETE', 'UNDERWRITE',
        'CONDITIONS_CLEAR', 'CD_DELIVER', 'SIGNING', 'RESCISSION',
        'DISBURSE', 'RECORDING'
    )),
    action_type varchar NOT NULL CHECK (action_type IN ('START', 'COMPLETE')),
    sent_at timestamptz,
    received_at timestamptz,
    sent_user_id bigint REFERENCES users (user_id),
    received_user_id bigint REFERENCES users (user_id),
    live_flag boolean NOT NULL DEFAULT TRUE
);

CREATE INDEX CONCURRENTLY idx_file_actions_file_id ON file_actions (file_id);

COMMENT ON TABLE file_actions IS 'One row per workflow step (send/receive lifecycle) on a '
'file. Step catalog and RACI assignments are defined in design/Home-Refinance-Workflow.md.';
COMMENT ON COLUMN file_actions.file_action_id IS 'Surrogate primary key.';
COMMENT ON COLUMN file_actions.file_id IS 'File this step belongs to.';
COMMENT ON COLUMN file_actions.action_code IS 'Step identifier — one of the 12 refinance '
'workflow steps (this working example seeds a truncated 4-step subset per design/Milestones.md '
'M1.2: APPLICATION_SUBMIT, LOAN_PROCESS, SIGNING, RECORDING).';
COMMENT ON COLUMN file_actions.action_type IS 'Whether this row records the step''s START or '
'COMPLETE lifecycle event.';
COMMENT ON COLUMN file_actions.sent_at IS 'Custody handed off at this time (Sender).';
COMMENT ON COLUMN file_actions.received_at IS 'Custody taken up at this time (Receiver). A '
'step is open between sent_at and received_at.';
COMMENT ON COLUMN file_actions.sent_user_id IS 'User who held custody and sent the step onward.';
COMMENT ON COLUMN file_actions.received_user_id IS 'User who received custody. NULL for the '
'terminal step, which Autoclose closes automatically — see Requirements.md A5.';
COMMENT ON COLUMN file_actions.live_flag IS 'Marks the current/authoritative row for a step, '
'distinguishing it from superseded or corrected rows.';

CREATE TABLE parties (
    party_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    file_id bigint NOT NULL REFERENCES files (file_id),
    person_id bigint REFERENCES persons (person_id),
    role varchar NOT NULL CHECK (role IN (
        'BORROWER', 'LOAN_OFFICER', 'LOAN_PROCESSOR', 'UNDERWRITER',
        'APPRAISER', 'TITLE_AGENT', 'NOTARY', 'COUNTY_RECORDER'
    ))
);

CREATE INDEX CONCURRENTLY idx_parties_file_id ON parties (file_id);
CREATE INDEX CONCURRENTLY idx_parties_person_id ON parties (person_id);

COMMENT ON TABLE parties IS 'One row per party-role assignment on a file. A person may hold '
'multiple roles across files. Roles are defined in design/Home-Refinance-Workflow.md.';
COMMENT ON COLUMN parties.party_id IS 'Surrogate primary key.';
COMMENT ON COLUMN parties.person_id IS 'Foreign key to the persons table, which stores '
'personally identifiable information.';
COMMENT ON COLUMN parties.file_id IS 'File this party assignment applies to.';
COMMENT ON COLUMN parties.role IS 'Party role on the file, per the RACI table in '
'design/Home-Refinance-Workflow.md.';

CREATE TABLE audit_events (
    audit_event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    file_id bigint NOT NULL REFERENCES files (file_id),
    user_id bigint REFERENCES users (user_id),
    event_type varchar NOT NULL CHECK (event_type IN (
        'NOTE_ADDED', 'DOCUMENT_UPLOADED', 'SIGNATURE_CAPTURED',
        'SIGNATURE_REJECTED', 'SIGNATURE_APPROVED'
    )),
    description text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX CONCURRENTLY idx_audit_events_file_id ON audit_events (file_id);
CREATE INDEX CONCURRENTLY idx_audit_events_user_id ON audit_events (user_id);

COMMENT ON TABLE audit_events IS 'High-volume event log for work-product changes (notes, '
'signatures, uploads) that do not belong on file_actions — see Requirements.md A2.';
COMMENT ON COLUMN audit_events.audit_event_id IS 'Surrogate primary key.';
COMMENT ON COLUMN audit_events.file_id IS 'File this event occurred on.';
COMMENT ON COLUMN audit_events.user_id IS 'User who performed the action.';
COMMENT ON COLUMN audit_events.event_type IS 'Free-form event category (e.g. NOTE_ADDED, '
'DOCUMENT_UPLOADED, SIGNATURE_CAPTURED). Not enumerated — internal audit trail, not a governed surface.';
COMMENT ON COLUMN audit_events.description IS 'Free-text description of the event.';
COMMENT ON COLUMN audit_events.created_at IS 'Timestamp the event was recorded.';
