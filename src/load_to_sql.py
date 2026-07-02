"""
==============================================================================
AeroPulse AI - Digital Manufacturing Analytics Platform
load_to_sql.py

Loads every processed CSV in data/processed/ into the AeroPulseAI SQL Server
database, respecting foreign-key load order, NULL/datetime/numeric/boolean
conversion, IDENTITY column preservation, and transactional safety.

Server   : DESKTOP-ULKMV2J\\SQLEXPRESS
Database : AeroPulseAI
Auth     : Windows Authentication (Trusted_Connection=yes)

Author: AeroPulse AI Data Engineering
==============================================================================
"""

import logging
import math
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
import pyodbc

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Toggle this to control reload behavior:
#   True  -> every target table is emptied (safely, in FK-safe order) before
#            the load begins, so the load always starts from a clean slate.
#   False -> a table that already contains rows is left untouched and skipped.
RELOAD_DATA = True

SERVER = r"DESKTOP-ULKMV2J\SQLEXPRESS"
DATABASE = "AeroPulseAI"

PROCESSED_DIR = Path("data") / "processed"

# ODBC drivers to try, in order of preference. Different machines have
# different driver versions installed, so we probe until one connects.
CANDIDATE_DRIVERS = [
    "ODBC Driver 18 for SQL Server",
    "ODBC Driver 17 for SQL Server",
    "SQL Server Native Client 11.0",
    "SQL Server",
]

# Table load order: parents before children, so every FK reference already
# exists in the database by the time a dependent row is inserted.
# The CSV filename (without extension) is expected to match the table name.
LOAD_ORDER = [
    "Customers",
    "Suppliers",
    "InventoryItems",
    "Machines",
    "Operators",
    "PurchaseOrders",
    "PurchaseOrderLines",
    "ProductionOrders",
    "MachineSensorData",
    "ProductionLogs",
    "QualityInspections",
    "MaintenanceLogs",
    "Shipments",
]

# Tables that exist as CSVs in data/processed/ but are reporting artifacts,
# not schema tables, and must never be loaded into SQL Server.
EXCLUDED_TABLES = {"kpi_summary", "KPI_Summary"}

# Batch size for executemany() inserts, to keep parameter counts and memory
# usage reasonable for very large tables (e.g. MachineSensorData ~20k rows).
INSERT_BATCH_SIZE = 1000

# ==============================================================================
# LOGGING SETUP
# ==============================================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger("aeropulse_loader")


# ==============================================================================
# CONNECTION
# ==============================================================================

def get_connection() -> pyodbc.Connection:
    """
    Open a connection to SQL Server using Windows Authentication
    (Trusted_Connection=yes). Tries several common ODBC driver names since
    the exact installed driver version varies by machine.
    """
    last_error = None
    for driver in CANDIDATE_DRIVERS:
        conn_str = (
            f"DRIVER={{{driver}}};"
            f"SERVER={SERVER};"
            f"DATABASE={DATABASE};"
            f"Trusted_Connection=yes;"
        )
        try:
            conn = pyodbc.connect(conn_str, autocommit=False)
            logger.info("Connected to SQL Server using driver '%s'", driver)
            cursor = conn.cursor()

            cursor.execute("SELECT DB_NAME()")
            logger.info("Connected Database: %s", cursor.fetchone()[0])

            cursor.execute("SELECT @@SERVERNAME")
            logger.info("Connected Server: %s", cursor.fetchone()[0])
            return conn
        except pyodbc.Error as exc:
            logger.debug("Driver '%s' failed: %s", driver, exc)
            last_error = exc
            continue

    logger.error(
        "Could not connect to %s\\%s using any known ODBC driver. "
        "Verify SQL Server Browser is running and an ODBC driver is installed.",
        SERVER, DATABASE,
    )
    raise ConnectionError(f"Unable to connect to SQL Server: {last_error}")


# ==============================================================================
# CSV DISCOVERY / READING
# ==============================================================================

def discover_csv_files(processed_dir: Path) -> dict:
    """
    Automatically detect every CSV file in data/processed/.
    Returns a dict mapping {table_name: Path}, excluding reporting tables
    such as kpi_summary.
    """
    if not processed_dir.exists():
        raise FileNotFoundError(f"Processed data directory not found: {processed_dir}")

    found = {}
    for csv_path in sorted(processed_dir.glob("*.csv")):
        table_name = csv_path.stem
        if table_name in EXCLUDED_TABLES:
            logger.info("Skipping reporting file (not a schema table): %s", csv_path.name)
            continue
        found[table_name] = csv_path

    # Warn about any discovered CSVs that aren't part of the known load order,
    # and about any expected tables that are missing a CSV.
    unknown = set(found.keys()) - set(LOAD_ORDER)
    for name in unknown:
        logger.warning("CSV '%s' found but not part of LOAD_ORDER; it will be ignored", name)

    missing = set(LOAD_ORDER) - set(found.keys())
    for name in missing:
        logger.warning("Expected table '%s' has no matching CSV in %s", name, processed_dir)

    return found


def read_csv(csv_path: Path) -> pd.DataFrame:
    """Read a single CSV file into a DataFrame with logging and error handling."""
    try:
        df = pd.read_csv(csv_path)
        logger.info("Read %s: %d rows, %d columns", csv_path.name, len(df), df.shape[1])
        return df
    except FileNotFoundError:
        logger.error("CSV file not found: %s", csv_path)
        raise
    except pd.errors.EmptyDataError:
        logger.error("CSV file is empty: %s", csv_path)
        raise
    except Exception:
        logger.exception("Unexpected error reading CSV: %s", csv_path)
        raise


# ==============================================================================
# SCHEMA INTROSPECTION
# ==============================================================================

def get_table_columns(cursor: pyodbc.Cursor, table_name: str) -> tuple:
    """
    Return (ordered_column_names, identity_column_names) for a table, using
    SQL Server system catalog views. Computed columns (e.g. PurchaseOrderLines
    .LineTotal) are excluded automatically since they cannot be inserted into
    directly.
    """
    cursor.execute(
        """
        SELECT c.name, c.is_identity
        FROM sys.columns c
        JOIN sys.tables t ON c.object_id = t.object_id
        WHERE t.name = ? AND c.is_computed = 0
        ORDER BY c.column_id
        """,
        table_name,
    )
    rows = cursor.fetchall()
    if not rows:
        raise ValueError(f"Table '{table_name}' does not exist in the target database")

    columns = [row[0] for row in rows]
    identity_columns = [row[0] for row in rows if row[1]]
    return columns, identity_columns


def get_row_count(cursor: pyodbc.Cursor, table_name: str) -> int:
    """Return the current row count of a table."""
    cursor.execute(f"SELECT COUNT(*) FROM dbo.[{table_name}]")
    return cursor.fetchone()[0]


# ==============================================================================
# DATA CLEANING / TYPE CONVERSION
# ==============================================================================

def clean_value(value):
    """
    Normalize a single pandas/numpy scalar value into a native Python type
    that pyodbc can bind safely:
      - NaN / NaT / None                -> None (SQL NULL)
      - pandas.Timestamp                -> python datetime
      - numpy integer / floating types  -> python int / float
      - numpy bool_                     -> python bool (bound as bit)
    """
    try:
        if value is None:
            return None
        if isinstance(value, pd.Timestamp):
            if pd.isna(value):
                return None
            return value.to_pydatetime()
        if isinstance(value, (np.integer,)):
            return int(value)
        if isinstance(value, (np.floating,)):
            if math.isnan(value):
                return None
            return float(value)
        if isinstance(value, (np.bool_,)):
            return bool(value)
        # Generic NaN/NaT catch-all for remaining scalar types
        if pd.isna(value):
            return None
        return value
    except (TypeError, ValueError):
        # pd.isna can raise on some non-scalar/edge-case inputs; treat as-is
        return value


def dataframe_to_records(df: pd.DataFrame, columns: list) -> list:
    """
    Convert a DataFrame (restricted to `columns`, in that order) into a list
    of tuples suitable for pyodbc's executemany(), with all NULL/datetime/
    numeric/boolean normalization applied.
    """
    subset = df[columns]
    records = [
        tuple(clean_value(v) for v in row)
        for row in subset.itertuples(index=False, name=None)
    ]
    return records


# ==============================================================================
# TRUNCATE / RELOAD HANDLING
# ==============================================================================

def truncate_table(cursor: pyodbc.Cursor, table_name: str) -> None:
    """
    Safely empty a table ahead of a reload. DELETE is used instead of
    TRUNCATE because SQL Server disallows TRUNCATE on any table that is
    referenced by a FOREIGN KEY constraint, regardless of whether the
    referencing table currently holds rows. Calling this for every table
    in reverse dependency order (children first) avoids FK violations.
    Identity seeds are reset so re-inserted IDENTITY values start clean.
    """
    logger.info("Truncating table '%s'...", table_name)
    cursor.execute(f"DELETE FROM dbo.[{table_name}]")
    try:
        cursor.execute(f"DBCC CHECKIDENT ('dbo.[{table_name}]', RESEED, 0)")
    except pyodbc.Error:
        # Table has no IDENTITY column - safe to ignore.
        pass


def reset_tables_for_reload(cursor: pyodbc.Cursor, table_names: list) -> None:
    """
    When RELOAD_DATA is True, empty every populated target table before any
    inserts begin. Tables are truncated in REVERSE load order (children
    before parents) so FK constraints are never violated mid-reset.
    """
    for table_name in reversed(table_names):
        try:
            row_count = get_row_count(cursor, table_name)
        except pyodbc.Error:
            logger.warning("Could not read row count for '%s' (table may not exist yet)", table_name)
            continue

        if row_count > 0:
            truncate_table(cursor, table_name)
        else:
            logger.info("Table '%s' already empty; nothing to truncate", table_name)


# ==============================================================================
# INSERT LOGIC
# ==============================================================================

def insert_dataframe(cursor: pyodbc.Cursor, table_name: str, df: pd.DataFrame) -> int:
    """
    Insert a DataFrame into the given table using parameterized executemany().

    - Restricts the DataFrame to columns that actually exist as insertable
      (non-computed) columns on the target table, in the table's own
      column order, so processed CSVs with extra engineered/analytics
      columns (e.g. InventoryStatus, SupplierDelay) load cleanly.
    - Wraps the insert in SET IDENTITY_INSERT ON/OFF when the target table
      has an IDENTITY primary key, since processed CSVs carry explicit
      surrogate keys that must be preserved to maintain FK integrity
      across tables.
    - Batches executemany() calls to keep parameter counts manageable for
      very large tables.
    """
    table_columns, identity_columns = get_table_columns(cursor, table_name)

    # Only load columns that are present in both the CSV and the table,
    # preserving the target table's column order.
    usable_columns = [c for c in table_columns if c in df.columns]
    if not usable_columns:
        raise ValueError(f"No matching columns found between CSV and table '{table_name}'")

    missing_from_csv = set(table_columns) - set(usable_columns)
    if missing_from_csv:
        logger.debug("Columns present on table but absent from CSV (left NULL/default): %s",
                     sorted(missing_from_csv))

    extra_in_csv = set(df.columns) - set(usable_columns)
    if extra_in_csv:
        logger.debug("Analytics/engineered columns in CSV not loaded to SQL: %s",
                     sorted(extra_in_csv))

    records = dataframe_to_records(df, usable_columns)
    if not records:
        logger.info("No rows to insert for '%s'", table_name)
        return 0

    placeholders = ", ".join("?" for _ in usable_columns)
    column_list = ", ".join(f"[{c}]" for c in usable_columns)
    insert_sql = f"INSERT INTO dbo.[{table_name}] ({column_list}) VALUES ({placeholders})"

    needs_identity_insert = bool(set(identity_columns) & set(usable_columns))

    try:
        cursor.fast_executemany = True
    except AttributeError:
        pass  # Not all pyodbc/driver combinations support fast_executemany

    try:
        if needs_identity_insert:
            cursor.execute(f"SET IDENTITY_INSERT dbo.[{table_name}] ON")

        total_inserted = 0
        for start in range(0, len(records), INSERT_BATCH_SIZE):
            batch = records[start:start + INSERT_BATCH_SIZE]
            cursor.executemany(insert_sql, batch)
            total_inserted += len(batch)

        return total_inserted

    finally:
        if needs_identity_insert:
            cursor.execute(f"SET IDENTITY_INSERT dbo.[{table_name}] OFF")


# ==============================================================================
# TABLE-LEVEL ORCHESTRATION
# ==============================================================================

def load_table(conn: pyodbc.Connection, table_name: str, csv_path: Path) -> int:
    """
    Load a single table end-to-end:
      1. Check existing row count.
      2. Skip if RELOAD_DATA is False and the table already has data.
      3. Read + clean the CSV.
      4. Insert via parameterized executemany().
      5. Commit on success; roll back and re-raise on failure.

    Returns the number of rows inserted (0 if skipped).
    """
    cursor = conn.cursor()
    logger.info("Loading %s...", table_name)

    try:
        existing_rows = get_row_count(cursor, table_name)
    except pyodbc.Error:
        conn.rollback()
        logger.exception("Target table '%s' does not appear to exist in the database", table_name)
        raise

    if not RELOAD_DATA and existing_rows > 0:
        logger.info("Skipping %s: already contains %d row(s) and RELOAD_DATA is False",
                    table_name, existing_rows)
        return 0

    try:
        df = read_csv(csv_path)
        rows_inserted = insert_dataframe(cursor, table_name, df)
        conn.commit()
        cursor.execute(f"SELECT COUNT(*) FROM dbo.{table_name}")
        logger.info("%s now contains %d rows", table_name, cursor.fetchone()[0])
        logger.info("Inserted %d rows into %s.", rows_inserted, table_name)
        return rows_inserted

    except Exception:
        conn.rollback()
        logger.exception("Failed to load table '%s'; transaction rolled back", table_name)
        raise


# ==============================================================================
# MAIN ORCHESTRATION
# ==============================================================================

def main() -> None:
    start_time = time.time()

    logger.info("=" * 70)
    logger.info("AeroPulse AI - SQL Server Data Load Starting")
    logger.info("Target: %s / %s | RELOAD_DATA = %s", SERVER, DATABASE, RELOAD_DATA)
    logger.info("=" * 70)

    tables_loaded = []
    rows_by_table = {}
    conn = None

    try:
        conn = get_connection()
        cursor = conn.cursor()

        # Discover CSVs and build the final ordered work list, restricted to
        # tables we actually have both a CSV for and a schema table for.
        available_csvs = discover_csv_files(PROCESSED_DIR)
        work_list = [(name, available_csvs[name]) for name in LOAD_ORDER if name in available_csvs]

        if not work_list:
            logger.error("No matching CSV files found in %s for the configured LOAD_ORDER", PROCESSED_DIR)
            return

        # If reloading, clear every target table up-front in reverse
        # dependency order so FK constraints are never violated mid-reset.
        if RELOAD_DATA:
            logger.info("-" * 70)
            logger.info("RELOAD_DATA is True: resetting tables before load")
            reset_tables_for_reload(cursor, [name for name, _ in work_list])
            conn.commit()

        # Load each table in FK-safe order.
        logger.info("-" * 70)
        for table_name, csv_path in work_list:
            rows_inserted = load_table(conn, table_name, csv_path)
            tables_loaded.append(table_name)
            rows_by_table[table_name] = rows_inserted

    except Exception:
        logger.exception("Data load aborted due to an unrecoverable error")
        sys.exit(1)

    finally:
        if conn is not None:
            conn.close()
            logger.info("Database connection closed")

    # ---- Final summary ---------------------------------------------------
    elapsed = time.time() - start_time
    total_rows = sum(rows_by_table.values())

    logger.info("=" * 70)
    logger.info("LOAD SUMMARY")
    logger.info("=" * 70)
    for table_name in tables_loaded:
        logger.info("  %-22s -> %6d rows", table_name, rows_by_table.get(table_name, 0))
    logger.info("-" * 70)
    logger.info("Tables loaded   : %d", len(tables_loaded))
    logger.info("Rows inserted   : %d", total_rows)
    logger.info("Execution time  : %.2f seconds", elapsed)
    logger.info("=" * 70)


if __name__ == "__main__":
    main()
    