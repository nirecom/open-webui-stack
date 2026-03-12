"""
Migrate Open WebUI data from SQLite to PostgreSQL.

Run inside the open-webui container where both the SQLite file
and DATABASE_URL environment variable are available:

    docker compose exec -T open-webui python3 < misc/migrate_sqlite_to_pg.py

Prerequisites:
  - PostgreSQL is running and Open WebUI has auto-created the schema
  - DATABASE_URL is set in the container environment
  - /app/backend/data/webui.db exists (the original SQLite database)

Notes:
  - SQLite stores booleans as 0/1; this script converts them to
    Python bool for PostgreSQL boolean columns.
  - Migration-tracking tables (alembic_version, migratehistory) are skipped.
  - Existing rows in PostgreSQL are deleted before inserting.
  - FK constraints are temporarily disabled via session_replication_role.
"""

import sqlite3
import os

from sqlalchemy import create_engine, inspect, text

SQLITE_PATH = "/app/backend/data/webui.db"
SKIP_TABLES = {"sqlite_sequence", "migratehistory", "alembic_version"}


def main():
    db_url = os.environ.get("DATABASE_URL", "")
    if not db_url:
        print("ERROR: DATABASE_URL is not set")
        return

    sqlite_conn = sqlite3.connect(SQLITE_PATH)
    cursor = sqlite_conn.cursor()
    pg_engine = create_engine(db_url)

    tables = [
        r[0]
        for r in cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).fetchall()
        if r[0] not in SKIP_TABLES and not r[0].startswith("sqlite_")
    ]

    # Detect boolean columns in PostgreSQL schema
    insp = inspect(pg_engine)
    bool_cols = {}
    for table in tables:
        try:
            cols = insp.get_columns(table)
            bool_cols[table] = {
                c["name"] for c in cols if str(c["type"]) == "BOOLEAN"
            }
        except Exception:
            bool_cols[table] = set()

    with pg_engine.connect() as conn:
        conn.execute(text("SET session_replication_role = 'replica'"))

        for table in tables:
            conn.execute(text(f'DELETE FROM "{table}"'))

            rows = cursor.execute(f'SELECT * FROM "{table}"').fetchall()
            if not rows:
                print(f"  {table}: 0 rows")
                continue

            columns = [d[0] for d in cursor.description]
            col_list = ", ".join(f'"{c}"' for c in columns)
            val_list = ", ".join(f":{c}" for c in columns)

            for row in rows:
                data = dict(zip(columns, row))
                for col in bool_cols.get(table, set()):
                    if col in data and data[col] is not None:
                        data[col] = bool(data[col])
                conn.execute(
                    text(f'INSERT INTO "{table}" ({col_list}) VALUES ({val_list})'),
                    data,
                )

            print(f"  {table}: {len(rows)} rows")

        conn.execute(text("SET session_replication_role = 'origin'"))
        conn.commit()

    sqlite_conn.close()
    print("Migration complete!")


if __name__ == "__main__":
    main()
