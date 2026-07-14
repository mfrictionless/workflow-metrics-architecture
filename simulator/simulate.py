"""Writes COUNT new files (truncated 4-step workflow) into the ODS. The only
module that imports psycopg2 -- row-generation logic lives in workflow.py so
it can be unit-tested without a database. See design/Milestones.md M1.3.
"""
import datetime
import os
import random
import uuid

import psycopg2

from workflow import build_file


def db_connection():
    return psycopg2.connect(
        host=os.environ.get("ODS_POSTGRES_HOST", "ods-postgres"),
        port=os.environ.get("ODS_POSTGRES_PORT", "5432"),
        dbname=os.environ["ODS_POSTGRES_DB"],
        user=os.environ["ODS_POSTGRES_USER"],
        password=os.environ["ODS_POSTGRES_PASSWORD"],
    )


def insert_file(conn, file_data):
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO files (file_number, status, opened_at, closed_at, county_fips, product_type)
            VALUES (%(file_number)s, %(status)s, %(opened_at)s, %(closed_at)s, %(county_fips)s, %(product_type)s)
            RETURNING file_id
            """,
            file_data["file"],
        )
        file_id = cur.fetchone()[0]

        for party in file_data["parties"]:
            cur.execute(
                "INSERT INTO parties (file_id, role, user_id) VALUES (%s, %s, %s)",
                (file_id, party["role"], party["user_id"]),
            )

        for action in file_data["file_actions"]:
            cur.execute(
                """
                INSERT INTO file_actions
                    (file_id, action_code, action_type, sent_at, received_at, sent_user_id, received_user_id)
                VALUES (%(file_id)s, %(action_code)s, %(action_type)s, %(sent_at)s, %(received_at)s,
                        %(sent_user_id)s, %(received_user_id)s)
                """,
                {**action, "file_id": file_id},
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
