/* =========================================================================
   AeroPulse AI - Digital Manufacturing Analytics Platform
   schema.sql
   Target: Microsoft SQL Server
   ========================================================================= */

IF OBJECT_ID('dbo.Shipments', 'U') IS NOT NULL DROP TABLE dbo.Shipments;
IF OBJECT_ID('dbo.MaintenanceLogs', 'U') IS NOT NULL DROP TABLE dbo.MaintenanceLogs;
IF OBJECT_ID('dbo.QualityInspections', 'U') IS NOT NULL DROP TABLE dbo.QualityInspections;
IF OBJECT_ID('dbo.ProductionLogs', 'U') IS NOT NULL DROP TABLE dbo.ProductionLogs;
IF OBJECT_ID('dbo.MachineSensorData', 'U') IS NOT NULL DROP TABLE dbo.MachineSensorData;
IF OBJECT_ID('dbo.ProductionOrders', 'U') IS NOT NULL DROP TABLE dbo.ProductionOrders;
IF OBJECT_ID('dbo.PurchaseOrderLines', 'U') IS NOT NULL DROP TABLE dbo.PurchaseOrderLines;
IF OBJECT_ID('dbo.PurchaseOrders', 'U') IS NOT NULL DROP TABLE dbo.PurchaseOrders;
IF OBJECT_ID('dbo.Operators', 'U') IS NOT NULL DROP TABLE dbo.Operators;
IF OBJECT_ID('dbo.Machines', 'U') IS NOT NULL DROP TABLE dbo.Machines;
IF OBJECT_ID('dbo.InventoryItems', 'U') IS NOT NULL DROP TABLE dbo.InventoryItems;
IF OBJECT_ID('dbo.Suppliers', 'U') IS NOT NULL DROP TABLE dbo.Suppliers;
IF OBJECT_ID('dbo.Customers', 'U') IS NOT NULL DROP TABLE dbo.Customers;
GO

/* =========================================================================
   1. Customers
   ========================================================================= */
CREATE TABLE dbo.Customers (
    CustomerID          INT IDENTITY(1,1)      NOT NULL,
    CustomerCode        VARCHAR(20)             NOT NULL,
    CustomerName        NVARCHAR(150)           NOT NULL,
    ContactPerson       NVARCHAR(100)           NULL,
    Email                VARCHAR(150)            NULL,
    Phone                VARCHAR(30)             NULL,
    Country              NVARCHAR(80)            NULL,
    Address              NVARCHAR(255)           NULL,
    IsActive             BIT                     NOT NULL CONSTRAINT DF_Customers_IsActive DEFAULT (1),
    CreatedAt            DATETIME2(0)            NOT NULL CONSTRAINT DF_Customers_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Customers PRIMARY KEY CLUSTERED (CustomerID),
    CONSTRAINT UQ_Customers_CustomerCode UNIQUE (CustomerCode),
    CONSTRAINT UQ_Customers_Email UNIQUE (Email)
);
GO

/* =========================================================================
   2. Suppliers
   ========================================================================= */
CREATE TABLE dbo.Suppliers (
    SupplierID           INT IDENTITY(1,1)      NOT NULL,
    SupplierCode         VARCHAR(20)             NOT NULL,
    SupplierName         NVARCHAR(150)           NOT NULL,
    ContactPerson        NVARCHAR(100)           NULL,
    Email                 VARCHAR(150)            NULL,
    Phone                 VARCHAR(30)             NULL,
    Country               NVARCHAR(80)            NULL,
    Address               NVARCHAR(255)           NULL,
    QualityRating         DECIMAL(3,2)            NULL CONSTRAINT CK_Suppliers_QualityRating CHECK (QualityRating BETWEEN 0 AND 5),
    IsActive              BIT                     NOT NULL CONSTRAINT DF_Suppliers_IsActive DEFAULT (1),
    CreatedAt             DATETIME2(0)            NOT NULL CONSTRAINT DF_Suppliers_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Suppliers PRIMARY KEY CLUSTERED (SupplierID),
    CONSTRAINT UQ_Suppliers_SupplierCode UNIQUE (SupplierCode)
);
GO

/* =========================================================================
   3. InventoryItems  (raw materials / components / finished parts)
   ========================================================================= */
CREATE TABLE dbo.InventoryItems (
    ItemID                INT IDENTITY(1,1)      NOT NULL,
    ItemCode              VARCHAR(30)             NOT NULL,
    ItemName              NVARCHAR(150)           NOT NULL,
    ItemCategory          VARCHAR(50)             NOT NULL
        CONSTRAINT CK_InventoryItems_Category CHECK (ItemCategory IN ('RawMaterial','Component','SubAssembly','FinishedGood','Consumable')),
    UnitOfMeasure         VARCHAR(20)             NOT NULL,
    QuantityOnHand         DECIMAL(14,3)           NOT NULL CONSTRAINT DF_InventoryItems_Qty DEFAULT (0)
        CONSTRAINT CK_InventoryItems_QtyNonNeg CHECK (QuantityOnHand >= 0),
    ReorderLevel           DECIMAL(14,3)           NOT NULL CONSTRAINT DF_InventoryItems_Reorder DEFAULT (0),
    UnitCost               DECIMAL(14,2)           NOT NULL CONSTRAINT DF_InventoryItems_UnitCost DEFAULT (0)
        CONSTRAINT CK_InventoryItems_UnitCostNonNeg CHECK (UnitCost >= 0),
    PrimarySupplierID      INT                     NULL,
    WarehouseLocation      NVARCHAR(100)           NULL,
    CreatedAt              DATETIME2(0)            NOT NULL CONSTRAINT DF_InventoryItems_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_InventoryItems PRIMARY KEY CLUSTERED (ItemID),
    CONSTRAINT UQ_InventoryItems_ItemCode UNIQUE (ItemCode),
    CONSTRAINT FK_InventoryItems_Suppliers FOREIGN KEY (PrimarySupplierID)
        REFERENCES dbo.Suppliers (SupplierID)
        ON DELETE SET NULL
);
GO

/* =========================================================================
   4. PurchaseOrders (header)
   ========================================================================= */
CREATE TABLE dbo.PurchaseOrders (
    PurchaseOrderID        INT IDENTITY(1,1)      NOT NULL,
    PONumber                VARCHAR(30)             NOT NULL,
    SupplierID              INT                     NOT NULL,
    OrderDate                DATE                    NOT NULL,
    ExpectedDeliveryDate     DATE                    NULL,
    Status                    VARCHAR(20)             NOT NULL CONSTRAINT DF_PurchaseOrders_Status DEFAULT ('Pending')
        CONSTRAINT CK_PurchaseOrders_Status CHECK (Status IN ('Pending','Approved','Shipped','PartiallyReceived','Received','Cancelled')),
    TotalAmount               DECIMAL(16,2)           NOT NULL CONSTRAINT DF_PurchaseOrders_TotalAmount DEFAULT (0)
        CONSTRAINT CK_PurchaseOrders_TotalAmountNonNeg CHECK (TotalAmount >= 0),
    CreatedAt                 DATETIME2(0)            NOT NULL CONSTRAINT DF_PurchaseOrders_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_PurchaseOrders PRIMARY KEY CLUSTERED (PurchaseOrderID),
    CONSTRAINT UQ_PurchaseOrders_PONumber UNIQUE (PONumber),
    CONSTRAINT FK_PurchaseOrders_Suppliers FOREIGN KEY (SupplierID)
        REFERENCES dbo.Suppliers (SupplierID)
        ON DELETE NO ACTION,
    CONSTRAINT CK_PurchaseOrders_DeliveryAfterOrder CHECK (ExpectedDeliveryDate IS NULL OR ExpectedDeliveryDate >= OrderDate)
);
GO

/* =========================================================================
   5. PurchaseOrderLines (detail)
   ========================================================================= */
CREATE TABLE dbo.PurchaseOrderLines (
    PurchaseOrderLineID     INT IDENTITY(1,1)      NOT NULL,
    PurchaseOrderID          INT                     NOT NULL,
    ItemID                    INT                     NOT NULL,
    QuantityOrdered           DECIMAL(14,3)           NOT NULL CONSTRAINT CK_POLines_QtyOrderedPos CHECK (QuantityOrdered > 0),
    QuantityReceived          DECIMAL(14,3)           NOT NULL CONSTRAINT DF_POLines_QtyReceived DEFAULT (0)
        CONSTRAINT CK_POLines_QtyReceivedNonNeg CHECK (QuantityReceived >= 0),
    UnitPrice                  DECIMAL(14,2)           NOT NULL CONSTRAINT CK_POLines_UnitPriceNonNeg CHECK (UnitPrice >= 0),
    LineTotal                  AS (QuantityOrdered * UnitPrice) PERSISTED,
    CONSTRAINT PK_PurchaseOrderLines PRIMARY KEY CLUSTERED (PurchaseOrderLineID),
    CONSTRAINT UQ_POLines_PO_Item UNIQUE (PurchaseOrderID, ItemID),
    CONSTRAINT FK_POLines_PurchaseOrders FOREIGN KEY (PurchaseOrderID)
        REFERENCES dbo.PurchaseOrders (PurchaseOrderID)
        ON DELETE CASCADE,
    CONSTRAINT FK_POLines_InventoryItems FOREIGN KEY (ItemID)
        REFERENCES dbo.InventoryItems (ItemID)
        ON DELETE NO ACTION
);
GO

/* =========================================================================
   6. Machines
   ========================================================================= */
CREATE TABLE dbo.Machines (
    MachineID               INT IDENTITY(1,1)      NOT NULL,
    MachineCode              VARCHAR(20)             NOT NULL,
    MachineName               NVARCHAR(100)           NOT NULL,
    MachineType                VARCHAR(50)             NOT NULL,
    Manufacturer                NVARCHAR(100)           NULL,
    InstallationDate             DATE                    NULL,
    Status                        VARCHAR(20)             NOT NULL CONSTRAINT DF_Machines_Status DEFAULT ('Operational')
        CONSTRAINT CK_Machines_Status CHECK (Status IN ('Operational','Idle','UnderMaintenance','Decommissioned')),
    Location                      NVARCHAR(100)           NULL,
    CreatedAt                      DATETIME2(0)            NOT NULL CONSTRAINT DF_Machines_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Machines PRIMARY KEY CLUSTERED (MachineID),
    CONSTRAINT UQ_Machines_MachineCode UNIQUE (MachineCode)
);
GO

/* =========================================================================
   7. Operators
   ========================================================================= */
CREATE TABLE dbo.Operators (
    OperatorID                INT IDENTITY(1,1)      NOT NULL,
    EmployeeCode                VARCHAR(20)             NOT NULL,
    FullName                     NVARCHAR(120)           NOT NULL,
    Shift                          VARCHAR(10)             NOT NULL
        CONSTRAINT CK_Operators_Shift CHECK (Shift IN ('Day','Evening','Night')),
    Certification                  NVARCHAR(100)           NULL,
    HireDate                        DATE                    NULL,
    IsActive                         BIT                     NOT NULL CONSTRAINT DF_Operators_IsActive DEFAULT (1),
    CreatedAt                         DATETIME2(0)            NOT NULL CONSTRAINT DF_Operators_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Operators PRIMARY KEY CLUSTERED (OperatorID),
    CONSTRAINT UQ_Operators_EmployeeCode UNIQUE (EmployeeCode)
);
GO

/* =========================================================================
   8. ProductionOrders
   ========================================================================= */
CREATE TABLE dbo.ProductionOrders (
    ProductionOrderID          INT IDENTITY(1,1)      NOT NULL,
    ProductionOrderNumber        VARCHAR(30)             NOT NULL,
    ItemID                        INT                     NOT NULL,
    CustomerID                     INT                     NULL,
    PlannedQuantity                  DECIMAL(14,3)           NOT NULL CONSTRAINT CK_ProdOrders_PlannedQtyPos CHECK (PlannedQuantity > 0),
    ActualQuantity                    DECIMAL(14,3)           NOT NULL CONSTRAINT DF_ProdOrders_ActualQty DEFAULT (0)
        CONSTRAINT CK_ProdOrders_ActualQtyNonNeg CHECK (ActualQuantity >= 0),
    ScheduledStartDate                  DATE                    NOT NULL,
    ScheduledEndDate                      DATE                    NOT NULL,
    Status                                  VARCHAR(20)             NOT NULL CONSTRAINT DF_ProdOrders_Status DEFAULT ('Scheduled')
        CONSTRAINT CK_ProdOrders_Status CHECK (Status IN ('Scheduled','InProgress','Completed','OnHold','Cancelled')),
    Priority                                  VARCHAR(10)             NOT NULL CONSTRAINT DF_ProdOrders_Priority DEFAULT ('Medium')
        CONSTRAINT CK_ProdOrders_Priority CHECK (Priority IN ('Low','Medium','High','Critical')),
    CreatedAt                                  DATETIME2(0)            NOT NULL CONSTRAINT DF_ProdOrders_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_ProductionOrders PRIMARY KEY CLUSTERED (ProductionOrderID),
    CONSTRAINT UQ_ProdOrders_Number UNIQUE (ProductionOrderNumber),
    CONSTRAINT FK_ProdOrders_InventoryItems FOREIGN KEY (ItemID)
        REFERENCES dbo.InventoryItems (ItemID)
        ON DELETE NO ACTION,
    CONSTRAINT FK_ProdOrders_Customers FOREIGN KEY (CustomerID)
        REFERENCES dbo.Customers (CustomerID)
        ON DELETE SET NULL,
    CONSTRAINT CK_ProdOrders_EndAfterStart CHECK (ScheduledEndDate >= ScheduledStartDate)
);
GO

/* =========================================================================
   9. MachineSensorData
   ========================================================================= */
CREATE TABLE dbo.MachineSensorData (
    SensorReadingID              BIGINT IDENTITY(1,1)   NOT NULL,
    MachineID                      INT                     NOT NULL,
    ReadingTimestamp                  DATETIME2(3)            NOT NULL CONSTRAINT DF_SensorData_Timestamp DEFAULT (SYSUTCDATETIME()),
    Temperature                        DECIMAL(8,3)            NULL,
    Vibration                            DECIMAL(8,3)            NULL,
    Pressure                              DECIMAL(8,3)            NULL,
    RPM                                    DECIMAL(10,2)           NULL,
    PowerConsumptionKW                      DECIMAL(10,3)           NULL,
    IsAnomaly                                BIT                     NOT NULL CONSTRAINT DF_SensorData_IsAnomaly DEFAULT (0),
    CONSTRAINT PK_MachineSensorData PRIMARY KEY CLUSTERED (SensorReadingID),
    CONSTRAINT FK_SensorData_Machines FOREIGN KEY (MachineID)
        REFERENCES dbo.Machines (MachineID)
        ON DELETE CASCADE
);
GO
CREATE NONCLUSTERED INDEX IX_SensorData_Machine_Timestamp
    ON dbo.MachineSensorData (MachineID, ReadingTimestamp);
GO

/* =========================================================================
   10. ProductionLogs
   ========================================================================= */
CREATE TABLE dbo.ProductionLogs (
    ProductionLogID                INT IDENTITY(1,1)      NOT NULL,
    ProductionOrderID                INT                     NOT NULL,
    MachineID                          INT                     NOT NULL,
    OperatorID                          INT                     NOT NULL,
    LogDate                              DATE                    NOT NULL,
    ShiftStartTime                        DATETIME2(0)            NOT NULL,
    ShiftEndTime                            DATETIME2(0)            NOT NULL,
    UnitsProduced                            DECIMAL(14,3)           NOT NULL CONSTRAINT DF_ProdLogs_Units DEFAULT (0)
        CONSTRAINT CK_ProdLogs_UnitsNonNeg CHECK (UnitsProduced >= 0),
    UnitsScrapped                              DECIMAL(14,3)           NOT NULL CONSTRAINT DF_ProdLogs_Scrapped DEFAULT (0)
        CONSTRAINT CK_ProdLogs_ScrappedNonNeg CHECK (UnitsScrapped >= 0),
    DowntimeMinutes                              INT                     NOT NULL CONSTRAINT DF_ProdLogs_Downtime DEFAULT (0)
        CONSTRAINT CK_ProdLogs_DowntimeNonNeg CHECK (DowntimeMinutes >= 0),
    Notes                                          NVARCHAR(500)           NULL,
    CONSTRAINT PK_ProductionLogs PRIMARY KEY CLUSTERED (ProductionLogID),
    CONSTRAINT FK_ProdLogs_ProductionOrders FOREIGN KEY (ProductionOrderID)
        REFERENCES dbo.ProductionOrders (ProductionOrderID)
        ON DELETE CASCADE,
    CONSTRAINT FK_ProdLogs_Machines FOREIGN KEY (MachineID)
        REFERENCES dbo.Machines (MachineID)
        ON DELETE NO ACTION,
    CONSTRAINT FK_ProdLogs_Operators FOREIGN KEY (OperatorID)
        REFERENCES dbo.Operators (OperatorID)
        ON DELETE NO ACTION,
    CONSTRAINT CK_ProdLogs_ShiftEndAfterStart CHECK (ShiftEndTime > ShiftStartTime)
);
GO

/* =========================================================================
   11. QualityInspections
   ========================================================================= */
CREATE TABLE dbo.QualityInspections (
    InspectionID                    INT IDENTITY(1,1)      NOT NULL,
    ProductionOrderID                 INT                     NOT NULL,
    InspectorOperatorID                 INT                     NOT NULL,
    InspectionDate                        DATETIME2(0)            NOT NULL CONSTRAINT DF_QualityInsp_Date DEFAULT (SYSUTCDATETIME()),
    InspectionType                          VARCHAR(30)             NOT NULL
        CONSTRAINT CK_QualityInsp_Type CHECK (InspectionType IN ('Incoming','InProcess','FinalInspection','Audit')),
    Result                                    VARCHAR(20)             NOT NULL
        CONSTRAINT CK_QualityInsp_Result CHECK (Result IN ('Pass','Fail','ReworkRequired')),
    DefectCategory                              NVARCHAR(100)           NULL,
    DefectCount                                  INT                     NOT NULL CONSTRAINT DF_QualityInsp_DefectCount DEFAULT (0)
        CONSTRAINT CK_QualityInsp_DefectCountNonNeg CHECK (DefectCount >= 0),
    Remarks                                        NVARCHAR(500)           NULL,
    CONSTRAINT PK_QualityInspections PRIMARY KEY CLUSTERED (InspectionID),
    CONSTRAINT FK_QualityInsp_ProductionOrders FOREIGN KEY (ProductionOrderID)
        REFERENCES dbo.ProductionOrders (ProductionOrderID)
        ON DELETE CASCADE,
    CONSTRAINT FK_QualityInsp_Operators FOREIGN KEY (InspectorOperatorID)
        REFERENCES dbo.Operators (OperatorID)
        ON DELETE NO ACTION
);
GO

/* =========================================================================
   12. MaintenanceLogs
   ========================================================================= */
CREATE TABLE dbo.MaintenanceLogs (
    MaintenanceLogID                  INT IDENTITY(1,1)      NOT NULL,
    MachineID                           INT                     NOT NULL,
    OperatorID                            INT                     NULL,
    MaintenanceType                         VARCHAR(20)             NOT NULL
        CONSTRAINT CK_MaintLogs_Type CHECK (MaintenanceType IN ('Preventive','Corrective','Predictive','Emergency')),
    StartTime                                 DATETIME2(0)            NOT NULL,
    EndTime                                     DATETIME2(0)            NULL,
    DescriptionOfWork                             NVARCHAR(500)           NULL,
    Cost                                           DECIMAL(12,2)           NOT NULL CONSTRAINT DF_MaintLogs_Cost DEFAULT (0)
        CONSTRAINT CK_MaintLogs_CostNonNeg CHECK (Cost >= 0),
    Status                                           VARCHAR(20)             NOT NULL CONSTRAINT DF_MaintLogs_Status DEFAULT ('Scheduled')
        CONSTRAINT CK_MaintLogs_Status CHECK (Status IN ('Scheduled','InProgress','Completed','Cancelled')),
    CONSTRAINT PK_MaintenanceLogs PRIMARY KEY CLUSTERED (MaintenanceLogID),
    CONSTRAINT FK_MaintLogs_Machines FOREIGN KEY (MachineID)
        REFERENCES dbo.Machines (MachineID)
        ON DELETE CASCADE,
    CONSTRAINT FK_MaintLogs_Operators FOREIGN KEY (OperatorID)
        REFERENCES dbo.Operators (OperatorID)
        ON DELETE SET NULL,
    CONSTRAINT CK_MaintLogs_EndAfterStart CHECK (EndTime IS NULL OR EndTime >= StartTime)
);
GO

/* =========================================================================
   13. Shipments
   ========================================================================= */
CREATE TABLE dbo.Shipments (
    ShipmentID                          INT IDENTITY(1,1)      NOT NULL,
    ShipmentNumber                        VARCHAR(30)             NOT NULL,
    ProductionOrderID                       INT                     NOT NULL,
    CustomerID                                INT                     NOT NULL,
    ShippedQuantity                             DECIMAL(14,3)           NOT NULL CONSTRAINT CK_Shipments_QtyPos CHECK (ShippedQuantity > 0),
    ShipmentDate                                  DATE                    NOT NULL,
    EstimatedArrivalDate                            DATE                    NULL,
    ActualArrivalDate                                 DATE                    NULL,
    Carrier                                             NVARCHAR(100)           NULL,
    TrackingNumber                                        VARCHAR(60)             NULL,
    Status                                                  VARCHAR(20)             NOT NULL CONSTRAINT DF_Shipments_Status DEFAULT ('Preparing')
        CONSTRAINT CK_Shipments_Status CHECK (Status IN ('Preparing','InTransit','Delivered','Delayed','Cancelled')),
    CONSTRAINT PK_Shipments PRIMARY KEY CLUSTERED (ShipmentID),
    CONSTRAINT UQ_Shipments_ShipmentNumber UNIQUE (ShipmentNumber),
    CONSTRAINT FK_Shipments_ProductionOrders FOREIGN KEY (ProductionOrderID)
        REFERENCES dbo.ProductionOrders (ProductionOrderID)
        ON DELETE NO ACTION,
    CONSTRAINT FK_Shipments_Customers FOREIGN KEY (CustomerID)
        REFERENCES dbo.Customers (CustomerID)
        ON DELETE NO ACTION,
    CONSTRAINT CK_Shipments_ArrivalAfterShipment CHECK (EstimatedArrivalDate IS NULL OR EstimatedArrivalDate >= ShipmentDate)
);
GO

/* =========================================================================
   Supporting indexes for common analytical query patterns
   ========================================================================= */
CREATE NONCLUSTERED INDEX IX_ProductionOrders_Status ON dbo.ProductionOrders (Status);
CREATE NONCLUSTERED INDEX IX_ProductionOrders_ItemID ON dbo.ProductionOrders (ItemID);
CREATE NONCLUSTERED INDEX IX_ProductionLogs_ProdOrder ON dbo.ProductionLogs (ProductionOrderID);
CREATE NONCLUSTERED INDEX IX_QualityInspections_ProdOrder ON dbo.QualityInspections (ProductionOrderID);
CREATE NONCLUSTERED INDEX IX_MaintenanceLogs_MachineID ON dbo.MaintenanceLogs (MachineID);
CREATE NONCLUSTERED INDEX IX_Shipments_CustomerID ON dbo.Shipments (CustomerID);
CREATE NONCLUSTERED INDEX IX_PurchaseOrders_SupplierID ON dbo.PurchaseOrders (SupplierID);
GO