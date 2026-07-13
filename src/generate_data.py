"""
==============================================================================
AeroPulse AI - Digital Manufacturing Analytics Platform
generate_data.py

Generates realistic, referentially-consistent synthetic data for every table
defined in schema.sql and writes each table to data/raw/<table_name>.csv

Tables (generation order respects FK dependencies):
    1.  Customers
    2.  Suppliers
    3.  InventoryItems        (FK -> Suppliers)
    4.  PurchaseOrders        (FK -> Suppliers)
    5.  PurchaseOrderLines    (FK -> PurchaseOrders, InventoryItems)
    6.  Machines
    7.  Operators
    8.  ProductionOrders      (FK -> InventoryItems, Customers)
    9.  MachineSensorData     (FK -> Machines)
    10. ProductionLogs        (FK -> ProductionOrders, Machines, Operators)
    11. QualityInspections    (FK -> ProductionOrders, Operators)
    12. MaintenanceLogs       (FK -> Machines, Operators)
    13. Shipments             (FK -> ProductionOrders, Customers)

Author: AeroPulse AI Data Engineering
==============================================================================
"""

import os
import random
from datetime import datetime, timedelta

import numpy as np
import pandas as pd
from faker import Faker

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SEED = 42
random.seed(SEED)
np.random.seed(SEED)
fake = Faker()
Faker.seed(SEED)

OUTPUT_DIR = os.path.join("data", "raw")

ROW_COUNTS = {
    "Customers": 40,
    "Suppliers": 60,
    "InventoryItems": 250,
    "PurchaseOrders": 400,
    "PurchaseOrderLines": 1200,
    "Machines": 35,
    "Operators": 80,
    "ProductionOrders": 500,
    "ProductionLogs": 5000,
    "MachineSensorData": 20000,
    "QualityInspections": 1000,
    "MaintenanceLogs": 600,
    "Shipments": 400,
}

# Overall simulation window used across time-based tables
SIM_START_DATE = datetime(2023, 1, 1)
SIM_END_DATE = datetime(2025, 12, 31)

# Aerospace-domain reference data -------------------------------------------------

ITEM_CATEGORIES = ["RawMaterial", "Component", "SubAssembly", "FinishedGood", "Consumable"]

ITEM_NAMES_BY_CATEGORY = {
    "RawMaterial": [
        "Titanium Ti-6Al-4V Sheet", "Aluminum 7075-T6 Billet", "Aluminum 2024-T3 Plate",
        "Inconel 718 Bar Stock", "Carbon Fiber Prepreg Roll", "Stainless Steel 15-5PH Rod",
        "Kevlar Fabric Roll", "Magnesium AZ31B Sheet", "Copper Alloy C11000 Wire",
    ],
    "Component": [
        "Aerospace Grade Rivet", "Hex Head Bolt NAS1351", "Hydraulic Fitting",
        "Avionics Connector", "Turbine Blade Blank", "Landing Gear Bushing",
        "Pressure Sensor Housing", "Fuel Line Coupling", "Composite Skin Panel",
        "Wiring Harness Clip",
    ],
    "SubAssembly": [
        "Wing Rib Sub-Assembly", "Flap Actuator Assembly", "Landing Gear Strut Assembly",
        "Avionics Bay Module", "Fuselage Frame Section", "Engine Mount Assembly",
        "Control Surface Hinge Assembly",
    ],
    "FinishedGood": [
        "Aircraft Wing Assembly", "Empennage Assembly", "Landing Gear Unit",
        "Engine Nacelle", "Fuselage Barrel Section", "Cockpit Panel Assembly",
    ],
    "Consumable": [
        "Aerospace Sealant Cartridge", "Cutting Fluid Drum", "Abrasive Grinding Disc",
        "Cleanroom Wipes Pack", "Protective Coating Spray", "Welding Filler Wire Spool",
    ],
}

UNIT_OF_MEASURE_BY_CATEGORY = {
    "RawMaterial": ["kg", "sheet", "roll", "bar"],
    "Component": ["each", "box"],
    "SubAssembly": ["each"],
    "FinishedGood": ["each"],
    "Consumable": ["each", "drum", "pack", "spool"],
}

MACHINE_TYPES = [
    "5-Axis CNC Machining Center", "CNC Lathe", "CNC Milling Machine",
    "Autoclave", "Waterjet Cutter", "Laser Cutting Machine",
    "Composite Layup Machine", "Automated Riveting Machine",
    "EDM Machine", "CMM Inspection Station", "Robotic Welding Cell",
]

MACHINE_MANUFACTURERS = [
    "DMG MORI", "Mazak", "Haas Automation", "Okuma", "Fanuc",
    "Hexagon Manufacturing", "Electroimpact", "Broetje Automation",
]

CERTIFICATIONS = [
    "AS9100 Machinist Level II", "NADCAP Composite Cert", "Six Sigma Green Belt",
    "CNC Programming Certified", "Welding Inspector CWI", "Quality Auditor ISO 9001",
    "Non-Destructive Testing Level II",
]

CARRIERS = ["FedEx Freight", "DHL Aviation", "UPS Supply Chain", "DB Schenker", "Kuehne+Nagel"]

COUNTRIES = ["USA", "Germany", "France", "UK", "Japan", "India", "Canada", "Italy", "Brazil", "South Korea"]

WAREHOUSE_LOCATIONS = [f"WH-{block}-{shelf:02d}" for block in ["A", "B", "C", "D"] for shelf in range(1, 11)]


# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

def random_datetime_between(start: datetime, end: datetime) -> datetime:
    """Return a random datetime uniformly distributed between start and end."""
    delta = end - start
    random_seconds = random.uniform(0, delta.total_seconds())
    return start + timedelta(seconds=random_seconds)


def random_date_between(start: datetime, end: datetime) -> datetime.date:
    """Return a random date between two datetimes."""
    return random_datetime_between(start, end).date()


def weighted_choice(options, weights):
    """Wrapper around random.choices returning a single element."""
    return random.choices(options, weights=weights, k=1)[0]


def ensure_output_dir():
    os.makedirs(OUTPUT_DIR, exist_ok=True)


def save_csv(df: pd.DataFrame, table_name: str):
    """Save a DataFrame to data/raw/<table_name>.csv"""
    path = os.path.join(OUTPUT_DIR, f"{table_name}.csv")
    df.to_csv(path, index=False)
    print(f"  -> {table_name}.csv written ({len(df):,} rows)")


# ==============================================================================
# 1. CUSTOMERS
# ==============================================================================

def generate_customers(n: int) -> pd.DataFrame:
    rows = []
    for i in range(1, n + 1):
        created = random_datetime_between(SIM_START_DATE, SIM_END_DATE)
        rows.append({
            "CustomerID": i,
            "CustomerCode": f"CUST-{i:04d}",
            "CustomerName": fake.company() + " Aviation",
            "ContactPerson": fake.name(),
            "Email": fake.unique.company_email(),
            "Phone": fake.phone_number(),
            "Country": random.choice(COUNTRIES),
            "Address": fake.address().replace("\n", ", "),
            "IsActive": weighted_choice([1, 0], [0.92, 0.08]),
            "CreatedAt": created.strftime("%Y-%m-%d %H:%M:%S"),
        })
    return pd.DataFrame(rows)


# ==============================================================================
# 2. SUPPLIERS
# ==============================================================================

def generate_suppliers(n: int) -> pd.DataFrame:
    rows = []
    for i in range(1, n + 1):
        created = random_datetime_between(SIM_START_DATE, SIM_END_DATE)
        rows.append({
            "SupplierID": i,
            "SupplierCode": f"SUPP-{i:04d}",
            "SupplierName": fake.company() + " Materials",
            "ContactPerson": fake.name(),
            "Email": fake.unique.company_email(),
            "Phone": fake.phone_number(),
            "Country": random.choice(COUNTRIES),
            "Address": fake.address().replace("\n", ", "),
            "QualityRating": round(float(np.clip(np.random.normal(4.0, 0.6), 0, 5)), 2),
            "IsActive": weighted_choice([1, 0], [0.90, 0.10]),
            "CreatedAt": created.strftime("%Y-%m-%d %H:%M:%S"),
        })
    return pd.DataFrame(rows)


# ==============================================================================
# 3. INVENTORY ITEMS
# ==============================================================================

def generate_inventory_items(n: int, suppliers_df: pd.DataFrame) -> pd.DataFrame:
    supplier_ids = suppliers_df["SupplierID"].tolist()
    rows = []
    for i in range(1, n + 1):
        category = random.choice(ITEM_CATEGORIES)
        name = random.choice(ITEM_NAMES_BY_CATEGORY[category])
        uom = random.choice(UNIT_OF_MEASURE_BY_CATEGORY[category])

        # Reorder / on-hand modeled so ~15% of items sit below reorder level
        # (simulating realistic inventory shortages)
        reorder_level = round(np.random.uniform(20, 500), 2)
        shortage = random.random() < 0.15
        if shortage:
            qty_on_hand = round(reorder_level * random.uniform(0.0, 0.9), 2)
        else:
            qty_on_hand = round(reorder_level * random.uniform(1.0, 4.0), 2)

        unit_cost = {
            "RawMaterial": np.random.uniform(15, 400),
            "Component": np.random.uniform(5, 250),
            "SubAssembly": np.random.uniform(500, 8000),
            "FinishedGood": np.random.uniform(20000, 250000),
            "Consumable": np.random.uniform(2, 100),
        }[category]

        created = random_datetime_between(SIM_START_DATE, SIM_END_DATE)
        rows.append({
            "ItemID": i,
            "ItemCode": f"ITM-{i:05d}",
            "ItemName": name,
            "ItemCategory": category,
            "UnitOfMeasure": uom,
            "QuantityOnHand": qty_on_hand,
            "ReorderLevel": reorder_level,
            "UnitCost": round(unit_cost, 2),
            "PrimarySupplierID": random.choice(supplier_ids),
            "WarehouseLocation": random.choice(WAREHOUSE_LOCATIONS),
            "CreatedAt": created.strftime("%Y-%m-%d %H:%M:%S"),
        })
    return pd.DataFrame(rows)


# ==============================================================================
# 4. PURCHASE ORDERS
# ==============================================================================

def generate_purchase_orders(n: int, suppliers_df: pd.DataFrame) -> pd.DataFrame:
    supplier_ids = suppliers_df["SupplierID"].tolist()
    statuses = ["Pending", "Approved", "Shipped", "PartiallyReceived", "Received", "Cancelled"]
    status_weights = [0.10, 0.15, 0.15, 0.10, 0.45, 0.05]

    rows = []
    for i in range(1, n + 1):
        order_date = random_date_between(SIM_START_DATE, SIM_END_DATE)
        # Baseline lead time, with ~20% of orders experiencing supplier delays
        base_lead_days = random.randint(7, 30)
        delayed = random.random() < 0.20
        lead_days = base_lead_days + random.randint(10, 45) if delayed else base_lead_days
        expected_delivery = order_date + timedelta(days=lead_days)

        status = weighted_choice(statuses, status_weights)

        rows.append({
            "PurchaseOrderID": i,
            "PONumber": f"PO-{i:06d}",
            "SupplierID": random.choice(supplier_ids),
            "OrderDate": order_date.strftime("%Y-%m-%d"),
            "ExpectedDeliveryDate": expected_delivery.strftime("%Y-%m-%d"),
            "Status": status,
            "TotalAmount": 0.0,  # populated after PurchaseOrderLines are generated
            "CreatedAt": datetime.combine(order_date, datetime.min.time()).strftime("%Y-%m-%d %H:%M:%S"),
        })
    return pd.DataFrame(rows)


# ==============================================================================
# 5. PURCHASE ORDER LINES
# ==============================================================================

def generate_purchase_order_lines(n: int, po_df: pd.DataFrame, items_df: pd.DataFrame):
    """
    Generates purchase order line items and back-fills PurchaseOrders.TotalAmount.
    Ensures every PurchaseOrder has at least one line by first assigning one line
    per PO (up to n), then distributing remaining lines randomly.
    """
    po_ids = po_df["PurchaseOrderID"].tolist()
    item_records = items_df.set_index("ItemID")[["UnitCost"]].to_dict("index")
    item_ids = items_df["ItemID"].tolist()

    # Guarantee 1 line per PO first (if n allows), then top up randomly
    assignments = []
    guaranteed = min(len(po_ids), n)
    assignments.extend(po_ids[:guaranteed])
    remaining = n - guaranteed
    if remaining > 0:
        assignments.extend(random.choices(po_ids, k=remaining))

    rows = []
    used_pairs = set()
    line_id = 1
    for po_id in assignments:
        # avoid duplicate (PurchaseOrderID, ItemID) pairs to satisfy UNIQUE constraint
        for _ in range(10):
            item_id = random.choice(item_ids)
            if (po_id, item_id) not in used_pairs:
                used_pairs.add((po_id, item_id))
                break
        else:
            continue  # skip if couldn't find a unique pair after 10 tries

        qty_ordered = round(np.random.uniform(5, 500), 2)
        # Received quantity: full receipt for most, partial for delayed/pending POs
        po_status = po_df.loc[po_df["PurchaseOrderID"] == po_id, "Status"].values[0]
        if po_status == "Received":
            qty_received = qty_ordered
        elif po_status == "PartiallyReceived":
            qty_received = round(qty_ordered * random.uniform(0.2, 0.85), 2)
        elif po_status in ("Pending", "Approved", "Shipped"):
            qty_received = 0.0
        else:  # Cancelled
            qty_received = 0.0

        base_cost = item_records[item_id]["UnitCost"]
        unit_price = round(base_cost * random.uniform(0.9, 1.15), 2)  # market fluctuation

        rows.append({
            "PurchaseOrderLineID": line_id,
            "PurchaseOrderID": po_id,
            "ItemID": item_id,
            "QuantityOrdered": qty_ordered,
            "QuantityReceived": qty_received,
            "UnitPrice": unit_price,
        })
        line_id += 1

    lines_df = pd.DataFrame(rows)
    lines_df["LineTotal"] = (lines_df["QuantityOrdered"] * lines_df["UnitPrice"]).round(2)

    # Backfill PurchaseOrders.TotalAmount from line totals
    totals = lines_df.groupby("PurchaseOrderID")["LineTotal"].sum().round(2)
    po_df["TotalAmount"] = po_df["PurchaseOrderID"].map(totals).fillna(0.0)

    return lines_df, po_df


# ==============================================================================
# 6. MACHINES
# ==============================================================================

def generate_machines(n: int) -> pd.DataFrame:
    statuses = ["Operational", "Idle", "UnderMaintenance", "Decommissioned"]
    status_weights = [0.72, 0.15, 0.10, 0.03]

    rows = []
    for i in range(1, n + 1):
        install_date = random_date_between(datetime(2015, 1, 1), datetime(2024, 6, 30))
        rows.append({
            "MachineID": i,
            "MachineCode": f"MCH-{i:03d}",
            "MachineName": f"{random.choice(MACHINE_TYPES)} #{i}",
            "MachineType": random.choice(MACHINE_TYPES),
            "Manufacturer": random.choice(MACHINE_MANUFACTURERS),
            "InstallationDate": install_date.strftime("%Y-%m-%d"),
            "Status": weighted_choice(statuses, status_weights),
            "Location": f"Bay-{random.randint(1, 12)}",
            "CreatedAt": datetime.combine(install_date, datetime.min.time()).strftime("%Y-%m-%d %H:%M:%S"),
        })
    return pd.DataFrame(rows)


# ==============================================================================
# 7. OPERATORS
# ==============================================================================

def generate_operators(n: int) -> pd.DataFrame:
    shifts = ["Day", "Evening", "Night"]
    rows = []
    for i in range(1, n + 1):
        hire_date = random_date_between(datetime(2016, 1, 1), datetime(2025, 6, 30))
        rows.append({
            "OperatorID": i,
            "EmployeeCode": f"EMP-{i:04d}",
            "FullName": fake.name(),
            "Shift": random.choice(shifts),
            "Certification": random.choice(CERTIFICATIONS),
            "HireDate": hire_date.strftime("%Y-%m-%d"),
            "IsActive": weighted_choice([1, 0], [0.93, 0.07]),
            "CreatedAt": datetime.combine(hire_date, datetime.min.time()).strftime("%Y-%m-%d %H:%M:%S"),
        })
    return pd.DataFrame(rows)


# ==============================================================================
# 8. PRODUCTION ORDERS
# ==============================================================================

def generate_production_orders(n: int, items_df: pd.DataFrame, customers_df: pd.DataFrame) -> pd.DataFrame:
    item_ids = items_df["ItemID"].tolist()
    customer_ids = customers_df["CustomerID"].tolist()
    statuses = ["Scheduled", "InProgress", "Completed", "OnHold", "Cancelled"]
    status_weights = [0.15, 0.20, 0.50, 0.10, 0.05]
    priorities = ["Low", "Medium", "High", "Critical"]
    priority_weights = [0.25, 0.40, 0.25, 0.10]

    rows = []
    for i in range(1, n + 1):
        start_date = random_date_between(SIM_START_DATE, SIM_END_DATE - timedelta(days=30))
        planned_duration = random.randint(3, 45)

        # ~18% of orders experience schedule slippage (production delays)
        delayed = random.random() < 0.18
        end_date = start_date + timedelta(days=planned_duration + (random.randint(5, 20) if delayed else 0))

        status = weighted_choice(statuses, status_weights)
        planned_qty = round(np.random.uniform(10, 1000), 2)

        if status == "Completed":
            actual_qty = round(planned_qty * np.random.uniform(0.9, 1.0), 2)
        elif status in ("InProgress", "OnHold"):
            actual_qty = round(planned_qty * np.random.uniform(0.1, 0.7), 2)
        else:
            actual_qty = 0.0

        rows.append({
            "ProductionOrderID": i,
            "ProductionOrderNumber": f"PRD-{i:06d}",
            "ItemID": random.choice(item_ids),
            "CustomerID": random.choice(customer_ids),
            "PlannedQuantity": planned_qty,
            "ActualQuantity": actual_qty,
            "ScheduledStartDate": start_date.strftime("%Y-%m-%d"),
            "ScheduledEndDate": end_date.strftime("%Y-%m-%d"),
            "Status": status,
            "Priority": weighted_choice(priorities, priority_weights),
            "CreatedAt": datetime.combine(start_date, datetime.min.time()).strftime("%Y-%m-%d %H:%M:%S"),
        })
    return pd.DataFrame(rows)


# ==============================================================================
# 9. MACHINE SENSOR DATA
# ==============================================================================

def generate_machine_sensor_data(n: int, machines_df: pd.DataFrame) -> pd.DataFrame:
    machine_ids = machines_df["MachineID"].tolist()
    rows = []
    for i in range(1, n + 1):
        machine_id = random.choice(machine_ids)
        ts = random_datetime_between(SIM_START_DATE, SIM_END_DATE)

        # Normal operating baselines with occasional anomalies (~4% anomaly rate)
        is_anomaly = random.random() < 0.04

        if is_anomaly:
            # Harder-to-detect anomalies with overlapping distributions
            temperature = np.random.normal(82, 10)
            vibration = np.random.normal(5.5, 1.8)
            pressure = np.random.normal(32, 8)
            rpm = np.random.normal(1700, 450)
            power = np.random.normal(8.5, 2.5)

        else:
            # Normal operating conditions
            temperature = np.random.normal(65, 8)
            vibration = np.random.normal(2.8, 1.0)
            pressure = np.random.normal(45, 6)
            rpm = np.random.normal(2200, 350)
            power = np.random.normal(12, 3)

        rows.append({
            "SensorReadingID": i,
            "MachineID": machine_id,
            "ReadingTimestamp": ts.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3],
            "Temperature": round(max(temperature, 0), 3),
            "Vibration": round(max(vibration, 0), 3),
            "Pressure": round(max(pressure, 0), 3),
            "RPM": round(max(rpm, 0), 2),
            "PowerConsumptionKW": round(max(power, 0), 3),
            "IsAnomaly": int(is_anomaly),
        })
    return pd.DataFrame(rows)


# ==============================================================================
# 10. PRODUCTION LOGS
# ==============================================================================

def generate_production_logs(n: int, prod_orders_df: pd.DataFrame,
                              machines_df: pd.DataFrame, operators_df: pd.DataFrame) -> pd.DataFrame:
    po_ids = prod_orders_df["ProductionOrderID"].tolist()
    machine_ids = machines_df["MachineID"].tolist()
    operator_ids = operators_df["OperatorID"].tolist()
    po_dates = prod_orders_df.set_index("ProductionOrderID")[["ScheduledStartDate", "ScheduledEndDate"]]

    notes_pool = [
        None, None, None,  # majority have no notes
        "Minor tooling adjustment required.",
        "Material shortage caused brief stoppage.",
        "Unscheduled machine downtime.",
        "Operator changeover mid-shift.",
        "Quality hold pending inspection.",
    ]

    rows = []
    for i in range(1, n + 1):
        po_id = random.choice(po_ids)
        start_str, end_str = po_dates.loc[po_id]
        po_start = datetime.strptime(start_str, "%Y-%m-%d")
        po_end = datetime.strptime(end_str, "%Y-%m-%d")
        if po_end <= po_start:
            po_end = po_start + timedelta(days=1)

        log_dt = random_datetime_between(po_start, po_end)
        log_date = log_dt.date()

        shift_start = datetime.combine(log_date, datetime.min.time()) + timedelta(hours=random.choice([6, 14, 22]))
        shift_end = shift_start + timedelta(hours=8)

        units_produced = round(np.random.uniform(5, 150), 2)
        # Scrap rate typically low, occasionally elevated (quality issues)
        scrap_rate = np.random.choice([np.random.uniform(0, 0.03), np.random.uniform(0.05, 0.20)],
                                       p=[0.85, 0.15])
        units_scrapped = round(units_produced * scrap_rate, 2)

        # Downtime: mostly minimal, occasional significant downtime events
        downtime = int(np.random.choice([np.random.randint(0, 20), np.random.randint(30, 240)],
                                         p=[0.80, 0.20]))

        rows.append({
            "ProductionLogID": i,
            "ProductionOrderID": po_id,
            "MachineID": random.choice(machine_ids),
            "OperatorID": random.choice(operator_ids),
            "LogDate": log_date.strftime("%Y-%m-%d"),
            "ShiftStartTime": shift_start.strftime("%Y-%m-%d %H:%M:%S"),
            "ShiftEndTime": shift_end.strftime("%Y-%m-%d %H:%M:%S"),
            "UnitsProduced": units_produced,
            "UnitsScrapped": units_scrapped,
            "DowntimeMinutes": downtime,
            "Notes": random.choice(notes_pool),
        })
    return pd.DataFrame(rows)


# ==============================================================================
# 11. QUALITY INSPECTIONS
# ==============================================================================

def generate_quality_inspections(n: int, prod_orders_df: pd.DataFrame, operators_df: pd.DataFrame) -> pd.DataFrame:
    po_ids = prod_orders_df["ProductionOrderID"].tolist()
    operator_ids = operators_df["OperatorID"].tolist()
    inspection_types = ["Incoming", "InProcess", "FinalInspection", "Audit"]
    type_weights = [0.25, 0.35, 0.30, 0.10]
    results = ["Pass", "Fail", "ReworkRequired"]
    result_weights = [0.82, 0.09, 0.09]  # ~18% failure/rework rate, realistic for aerospace QA

    defect_categories = [
        "Surface Finish Defect", "Dimensional Tolerance Deviation", "Material Porosity",
        "Weld Discontinuity", "Fastener Torque Non-Conformance", "Coating Thickness Deviation",
        "Foreign Object Debris (FOD)",
    ]

    rows = []
    for i in range(1, n + 1):
        po_id = random.choice(po_ids)
        insp_datetime = random_datetime_between(SIM_START_DATE, SIM_END_DATE)
        result = weighted_choice(results, result_weights)

        if result == "Pass":
            defect_category = None
            defect_count = 0
            remarks = "All measured parameters within specification."
        else:
            defect_category = random.choice(defect_categories)
            defect_count = random.randint(1, 12)
            remarks = f"{defect_category} identified during inspection; see NCR log."

        rows.append({
            "InspectionID": i,
            "ProductionOrderID": po_id,
            "InspectorOperatorID": random.choice(operator_ids),
            "InspectionDate": insp_datetime.strftime("%Y-%m-%d %H:%M:%S"),
            "InspectionType": weighted_choice(inspection_types, type_weights),
            "Result": result,
            "DefectCategory": defect_category,
            "DefectCount": defect_count,
            "Remarks": remarks,
        })
    return pd.DataFrame(rows)


# ==============================================================================
# 12. MAINTENANCE LOGS
# ==============================================================================

def generate_maintenance_logs(n: int, machines_df: pd.DataFrame, operators_df: pd.DataFrame) -> pd.DataFrame:
    machine_ids = machines_df["MachineID"].tolist()
    operator_ids = operators_df["OperatorID"].tolist()
    maint_types = ["Preventive", "Corrective", "Predictive", "Emergency"]
    type_weights = [0.45, 0.30, 0.15, 0.10]
    statuses = ["Scheduled", "InProgress", "Completed", "Cancelled"]
    status_weights = [0.10, 0.10, 0.75, 0.05]

    descriptions = {
        "Preventive": "Routine scheduled preventive maintenance performed per manufacturer guidelines.",
        "Corrective": "Corrective repair performed following identified fault or performance degradation.",
        "Predictive": "Maintenance triggered by predictive analytics / sensor anomaly threshold.",
        "Emergency": "Unplanned emergency repair following unexpected machine failure.",
    }

    rows = []
    for i in range(1, n + 1):
        machine_id = random.choice(machine_ids)
        start_time = random_datetime_between(SIM_START_DATE, SIM_END_DATE)
        maint_type = weighted_choice(maint_types, type_weights)
        status = weighted_choice(statuses, status_weights)

        duration_hours = {
            "Preventive": np.random.uniform(1, 6),
            "Corrective": np.random.uniform(2, 12),
            "Predictive": np.random.uniform(1, 8),
            "Emergency": np.random.uniform(4, 24),
        }[maint_type]

        end_time = start_time + timedelta(hours=duration_hours) if status in ("Completed", "InProgress") else None

        cost = {
            "Preventive": np.random.uniform(200, 1500),
            "Corrective": np.random.uniform(800, 6000),
            "Predictive": np.random.uniform(500, 4000),
            "Emergency": np.random.uniform(2000, 15000),
        }[maint_type]

        rows.append({
            "MaintenanceLogID": i,
            "MachineID": machine_id,
            "OperatorID": random.choice(operator_ids),
            "MaintenanceType": maint_type,
            "StartTime": start_time.strftime("%Y-%m-%d %H:%M:%S"),
            "EndTime": end_time.strftime("%Y-%m-%d %H:%M:%S") if end_time else None,
            "DescriptionOfWork": descriptions[maint_type],
            "Cost": round(cost, 2),
            "Status": status,
        })
    return pd.DataFrame(rows)


# ==============================================================================
# 13. SHIPMENTS
# ==============================================================================

def generate_shipments(n: int, prod_orders_df: pd.DataFrame, customers_df: pd.DataFrame) -> pd.DataFrame:
    # Prefer shipping completed production orders that have an assigned customer
    eligible_orders = prod_orders_df[
        (prod_orders_df["Status"] == "Completed") & (prod_orders_df["CustomerID"].notna())
    ]
    if len(eligible_orders) < n:
        # Fall back to any order with a customer assigned if not enough completed orders
        eligible_orders = prod_orders_df[prod_orders_df["CustomerID"].notna()]

    sampled = eligible_orders.sample(n=min(n, len(eligible_orders)), replace=(len(eligible_orders) < n),
                                      random_state=SEED).reset_index(drop=True)

    statuses = ["Preparing", "InTransit", "Delivered", "Delayed", "Cancelled"]
    status_weights = [0.10, 0.20, 0.55, 0.10, 0.05]

    rows = []
    for i in range(1, len(sampled) + 1):
        po_row = sampled.iloc[i - 1]
        po_end = datetime.strptime(po_row["ScheduledEndDate"], "%Y-%m-%d")
        shipment_date = po_end + timedelta(days=random.randint(1, 10))

        transit_days = random.randint(2, 21)
        estimated_arrival = shipment_date + timedelta(days=transit_days)

        status = weighted_choice(statuses, status_weights)
        if status == "Delivered":
            # Actual arrival close to estimate, occasionally late
            actual_arrival = estimated_arrival + timedelta(days=random.choice([0, 0, 0, 1, 2, 5]))
        elif status == "Delayed":
            actual_arrival = None
            estimated_arrival = estimated_arrival + timedelta(days=random.randint(5, 15))
        else:
            actual_arrival = None

        rows.append({
            "ShipmentID": i,
            "ShipmentNumber": f"SHP-{i:06d}",
            "ProductionOrderID": int(po_row["ProductionOrderID"]),
            "CustomerID": int(po_row["CustomerID"]),
            "ShippedQuantity": round(np.random.uniform(1, max(po_row["ActualQuantity"], 1)), 2)
                if po_row["ActualQuantity"] > 0 else round(np.random.uniform(1, 50), 2),
            "ShipmentDate": shipment_date.strftime("%Y-%m-%d"),
            "EstimatedArrivalDate": estimated_arrival.strftime("%Y-%m-%d"),
            "ActualArrivalDate": actual_arrival.strftime("%Y-%m-%d") if actual_arrival else None,
            "Carrier": random.choice(CARRIERS),
            "TrackingNumber": fake.bothify(text="TRK#########??"),
            "Status": status,
        })
    return pd.DataFrame(rows)


# ==============================================================================
# MAIN ORCHESTRATION
# ==============================================================================

def main():
    print("=" * 70)
    print("AeroPulse AI - Synthetic Manufacturing Data Generation")
    print("=" * 70)

    ensure_output_dir()

    print("\n[1/13] Generating Customers...")
    customers_df = generate_customers(ROW_COUNTS["Customers"])
    save_csv(customers_df, "Customers")

    print("[2/13] Generating Suppliers...")
    suppliers_df = generate_suppliers(ROW_COUNTS["Suppliers"])
    save_csv(suppliers_df, "Suppliers")

    print("[3/13] Generating InventoryItems...")
    items_df = generate_inventory_items(ROW_COUNTS["InventoryItems"], suppliers_df)
    save_csv(items_df, "InventoryItems")

    print("[4/13] Generating PurchaseOrders...")
    po_df = generate_purchase_orders(ROW_COUNTS["PurchaseOrders"], suppliers_df)

    print("[5/13] Generating PurchaseOrderLines (and backfilling PO totals)...")
    po_lines_df, po_df = generate_purchase_order_lines(ROW_COUNTS["PurchaseOrderLines"], po_df, items_df)
    save_csv(po_df, "PurchaseOrders")
    save_csv(po_lines_df, "PurchaseOrderLines")

    print("[6/13] Generating Machines...")
    machines_df = generate_machines(ROW_COUNTS["Machines"])
    save_csv(machines_df, "Machines")

    print("[7/13] Generating Operators...")
    operators_df = generate_operators(ROW_COUNTS["Operators"])
    save_csv(operators_df, "Operators")

    print("[8/13] Generating ProductionOrders...")
    prod_orders_df = generate_production_orders(ROW_COUNTS["ProductionOrders"], items_df, customers_df)
    save_csv(prod_orders_df, "ProductionOrders")

    print("[9/13] Generating MachineSensorData...")
    sensor_df = generate_machine_sensor_data(ROW_COUNTS["MachineSensorData"], machines_df)
    save_csv(sensor_df, "MachineSensorData")

    print("[10/13] Generating ProductionLogs...")
    prod_logs_df = generate_production_logs(ROW_COUNTS["ProductionLogs"], prod_orders_df, machines_df, operators_df)
    save_csv(prod_logs_df, "ProductionLogs")

    print("[11/13] Generating QualityInspections...")
    quality_df = generate_quality_inspections(ROW_COUNTS["QualityInspections"], prod_orders_df, operators_df)
    save_csv(quality_df, "QualityInspections")

    print("[12/13] Generating MaintenanceLogs...")
    maintenance_df = generate_maintenance_logs(ROW_COUNTS["MaintenanceLogs"], machines_df, operators_df)
    save_csv(maintenance_df, "MaintenanceLogs")

    print("[13/13] Generating Shipments...")
    shipments_df = generate_shipments(ROW_COUNTS["Shipments"], prod_orders_df, customers_df)
    save_csv(shipments_df, "Shipments")

    print("\n" + "=" * 70)
    print(f"All CSV files written to: {os.path.abspath(OUTPUT_DIR)}")
    print("=" * 70)


if __name__ == "__main__":
    main()