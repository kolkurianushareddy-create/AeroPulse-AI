"""
==============================================================================
AeroPulse AI - Digital Manufacturing Analytics Platform
etl.py

Production ETL pipeline.

Input : data/raw/*.csv        (synthetic manufacturing data, one CSV per table)
Output: data/processed/*.csv  (validated, cleaned, feature-engineered tables)
        data/processed/kpi_summary.csv (business KPI rollup)

Pipeline stages per table:
    1. Load               - read CSV with logging + exception handling
    2. Validate/Cast       - enforce expected dtypes
    3. Handle missing      - impute / fill according to column semantics
    4. Deduplicate          - drop duplicate primary keys / full-row dupes
    5. Standardize dates    - parse into pandas datetime64
    6. Engineer features    - table-specific derived columns
    7. Save                 - write cleaned + enriched CSV to data/processed/

A final cross-table stage computes plant-wide business KPIs.

Author: AeroPulse AI Data Engineering
==============================================================================
"""

import logging
import os
import sys
from datetime import datetime

import numpy as np
import pandas as pd

# ==============================================================================
# CONFIGURATION
# ==============================================================================

RAW_DIR = os.path.join("data", "raw")
PROCESSED_DIR = os.path.join("data", "processed")

# Snapshot date used for "as of today" calculations (delays, overdue checks).
# Fixed rather than datetime.now() so the pipeline is reproducible against the
# synthetic dataset's simulated time window.
SNAPSHOT_DATE = pd.Timestamp("2026-01-01")

# Business thresholds
DOWNTIME_FLAG_THRESHOLD_MINUTES = 30
MAINTENANCE_OVERDUE_DAYS = 180
SUPPLIER_DELAY_GRACE_DAYS = 0
INSPECTION_FAIL_RESULTS = {"Fail", "ReworkRequired"}

# Per-table configuration: expected dtypes, date columns, id columns for
# dedup, and default fill values for missing data.
TABLE_CONFIG = {
    "Customers": {
        "id_cols": ["CustomerID"],
        "date_cols": ["CreatedAt"],
        "numeric_cols": ["CustomerID"],
        "string_fill": {
            "ContactPerson": "Unknown", "Email": "unknown@unknown.com",
            "Phone": "Unknown", "Country": "Unknown", "Address": "Unknown",
        },
        "bool_cols": ["IsActive"],
    },
    "Suppliers": {
        "id_cols": ["SupplierID"],
        "date_cols": ["CreatedAt"],
        "numeric_cols": ["SupplierID", "QualityRating"],
        "string_fill": {
            "ContactPerson": "Unknown", "Email": "unknown@unknown.com",
            "Phone": "Unknown", "Country": "Unknown", "Address": "Unknown",
        },
        "bool_cols": ["IsActive"],
        "numeric_fill": {"QualityRating": "median"},
    },
    "InventoryItems": {
        "id_cols": ["ItemID"],
        "date_cols": ["CreatedAt"],
        "numeric_cols": ["ItemID", "QuantityOnHand", "ReorderLevel", "UnitCost", "PrimarySupplierID"],
        "string_fill": {"WarehouseLocation": "Unassigned"},
        "numeric_fill": {"QuantityOnHand": 0, "ReorderLevel": 0, "UnitCost": "median"},
    },
    "PurchaseOrders": {
        "id_cols": ["PurchaseOrderID"],
        "date_cols": ["OrderDate", "ExpectedDeliveryDate", "CreatedAt"],
        "numeric_cols": ["PurchaseOrderID", "SupplierID", "TotalAmount"],
        "numeric_fill": {"TotalAmount": 0},
        "string_fill": {"Status": "Unknown"},
    },
    "PurchaseOrderLines": {
        "id_cols": ["PurchaseOrderLineID"],
        "date_cols": [],
        "numeric_cols": ["PurchaseOrderLineID", "PurchaseOrderID", "ItemID",
                          "QuantityOrdered", "QuantityReceived", "UnitPrice"],
        "numeric_fill": {"QuantityOrdered": 0, "QuantityReceived": 0, "UnitPrice": 0},
    },
    "Machines": {
        "id_cols": ["MachineID"],
        "date_cols": ["InstallationDate", "CreatedAt"],
        "numeric_cols": ["MachineID"],
        "string_fill": {"Manufacturer": "Unknown", "Location": "Unassigned", "Status": "Unknown"},
    },
    "Operators": {
        "id_cols": ["OperatorID"],
        "date_cols": ["HireDate", "CreatedAt"],
        "numeric_cols": ["OperatorID"],
        "string_fill": {"Certification": "None", "Shift": "Unknown"},
        "bool_cols": ["IsActive"],
    },
    "ProductionOrders": {
        "id_cols": ["ProductionOrderID"],
        "date_cols": ["ScheduledStartDate", "ScheduledEndDate", "CreatedAt"],
        "numeric_cols": ["ProductionOrderID", "ItemID", "CustomerID", "PlannedQuantity", "ActualQuantity"],
        "numeric_fill": {"PlannedQuantity": 0, "ActualQuantity": 0},
        "string_fill": {"Status": "Unknown", "Priority": "Medium"},
    },
    "MachineSensorData": {
        "id_cols": ["SensorReadingID"],
        "date_cols": ["ReadingTimestamp"],
        "numeric_cols": ["SensorReadingID", "MachineID", "Temperature", "Vibration",
                          "Pressure", "RPM", "PowerConsumptionKW"],
        "numeric_fill": {"Temperature": "median", "Vibration": "median",
                          "Pressure": "median", "RPM": "median", "PowerConsumptionKW": "median"},
        "bool_cols": ["IsAnomaly"],
    },
    "ProductionLogs": {
        "id_cols": ["ProductionLogID"],
        "date_cols": ["LogDate", "ShiftStartTime", "ShiftEndTime"],
        "numeric_cols": ["ProductionLogID", "ProductionOrderID", "MachineID", "OperatorID",
                          "UnitsProduced", "UnitsScrapped", "DowntimeMinutes"],
        "numeric_fill": {"UnitsProduced": 0, "UnitsScrapped": 0, "DowntimeMinutes": 0},
        "string_fill": {"Notes": "None"},
    },
    "QualityInspections": {
        "id_cols": ["InspectionID"],
        "date_cols": ["InspectionDate"],
        "numeric_cols": ["InspectionID", "ProductionOrderID", "InspectorOperatorID", "DefectCount"],
        "numeric_fill": {"DefectCount": 0},
        "string_fill": {"DefectCategory": "None", "Remarks": "None", "Result": "Unknown"},
    },
    "MaintenanceLogs": {
        "id_cols": ["MaintenanceLogID"],
        "date_cols": ["StartTime", "EndTime"],
        "numeric_cols": ["MaintenanceLogID", "MachineID", "OperatorID", "Cost"],
        "numeric_fill": {"Cost": 0},
        "string_fill": {"DescriptionOfWork": "None", "Status": "Unknown"},
    },
    "Shipments": {
        "id_cols": ["ShipmentID"],
        "date_cols": ["ShipmentDate", "EstimatedArrivalDate", "ActualArrivalDate"],
        "numeric_cols": ["ShipmentID", "ProductionOrderID", "CustomerID", "ShippedQuantity"],
        "numeric_fill": {"ShippedQuantity": 0},
        "string_fill": {"Carrier": "Unknown", "TrackingNumber": "Unknown", "Status": "Unknown"},
    },
}

TABLE_ORDER = [
    "Customers", "Suppliers", "InventoryItems", "PurchaseOrders", "PurchaseOrderLines",
    "Machines", "Operators", "ProductionOrders", "MachineSensorData", "ProductionLogs",
    "QualityInspections", "MaintenanceLogs", "Shipments",
]

# ==============================================================================
# LOGGING SETUP
# ==============================================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger("aeropulse_etl")


# ==============================================================================
# GENERIC EXTRACT / TRANSFORM HELPERS
# ==============================================================================

def load_csv(table_name: str) -> pd.DataFrame:
    """Load a raw CSV into a DataFrame with logging and exception handling."""
    path = os.path.join(RAW_DIR, f"{table_name}.csv")
    try:
        df = pd.read_csv(path)
        logger.info("Loaded %s: %d rows, %d columns", table_name, len(df), df.shape[1])
        return df
    except FileNotFoundError:
        logger.error("Raw file not found for table '%s' at %s", table_name, path)
        raise
    except pd.errors.EmptyDataError:
        logger.error("Raw file for table '%s' is empty", table_name)
        raise
    except Exception:
        logger.exception("Unexpected error loading table '%s'", table_name)
        raise


def standardize_dates(df: pd.DataFrame, date_cols: list) -> pd.DataFrame:
    """Parse configured columns into pandas datetime64, coercing bad values to NaT."""
    for col in date_cols:
        if col in df.columns:
            before_na = df[col].isna().sum()
            df[col] = pd.to_datetime(df[col], errors="coerce")
            after_na = df[col].isna().sum()
            new_nulls = after_na - before_na
            if new_nulls > 0:
                logger.warning("Column '%s' had %d value(s) that failed date parsing", col, new_nulls)
    return df


def cast_numeric(df: pd.DataFrame, numeric_cols: list) -> pd.DataFrame:
    """Coerce configured columns to numeric dtype, logging any coercion failures."""
    for col in numeric_cols:
        if col in df.columns:
            original_non_null = df[col].notna().sum()
            df[col] = pd.to_numeric(df[col], errors="coerce")
            new_non_null = df[col].notna().sum()
            if new_non_null < original_non_null:
                logger.warning(
                    "Column '%s' had %d value(s) that could not be cast to numeric",
                    col, original_non_null - new_non_null,
                )
    return df


def cast_boolean(df: pd.DataFrame, bool_cols: list) -> pd.DataFrame:
    """Normalize 0/1/True/False-like columns to nullable boolean/int (0/1)."""
    for col in bool_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0).astype(int)
    return df


def handle_missing_values(df: pd.DataFrame, config: dict) -> pd.DataFrame:
    """
    Impute missing values based on column semantics:
      - numeric_fill: dict mapping column -> constant, or the string 'median'
      - string_fill:  dict mapping column -> constant string fill value
    Any remaining numeric NaNs default to 0; remaining object-column NaNs
    default to 'Unknown'.
    """
    numeric_fill = config.get("numeric_fill", {})
    for col, strategy in numeric_fill.items():
        if col not in df.columns:
            continue
        if strategy == "median":
            fill_value = df[col].median()
            if pd.isna(fill_value):
                fill_value = 0
        else:
            fill_value = strategy
        missing = df[col].isna().sum()
        if missing:
            df[col] = df[col].fillna(fill_value)
            logger.info("Filled %d missing value(s) in '%s' with %s", missing, col, fill_value)

    string_fill = config.get("string_fill", {})
    for col, fill_value in string_fill.items():
        if col not in df.columns:
            continue
        missing = df[col].isna().sum()
        if missing:
            df[col] = df[col].fillna(fill_value)
            logger.info("Filled %d missing value(s) in '%s' with '%s'", missing, col, fill_value)

    # Catch-all defaults for anything not explicitly configured
    remaining_numeric = df.select_dtypes(include=[np.number]).columns
    for col in remaining_numeric:
        if df[col].isna().any():
            df[col] = df[col].fillna(0)

    remaining_object = df.select_dtypes(include=["object", "string"]).columns.unique()
    for col in remaining_object:
        if df[col].isna().any():
            df[col] = df[col].fillna("Unknown")

    return df


def remove_duplicates(df: pd.DataFrame, table_name: str, id_cols: list) -> pd.DataFrame:
    """Drop full-row duplicates, then enforce primary-key uniqueness (keep first)."""
    before = len(df)
    df = df.drop_duplicates()
    after_full_dedup = len(df)
    if before != after_full_dedup:
        logger.info("[%s] Dropped %d exact duplicate row(s)", table_name, before - after_full_dedup)

    valid_id_cols = [c for c in id_cols if c in df.columns]
    if valid_id_cols:
        before_pk = len(df)
        df = df.drop_duplicates(subset=valid_id_cols, keep="first")
        after_pk = len(df)
        if before_pk != after_pk:
            logger.warning(
                "[%s] Dropped %d row(s) with duplicate primary key %s",
                table_name, before_pk - after_pk, valid_id_cols,
            )
    return df.reset_index(drop=True)


def validate_and_clean(table_name: str, df: pd.DataFrame) -> pd.DataFrame:
    """Run the generic dtype validation / missing-value / dedup / date pipeline."""
    config = TABLE_CONFIG.get(table_name, {})
    try:
        df = cast_numeric(df, config.get("numeric_cols", []))
        df = cast_boolean(df, config.get("bool_cols", []))
        df = standardize_dates(df, config.get("date_cols", []))
        df = handle_missing_values(df, config)
        df = remove_duplicates(df, table_name, config.get("id_cols", []))
        return df
    except Exception:
        logger.exception("Validation/cleaning failed for table '%s'", table_name)
        raise


def save_processed(df: pd.DataFrame, table_name: str) -> None:
    """Write a cleaned/enriched DataFrame to data/processed/<table_name>.csv"""
    os.makedirs(PROCESSED_DIR, exist_ok=True)
    path = os.path.join(PROCESSED_DIR, f"{table_name}.csv")
    try:
        df.to_csv(path, index=False)
        logger.info("Saved %s: %d rows, %d columns -> %s", table_name, len(df), df.shape[1], path)
    except Exception:
        logger.exception("Failed to save processed table '%s'", table_name)
        raise


# ==============================================================================
# FEATURE ENGINEERING (table-specific)
# ==============================================================================

def engineer_inventory_items(df: pd.DataFrame) -> pd.DataFrame:
    """Add InventoryStatus classification based on QuantityOnHand vs ReorderLevel."""

    def classify(row):
        qty, reorder = row["QuantityOnHand"], row["ReorderLevel"]
        if reorder <= 0:
            return "Adequate"
        ratio = qty / reorder
        if qty <= 0:
            return "OutOfStock"
        if ratio < 1.0:
            return "Shortage"
        if ratio <= 1.5:
            return "Low"
        if ratio <= 4.0:
            return "Adequate"
        return "Overstock"

    df["InventoryStatus"] = df.apply(classify, axis=1)
    df["InventoryValue"] = (df["QuantityOnHand"] * df["UnitCost"]).round(2)
    return df


def engineer_purchase_orders(df: pd.DataFrame) -> pd.DataFrame:
    """Add SupplierDelay flag and delay-day count based on expected delivery date."""
    open_statuses = {"Pending", "Approved", "Shipped", "PartiallyReceived"}

    df["DaysToExpectedDelivery"] = (df["ExpectedDeliveryDate"] - df["OrderDate"]).dt.days

    def compute_delay(row):
        if row["Status"] in ("Received",):
            # Approximate: a received order is "on time" for KPI purposes since we
            # do not track an explicit actual-receipt-date column in this schema.
            return 0
        if row["Status"] == "Cancelled":
            return np.nan
        if pd.isna(row["ExpectedDeliveryDate"]):
            return np.nan
        overdue_days = (SNAPSHOT_DATE - row["ExpectedDeliveryDate"]).days - SUPPLIER_DELAY_GRACE_DAYS
        return max(overdue_days, 0) if row["Status"] in open_statuses else 0

    df["SupplierDelayDays"] = df.apply(compute_delay, axis=1)
    df["SupplierDelay"] = (df["SupplierDelayDays"].fillna(0) > 0).astype(int)
    return df


def engineer_purchase_order_lines(df: pd.DataFrame) -> pd.DataFrame:
    """Recompute LineTotal defensively and add fulfilment rate."""
    df["LineTotal"] = (df["QuantityOrdered"] * df["UnitPrice"]).round(2)
    df["ReceivedRate"] = np.where(
        df["QuantityOrdered"] > 0,
        (df["QuantityReceived"] / df["QuantityOrdered"]).round(4),
        0.0,
    )
    df["FullyReceived"] = (df["ReceivedRate"] >= 0.999).astype(int)
    return df


def engineer_machines(df: pd.DataFrame, maintenance_df: pd.DataFrame) -> pd.DataFrame:
    """Add MaintenanceOverdue flag based on days since each machine's last maintenance event."""
    completed = maintenance_df[maintenance_df["Status"] == "Completed"].copy()
    last_maint = (
        completed.groupby("MachineID")["StartTime"].max().rename("LastMaintenanceDate")
    )
    df = df.merge(last_maint, on="MachineID", how="left")

    df["DaysSinceLastMaintenance"] = (SNAPSHOT_DATE - df["LastMaintenanceDate"]).dt.days
    df["MaintenanceOverdue"] = np.where(
        df["LastMaintenanceDate"].isna(),
        1,  # never maintained -> treat as overdue
        (df["DaysSinceLastMaintenance"] > MAINTENANCE_OVERDUE_DAYS).astype(int),
    )
    return df


def engineer_production_orders(df: pd.DataFrame, production_logs_df: pd.DataFrame) -> pd.DataFrame:
    """
    Add ProductionDelayMinutes and IsDelayed by comparing each order's scheduled
    end date to the actual latest ShiftEndTime observed in ProductionLogs.
    """
    actual_finish = (
        production_logs_df.groupby("ProductionOrderID")["ShiftEndTime"]
        .max()
        .rename("ActualFinishTime")
    )
    df = df.merge(actual_finish, on="ProductionOrderID", how="left")

    scheduled_end_dt = df["ScheduledEndDate"]
    delay_minutes = (df["ActualFinishTime"] - scheduled_end_dt).dt.total_seconds() / 60.0
    df["ProductionDelayMinutes"] = delay_minutes.clip(lower=0).fillna(0).round(2)
    df["IsDelayed"] = (df["ProductionDelayMinutes"] > 0).astype(int)

    df["QuantityVariance"] = (df["ActualQuantity"] - df["PlannedQuantity"]).round(2)
    df["CompletionRate"] = np.where(
        df["PlannedQuantity"] > 0,
        (df["ActualQuantity"] / df["PlannedQuantity"]).round(4),
        0.0,
    )
    return df


def engineer_production_logs(df: pd.DataFrame) -> pd.DataFrame:
    """Add ProductionDurationHours, DowntimeFlag, MachineUtilizationRate, ScrapRate."""
    duration_hours = (df["ShiftEndTime"] - df["ShiftStartTime"]).dt.total_seconds() / 3600.0
    df["ProductionDurationHours"] = duration_hours.round(3)

    df["DowntimeFlag"] = (df["DowntimeMinutes"] > DOWNTIME_FLAG_THRESHOLD_MINUTES).astype(int)

    shift_minutes = df["ProductionDurationHours"] * 60.0
    productive_minutes = (shift_minutes - df["DowntimeMinutes"]).clip(lower=0)
    df["MachineUtilizationRate"] = np.where(
        shift_minutes > 0, (productive_minutes / shift_minutes).round(4), 0.0
    )

    total_units = df["UnitsProduced"] + df["UnitsScrapped"]
    df["ScrapRate"] = np.where(
        total_units > 0, (df["UnitsScrapped"] / total_units).round(4), 0.0
    )
    return df


def engineer_quality_inspections(df: pd.DataFrame) -> pd.DataFrame:
    """Add InspectionPassed boolean flag."""
    df["InspectionPassed"] = (~df["Result"].isin(INSPECTION_FAIL_RESULTS)).astype(int)
    return df


def engineer_maintenance_logs(df: pd.DataFrame) -> pd.DataFrame:
    """Add MaintenanceDurationHours and an unplanned-maintenance flag."""
    duration_hours = (df["EndTime"] - df["StartTime"]).dt.total_seconds() / 3600.0
    df["MaintenanceDurationHours"] = duration_hours.round(3)
    df["MaintenanceDurationHours"] = df["MaintenanceDurationHours"].fillna(0)
    df["IsUnplanned"] = df["MaintenanceType"].isin(["Corrective", "Emergency"]).astype(int)
    return df


def engineer_shipments(df: pd.DataFrame) -> pd.DataFrame:
    """Add ShipmentDelayDays and OnTimeDelivery flag."""
    delay_days = (df["ActualArrivalDate"] - df["EstimatedArrivalDate"]).dt.days
    df["ShipmentDelayDays"] = delay_days.clip(lower=0)
    df["OnTimeDelivery"] = np.where(
        df["ActualArrivalDate"].notna(),
        (df["ShipmentDelayDays"].fillna(0) == 0).astype(int),
        np.nan,
    )
    return df


# ==============================================================================
# BUSINESS KPI CALCULATION
# ==============================================================================

def compute_kpis(tables: dict) -> pd.DataFrame:
    """
    Compute plant-wide business KPIs from the cleaned, feature-engineered tables.
    Returns a tidy (KPIName, KPIValue, Unit) DataFrame.
    """
    kpis = []

    def add(name, value, unit=""):
        kpis.append({"KPIName": name, "KPIValue": value, "Unit": unit})

    try:
        prod_orders = tables["ProductionOrders"]
        add("OnTimeProductionRate",
            round(100 * (1 - prod_orders["IsDelayed"].mean()), 2), "%")
        add("AverageProductionDelayMinutes",
            round(prod_orders.loc[prod_orders["IsDelayed"] == 1, "ProductionDelayMinutes"].mean() or 0, 2),
            "minutes")
        add("AverageCompletionRate",
            round(100 * prod_orders["CompletionRate"].mean(), 2), "%")

        prod_logs = tables["ProductionLogs"]
        add("AverageMachineUtilizationRate",
            round(100 * prod_logs["MachineUtilizationRate"].mean(), 2), "%")
        add("AverageScrapRate", round(100 * prod_logs["ScrapRate"].mean(), 2), "%")
        add("DowntimeEventRate", round(100 * prod_logs["DowntimeFlag"].mean(), 2), "%")
        add("TotalUnitsProduced", round(prod_logs["UnitsProduced"].sum(), 2), "units")
        add("TotalUnitsScrapped", round(prod_logs["UnitsScrapped"].sum(), 2), "units")

        quality = tables["QualityInspections"]
        add("InspectionPassRate", round(100 * quality["InspectionPassed"].mean(), 2), "%")
        add("TotalDefectsFound", int(quality["DefectCount"].sum()), "defects")

        machines = tables["Machines"]
        add("MaintenanceOverdueRate", round(100 * machines["MaintenanceOverdue"].mean(), 2), "%")

        maintenance = tables["MaintenanceLogs"]
        add("AverageMaintenanceCost", round(maintenance["Cost"].mean(), 2), "USD")
        add("UnplannedMaintenanceRate", round(100 * maintenance["IsUnplanned"].mean(), 2), "%")

        purchase_orders = tables["PurchaseOrders"]
        add("SupplierDelayRate", round(100 * purchase_orders["SupplierDelay"].mean(), 2), "%")
        add("TotalPurchaseSpend", round(purchase_orders["TotalAmount"].sum(), 2), "USD")

        inventory = tables["InventoryItems"]
        shortage_rate = 100 * inventory["InventoryStatus"].isin(["Shortage", "OutOfStock"]).mean()
        add("InventoryShortageRate", round(shortage_rate, 2), "%")
        add("TotalInventoryValue", round(inventory["InventoryValue"].sum(), 2), "USD")

        shipments = tables["Shipments"]
        valid_shipments = shipments["OnTimeDelivery"].dropna()
        on_time_rate = 100 * valid_shipments.mean() if len(valid_shipments) else np.nan
        add("OnTimeShipmentRate", round(on_time_rate, 2) if pd.notna(on_time_rate) else None, "%")

    except Exception:
        logger.exception("Error while computing one or more KPIs; partial KPI set will be saved")

    return pd.DataFrame(kpis)


# ==============================================================================
# MAIN ETL ORCHESTRATION
# ==============================================================================

def run_etl() -> None:
    logger.info("=" * 70)
    logger.info("AeroPulse AI - ETL Pipeline Starting")
    logger.info("=" * 70)

    os.makedirs(PROCESSED_DIR, exist_ok=True)

    # ---- EXTRACT + generic TRANSFORM (validate/clean) for every table -------
    tables = {}
    for table_name in TABLE_ORDER:
        logger.info("-" * 70)
        logger.info("Processing table: %s", table_name)
        raw_df = load_csv(table_name)
        clean_df = validate_and_clean(table_name, raw_df)
        tables[table_name] = clean_df

    # ---- table-specific FEATURE ENGINEERING (some require cross-table joins) --
    logger.info("-" * 70)
    logger.info("Engineering derived features")

    try:
        tables["InventoryItems"] = engineer_inventory_items(tables["InventoryItems"])
        tables["PurchaseOrders"] = engineer_purchase_orders(tables["PurchaseOrders"])
        tables["PurchaseOrderLines"] = engineer_purchase_order_lines(tables["PurchaseOrderLines"])
        tables["Machines"] = engineer_machines(tables["Machines"], tables["MaintenanceLogs"])
        tables["ProductionOrders"] = engineer_production_orders(
            tables["ProductionOrders"], tables["ProductionLogs"]
        )
        tables["ProductionLogs"] = engineer_production_logs(tables["ProductionLogs"])
        tables["QualityInspections"] = engineer_quality_inspections(tables["QualityInspections"])
        tables["MaintenanceLogs"] = engineer_maintenance_logs(tables["MaintenanceLogs"])
        tables["Shipments"] = engineer_shipments(tables["Shipments"])
    except Exception:
        logger.exception("Feature engineering failed")
        raise

    # ---- LOAD: persist every processed table ---------------------------------
    logger.info("-" * 70)
    logger.info("Saving processed tables to %s", PROCESSED_DIR)
    for table_name in TABLE_ORDER:
        save_processed(tables[table_name], table_name)

    # ---- Business KPI rollup --------------------------------------------------
    logger.info("-" * 70)
    logger.info("Computing business KPIs")
    kpi_df = compute_kpis(tables)
    save_processed(kpi_df, "kpi_summary")

    logger.info("=" * 70)
    logger.info("ETL Pipeline completed successfully")
    logger.info("Processed files written to: %s", os.path.abspath(PROCESSED_DIR))
    logger.info("=" * 70)


if __name__ == "__main__":
    try:
        run_etl()
    except Exception:
        logger.exception("ETL pipeline terminated due to an unhandled error")
        sys.exit(1)