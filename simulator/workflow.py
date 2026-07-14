"""Pure row-generation logic for the truncated 4-step refinance workflow
(Apply, Process, Sign, Record and close). No I/O, no external dependencies --
deliberately free of any psycopg2 import so it can be unit-tested without a
database or pip install. See design/Milestones.md M1.2/M1.3 and the RACI
assignments in design/Home-Refinance-Workflow.md (steps 1, 3, 9, 12).

simulate.py (DB-writing) is the only module that imports psycopg2.
"""
import datetime
import itertools

# Roles, in a fixed order, so user_id assignment is deterministic per file.
ROLES = ["BORROWER", "LOAN_OFFICER", "LOAN_PROCESSOR", "TITLE_AGENT", "NOTARY", "COUNTY_RECORDER"]

# Sender/receiver role per step, keyed by action_code. RECORDING has no
# receiver -- Autoclose closes the terminal step automatically (A5).
STEP_ROLES = {
    "APPLICATION_SUBMIT": ("BORROWER", "LOAN_OFFICER"),
    "LOAN_PROCESS": ("BORROWER", "LOAN_PROCESSOR"),
    "SIGNING": ("BORROWER", "TITLE_AGENT"),
    "RECORDING": ("TITLE_AGENT", None),
}

ACTION_SEQUENCE = ["APPLICATION_SUBMIT", "LOAN_PROCESS", "SIGNING", "RECORDING"]

# Offsets (days before base_ts) for each step's sent_at/received_at, mirroring
# ods/seed/seed.sql's spacing.
STEP_OFFSETS_DAYS = {
    "APPLICATION_SUBMIT": (14, 13 + 22 / 24),
    "LOAN_PROCESS": (13, 10),
    "SIGNING": (2, 1),
    "RECORDING": (1, 0),
}

_user_id_counter = itertools.count(100001)


def build_file(file_number, base_ts):
    """Build one closed file's rows: a `files` row, 6 `parties` rows (one per
    role), and 4 `file_actions` rows for the truncated workflow. Returns a
    dict with keys "file", "parties", "file_actions" -- plain dicts, ready
    for a DB layer to insert. Deterministic given (file_number, base_ts),
    except for user_id assignment, which is unique per call.
    """
    user_id_by_role = {role: next(_user_id_counter) for role in ROLES}

    parties = [{"role": role, "user_id": user_id_by_role[role]} for role in ROLES]

    file_actions = []
    for action_code in ACTION_SEQUENCE:
        sent_offset_days, received_offset_days = STEP_OFFSETS_DAYS[action_code]
        sender_role, receiver_role = STEP_ROLES[action_code]
        file_actions.append(
            {
                "action_code": action_code,
                "action_type": "COMPLETE",
                "sent_at": base_ts - datetime.timedelta(days=sent_offset_days),
                "received_at": base_ts - datetime.timedelta(days=received_offset_days),
                "sent_user_id": user_id_by_role[sender_role],
                "received_user_id": user_id_by_role[receiver_role] if receiver_role else None,
            }
        )

    closed_at = file_actions[-1]["received_at"]
    opened_at = file_actions[0]["sent_at"]

    file_row = {
        "file_number": file_number,
        "status": "CLOSED",
        "opened_at": opened_at,
        "closed_at": closed_at,
        "county_fips": "06037",
        "product_type": "REFINANCE",
    }

    return {"file": file_row, "parties": parties, "file_actions": file_actions}
