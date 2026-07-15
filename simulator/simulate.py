"""Writes COUNT new files (truncated 4-step workflow) into the ODS. The only
module that imports psycopg2 -- row-generation logic lives in workflow.py so
it can be unit-tested without a database. See design/Milestones.md M1.3.
"""
import datetime
import os
import random
import uuid

import psycopg2

from workflow import build_file, open_state


def db_connection():
    return psycopg2.connect(
        host=os.environ.get("ODS_POSTGRES_HOST", "ods-postgres"),
        port=os.environ.get("ODS_POSTGRES_PORT", "5432"),
        dbname=os.environ["ODS_POSTGRES_DB"],
        user=os.environ["ODS_POSTGRES_USER"],
        password=os.environ["ODS_POSTGRES_PASSWORD"],
    )


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
                "INSERT INTO parties (file_id, role, user_id) VALUES (%s, %s, %s)",
                (file_id, party["role"], party["user_id"]),
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
    conn = db_connection()
    try:
        for _ in range(count):
            file_number = f"SIM-{uuid.uuid4().hex[:12]}"
            # Jitter each file's base timestamp so runs aren't identical.
            base_ts = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(
                days=random.uniform(0, 30)
            )
            file_data = build_file(file_number, base_ts)
            file_id = insert_file(conn, file_data)
            print(f"inserted file_id={file_id} file_number={file_number}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
