"""Writes COUNT new files (truncated 4-step workflow) into the ODS. The only
module that imports psycopg2 -- row-generation logic lives in workflow.py so
it can be unit-tested without a database. See design/Milestones.md M1.3.
"""
import datetime
import os
import random
import uuid

import psycopg2

from workflow import ROLES, SYSTEM, build_file, open_state

# All roles except BORROWER draw from a shared, reusable pool -- these are
# internal/vendor staff who plausibly handle many files. BORROWER is the
# file's customer, so it always gets a fresh person/user (see insert_borrower).
POOL_ROLES = [role for role in ROLES if role != "BORROWER"]

# (team_name, is_external_vendor_flag) per pooled role, matching
# ods/seed/seed.sql's fixed example.
ROLE_TEAM = {
    "LOAN_OFFICER": ("Acme Bank Loan Ops", False),
    "LOAN_PROCESSOR": ("Acme Bank Loan Ops", False),
    "TITLE_AGENT": ("Acme Title", True),
    "NOTARY": ("Acme Title", True),
    "COUNTY_RECORDER": ("Los Angeles County Recorder", True),
}


def db_connection():
    return psycopg2.connect(
        host=os.environ.get("ODS_POSTGRES_HOST", "ods-postgres"),
        port=os.environ.get("ODS_POSTGRES_PORT", "5432"),
        dbname=os.environ["ODS_POSTGRES_DB"],
        user=os.environ["ODS_POSTGRES_USER"],
        password=os.environ["ODS_POSTGRES_PASSWORD"],
    )


def ensure_pool(conn, pool_size):
    """Idempotently ensures `pool_size` persons+users exist per pooled role
    (every role except BORROWER). Safe to call every run -- looks up each
    pool member by its deterministic email before inserting. Returns
    {role: [(person_id, user_id), ...]}.
    """
    pool = {role: [] for role in POOL_ROLES}
    with conn.cursor() as cur:
        for role in POOL_ROLES:
            team_name, is_external_vendor_flag = ROLE_TEAM[role]
            for n in range(1, pool_size + 1):
                email = f"{role.lower()}.pool{n}@example.com"
                cur.execute("SELECT person_id FROM persons WHERE email = %s", (email,))
                row = cur.fetchone()
                if row:
                    person_id = row[0]
                else:
                    cur.execute(
                        """
                        INSERT INTO persons (display_name, email, ssn_last4)
                        VALUES (%s, %s, %s)
                        RETURNING person_id
                        """,
                        (f"{role.replace('_', ' ').title()} Pool {n}", email, "0000"),
                    )
                    person_id = cur.fetchone()[0]

                cur.execute("SELECT user_id FROM users WHERE person_id = %s", (person_id,))
                row = cur.fetchone()
                if row:
                    user_id = row[0]
                else:
                    cur.execute(
                        """
                        INSERT INTO users (person_id, team_name, is_external_vendor_flag)
                        VALUES (%s, %s, %s)
                        RETURNING user_id
                        """,
                        (person_id, team_name, is_external_vendor_flag),
                    )
                    user_id = cur.fetchone()[0]
                pool[role].append((person_id, user_id))
    conn.commit()
    return pool


def ensure_system_user(conn):
    """Idempotently ensures the singleton Autoclose System principal exists
    (matching ods/seed/seed.sql's fixed example) -- RECORDING's receiver,
    per A5. Safe to call every run. Returns (person_id, user_id).
    """
    email = "autoclose@example.com"
    with conn.cursor() as cur:
        cur.execute("SELECT person_id FROM persons WHERE email = %s", (email,))
        row = cur.fetchone()
        if row:
            person_id = row[0]
        else:
            cur.execute(
                """
                INSERT INTO persons (display_name, email, ssn_last4)
                VALUES (%s, %s, %s)
                RETURNING person_id
                """,
                ("Autoclose System", email, "SYSM"),
            )
            person_id = cur.fetchone()[0]

        cur.execute("SELECT user_id FROM users WHERE person_id = %s", (person_id,))
        row = cur.fetchone()
        if row:
            user_id = row[0]
        else:
            cur.execute(
                """
                INSERT INTO users (person_id, team_name, is_external_vendor_flag)
                VALUES (%s, 'AMOD', true)
                RETURNING user_id
                """,
                (person_id,),
            )
            user_id = cur.fetchone()[0]
    conn.commit()
    return person_id, user_id


def insert_borrower(conn, file_number):
    """Inserts a fresh person + user for the file's borrower (the customer --
    never pooled/reused across files)."""
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO persons (display_name, email, ssn_last4)
            VALUES (%s, %s, %s)
            RETURNING person_id
            """,
            (f"Borrower {file_number}", f"borrower.{file_number}@example.com", "0000"),
        )
        person_id = cur.fetchone()[0]
        cur.execute(
            """
            INSERT INTO users (person_id, team_name, is_external_vendor_flag)
            VALUES (%s, NULL, false)
            RETURNING user_id
            """,
            (person_id,),
        )
        user_id = cur.fetchone()[0]
    conn.commit()
    return person_id, user_id


def insert_file(conn, file_data):
    """Write one file through its realistic lifecycle in TWO transactions so
    the CDC stream carries a create then an update per file / file_action
    (M2.8). Phase 1 (one commit): insert the WIP file, its parties, and its
    actions sent-but-not-received. Phase 2 (a second commit): UPDATE the file
    to CLOSED and each action to received. The ODS ends in the same final
    state build_file describes; the intermediate WIP row exists only in the
    WAL/CDC stream, not as an extra ODS row. See design/Milestones.md M2.8.
    """
    initial = open_state(file_data)

    # Phase 1 -- INSERT the WIP snapshot (one transaction, so all three tables'
    # insert rows share one source txId, per M2.6/D012).
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO files (file_number, status, opened_at, closed_at, county_fips, product_type)
            VALUES (%(file_number)s, %(status)s, %(opened_at)s, %(closed_at)s, %(county_fips)s, %(product_type)s)
            RETURNING file_id
            """,
            initial["file"],
        )
        file_id = cur.fetchone()[0]

        for party in initial["parties"]:
            cur.execute(
                "INSERT INTO parties (file_id, role, person_id) VALUES (%s, %s, %s)",
                (file_id, party["role"], party["person_id"]),
            )

        action_ids = []
        for action in initial["file_actions"]:
            cur.execute(
                """
                INSERT INTO file_actions
                    (file_id, action_code, action_type, sent_at, received_at, sent_user_id, received_user_id)
                VALUES (%(file_id)s, %(action_code)s, %(action_type)s, %(sent_at)s, %(received_at)s,
                        %(sent_user_id)s, %(received_user_id)s)
                RETURNING file_action_id
                """,
                {**action, "file_id": file_id},
            )
            action_ids.append(cur.fetchone()[0])
    conn.commit()

    # Phase 2 -- UPDATE to the closed state (a second transaction). Actions are
    # paired to their inserted ids by position: open_state preserves order.
    final_file = file_data["file"]
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE files SET status = %(status)s, closed_at = %(closed_at)s WHERE file_id = %(file_id)s",
            {**final_file, "file_id": file_id},
        )
        for action_id, action in zip(action_ids, file_data["file_actions"]):
            cur.execute(
                "UPDATE file_actions SET received_at = %s, received_user_id = %s WHERE file_action_id = %s",
                (action["received_at"], action["received_user_id"], action_id),
            )
    conn.commit()
    return file_id


def main():
    count = int(os.environ.get("COUNT", "1"))
    pool_size = int(os.environ.get("POOL_SIZE_PER_ROLE", "3"))
    conn = db_connection()
    try:
        pool = ensure_pool(conn, pool_size)
        system_person_id, system_user_id = ensure_system_user(conn)
        for _ in range(count):
            file_number = f"SIM-{uuid.uuid4().hex[:12]}"
            # Jitter each file's base timestamp so runs aren't identical.
            base_ts = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(
                days=random.uniform(0, 30)
            )

            borrower_person_id, borrower_user_id = insert_borrower(conn, file_number)
            role_ids = {
                "BORROWER": {"person_id": borrower_person_id, "user_id": borrower_user_id},
                SYSTEM: {"person_id": system_person_id, "user_id": system_user_id},
            }
            for role in POOL_ROLES:
                person_id, user_id = random.choice(pool[role])
                role_ids[role] = {"person_id": person_id, "user_id": user_id}

            file_data = build_file(file_number, base_ts, role_ids)
            file_id = insert_file(conn, file_data)
            print(f"inserted file_id={file_id} file_number={file_number}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
