/* =============================================================================
   AeroPulse AI - Digital Manufacturing Analytics Platform
   analytics_queries.sql  (PART 1 of N)

   Scope of this part:
     SECTION 1 - Executive KPIs         (8 queries)
     SECTION 2 - Production Analytics   (8 queries)

   Target: Microsoft SQL Server (T-SQL)
   Notes:
     - Uses only tables/columns defined in schema.sql.
     - Inventory, Supplier, Machine-master, Maintenance, and Dashboard
       analytics are intentionally deferred to later parts of this file.
   ============================================================================= */


/* #############################################################################
   SECTION 1: EXECUTIVE KPIs
   ############################################################################# */

-- -----------------------------------------------------------------------------
-- EX-01: Plant-Wide On-Time Shipment Delivery Rate
-- -----------------------------------------------------------------------------
/*
Business Question:
    Of all shipments that have been delivered to customers, what percentage
    arrived on or before the originally estimated arrival date?

Business Value:
    On-time delivery (OTD) is one of the most heavily scrutinized contractual
    KPIs in aerospace manufacturing, directly affecting customer satisfaction,
    contract penalties, and supplier/OEM scorecards. Executives track this
    number to gauge overall logistics and production reliability.
*/
SELECT
    COUNT(*)                                                                   AS TotalDeliveredShipments,
    SUM(CASE WHEN s.ActualArrivalDate <= s.EstimatedArrivalDate THEN 1 ELSE 0 END) AS OnTimeShipments,
    CAST(
        100.0 * SUM(CASE WHEN s.ActualArrivalDate <= s.EstimatedArrivalDate THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) AS DECIMAL(5, 2)
    )                                                                           AS OnTimeDeliveryPercentage
FROM dbo.Shipments AS s
WHERE s.Status = 'Delivered'
  AND s.ActualArrivalDate IS NOT NULL
  AND s.EstimatedArrivalDate IS NOT NULL;
GO


-- -----------------------------------------------------------------------------
-- EX-02: Plant-Wide Quality First-Pass Yield
-- -----------------------------------------------------------------------------
/*
Business Question:
    What percentage of final quality inspections pass on the first attempt,
    without failure or rework?

Business Value:
    First-Pass Yield (FPY) is a foundational aerospace quality metric tied
    directly to AS9100 compliance, cost of poor quality, and customer trust.
    A declining FPY is often an executive-level early warning signal for
    process, tooling, or supplier material issues.
*/
WITH FinalInspections AS (
    SELECT
        qi.InspectionID,
        qi.Result
    FROM dbo.QualityInspections AS qi
    WHERE qi.InspectionType = 'FinalInspection'
)
SELECT
    COUNT(*)                                                    AS TotalFinalInspections,
    SUM(CASE WHEN Result = 'Pass' THEN 1 ELSE 0 END)             AS PassedInspections,
    CAST(
        100.0 * SUM(CASE WHEN Result = 'Pass' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) AS DECIMAL(5, 2)
    )                                                             AS FirstPassYieldPercentage
FROM FinalInspections;
GO


-- -----------------------------------------------------------------------------
-- EX-03: Production Order Status Distribution & Completion Rate
-- -----------------------------------------------------------------------------
/*
Business Question:
    How are all production orders distributed across their lifecycle
    statuses (Scheduled, InProgress, Completed, OnHold, Cancelled), and what
    share of the total order book does each status represent?

Business Value:
    Gives leadership an immediate read on plant health: how much work is
    completed versus stuck, on hold, or cancelled. This is typically the
    first chart reviewed in a weekly operations review.
*/
SELECT
    po.Status,
    COUNT(*)                                                            AS OrderCount,
    CAST(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER ()
        AS DECIMAL(5, 2)
    )                                                                    AS PercentageOfTotalOrders
FROM dbo.ProductionOrders AS po
GROUP BY po.Status
ORDER BY OrderCount DESC;
GO


-- -----------------------------------------------------------------------------
-- EX-04: Monthly Production Volume Trend with Month-over-Month Growth
-- -----------------------------------------------------------------------------
/*
Business Question:
    How is total planned versus actual production volume trending month over
    month, and what is the percentage change in actual output versus the
    prior month?

Business Value:
    Reveals capacity trends and planning accuracy at a glance, and flags
    sudden output drops (capacity constraints, demand shifts, or systemic
    production issues) before they surface in quarterly financials.
*/
WITH MonthlyVolume AS (
    SELECT
        DATEFROMPARTS(YEAR(po.ScheduledStartDate), MONTH(po.ScheduledStartDate), 1) AS ProductionMonth,
        SUM(po.PlannedQuantity)                                                      AS TotalPlannedQuantity,
        SUM(po.ActualQuantity)                                                       AS TotalActualQuantity
    FROM dbo.ProductionOrders AS po
    GROUP BY DATEFROMPARTS(YEAR(po.ScheduledStartDate), MONTH(po.ScheduledStartDate), 1)
)
SELECT
    ProductionMonth,
    TotalPlannedQuantity,
    TotalActualQuantity,
    LAG(TotalActualQuantity) OVER (ORDER BY ProductionMonth)                         AS PriorMonthActualQuantity,
    CAST(
        100.0 * (TotalActualQuantity - LAG(TotalActualQuantity) OVER (ORDER BY ProductionMonth))
        / NULLIF(LAG(TotalActualQuantity) OVER (ORDER BY ProductionMonth), 0)
        AS DECIMAL(6, 2)
    )                                                                                 AS MoMGrowthPercentage
FROM MonthlyVolume
ORDER BY ProductionMonth;
GO


-- -----------------------------------------------------------------------------
-- EX-05: Top 10 Customers by Delivered Shipment Volume
-- -----------------------------------------------------------------------------
/*
Business Question:
    Which ten customers account for the largest volume of delivered product,
    and how does each customer rank against the others?

Business Value:
    Identifies the plant's most critical customer relationships, informing
    account prioritization, capacity allocation, and executive relationship
    management decisions.
*/
WITH CustomerShipments AS (
    SELECT
        c.CustomerID,
        c.CustomerName,
        SUM(s.ShippedQuantity) AS TotalShippedQuantity,
        COUNT(s.ShipmentID)    AS TotalShipments
    FROM dbo.Shipments AS s
    INNER JOIN dbo.Customers AS c ON c.CustomerID = s.CustomerID
    WHERE s.Status = 'Delivered'
    GROUP BY c.CustomerID, c.CustomerName
)
SELECT TOP (10)
    CustomerID,
    CustomerName,
    TotalShippedQuantity,
    TotalShipments,
    RANK() OVER (ORDER BY TotalShippedQuantity DESC) AS CustomerRank
FROM CustomerShipments
ORDER BY TotalShippedQuantity DESC;
GO


-- -----------------------------------------------------------------------------
-- EX-06: Plant-Wide Scrap Rate and Production Yield
-- -----------------------------------------------------------------------------
/*
Business Question:
    Across all production logs, what percentage of total units produced were
    scrapped, and what is the resulting overall production yield?

Business Value:
    Scrap directly erodes margin on high-cost aerospace materials (titanium,
    Inconel, composites). Executives monitor plant-wide scrap rate as a
    proxy for material cost efficiency and process control maturity.
*/
SELECT
    SUM(pl.UnitsProduced)                                                          AS TotalUnitsProduced,
    SUM(pl.UnitsScrapped)                                                          AS TotalUnitsScrapped,
    CAST(
        100.0 * SUM(pl.UnitsScrapped) / NULLIF(SUM(pl.UnitsProduced) + SUM(pl.UnitsScrapped), 0)
        AS DECIMAL(5, 2)
    )                                                                                AS ScrapRatePercentage,
    CAST(
        100.0 * SUM(pl.UnitsProduced) / NULLIF(SUM(pl.UnitsProduced) + SUM(pl.UnitsScrapped), 0)
        AS DECIMAL(5, 2)
    )                                                                                AS YieldPercentage
FROM dbo.ProductionLogs AS pl;
GO


-- -----------------------------------------------------------------------------
-- EX-07: Average Downtime Impact per Production Order
-- -----------------------------------------------------------------------------
/*
Business Question:
    On average, how many minutes of downtime are logged per production
    order, and what share of orders experience any downtime at all?

Business Value:
    Downtime is one of the largest hidden costs on the shop floor. This
    executive summary quantifies how pervasive downtime is across the order
    book, justifying investment in machine reliability or predictive
    maintenance programs.
*/
WITH OrderDowntime AS (
    SELECT
        pl.ProductionOrderID,
        SUM(pl.DowntimeMinutes) AS TotalDowntimeMinutes
    FROM dbo.ProductionLogs AS pl
    GROUP BY pl.ProductionOrderID
)
SELECT
    COUNT(*)                                                                       AS TotalOrdersLogged,
    AVG(TotalDowntimeMinutes)                                                      AS AvgDowntimeMinutesPerOrder,
    SUM(CASE WHEN TotalDowntimeMinutes > 0 THEN 1 ELSE 0 END)                      AS OrdersWithDowntimeEvents,
    CAST(
        100.0 * SUM(CASE WHEN TotalDowntimeMinutes > 0 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0)
        AS DECIMAL(5, 2)
    )                                                                                AS PercentOrdersWithDowntime
FROM OrderDowntime;
GO


-- -----------------------------------------------------------------------------
-- EX-08: Quarter-over-Quarter Open Production Order Backlog Trend
-- -----------------------------------------------------------------------------
/*
Business Question:
    How has the volume of open (not yet completed) production orders
    changed from one quarter to the next?

Business Value:
    A growing backlog signals capacity constraints or planning issues before
    they become customer-facing delays. Executives use this trend to decide
    when to add shifts, outsource work, or invest in additional capacity.
*/
WITH QuarterlyBacklog AS (
    SELECT
        DATEPART(YEAR, po.ScheduledStartDate)                                       AS OrderYear,
        DATEPART(QUARTER, po.ScheduledStartDate)                                    AS OrderQuarter,
        SUM(CASE WHEN po.Status IN ('Scheduled', 'InProgress', 'OnHold') THEN 1 ELSE 0 END) AS OpenOrders,
        COUNT(*)                                                                    AS TotalOrders
    FROM dbo.ProductionOrders AS po
    GROUP BY DATEPART(YEAR, po.ScheduledStartDate), DATEPART(QUARTER, po.ScheduledStartDate)
)
SELECT
    OrderYear,
    OrderQuarter,
    OpenOrders,
    TotalOrders,
    LAG(OpenOrders) OVER (ORDER BY OrderYear, OrderQuarter)                          AS PriorQuarterOpenOrders,
    OpenOrders - LAG(OpenOrders) OVER (ORDER BY OrderYear, OrderQuarter)              AS BacklogChangeVsPriorQuarter
FROM QuarterlyBacklog
ORDER BY OrderYear, OrderQuarter;
GO


/* #############################################################################
   SECTION 2: PRODUCTION ANALYTICS
   ############################################################################# */

-- -----------------------------------------------------------------------------
-- PA-01: Average Production Order Cycle Time by Priority Level
-- -----------------------------------------------------------------------------
/*
Business Question:
    What is the average, minimum, and maximum planned cycle time (in days)
    for production orders, broken down by priority level?

Business Value:
    Confirms whether high-priority and critical orders are actually being
    scheduled with shorter cycle times, and gives production planners a
    baseline for setting realistic due dates by priority tier.
*/
SELECT
    po.Priority,
    COUNT(*)                                                          AS OrderCount,
    AVG(DATEDIFF(DAY, po.ScheduledStartDate, po.ScheduledEndDate))     AS AvgPlannedCycleTimeDays,
    MIN(DATEDIFF(DAY, po.ScheduledStartDate, po.ScheduledEndDate))     AS MinPlannedCycleTimeDays,
    MAX(DATEDIFF(DAY, po.ScheduledStartDate, po.ScheduledEndDate))     AS MaxPlannedCycleTimeDays
FROM dbo.ProductionOrders AS po
GROUP BY po.Priority
ORDER BY
    CASE po.Priority
        WHEN 'Critical' THEN 1
        WHEN 'High'     THEN 2
        WHEN 'Medium'   THEN 3
        WHEN 'Low'      THEN 4
        ELSE 5
    END;
GO


-- -----------------------------------------------------------------------------
-- PA-02: Daily Production Output with 7-Day Moving Average
-- -----------------------------------------------------------------------------
/*
Business Question:
    What is daily plant-wide production output, smoothed with a 7-day
    moving average to reveal the underlying trend beneath daily noise?

Business Value:
    Moving averages help production supervisors distinguish a genuine
    output trend (ramping up, slowing down) from normal day-to-day
    variability, supporting more stable staffing and scheduling decisions.
*/
WITH DailyOutput AS (
    SELECT
        pl.LogDate,
        SUM(pl.UnitsProduced) AS DailyUnitsProduced,
        SUM(pl.UnitsScrapped) AS DailyUnitsScrapped
    FROM dbo.ProductionLogs AS pl
    GROUP BY pl.LogDate
)
SELECT
    LogDate,
    DailyUnitsProduced,
    DailyUnitsScrapped,
    AVG(DailyUnitsProduced) OVER (
        ORDER BY LogDate
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    )                                                                  AS SevenDayMovingAvgOutput
FROM DailyOutput
ORDER BY LogDate;
GO


-- -----------------------------------------------------------------------------
-- PA-03: Operator Productivity Ranking by Shift
-- -----------------------------------------------------------------------------
/*
Business Question:
    Within each shift (Day, Evening, Night), how do operators rank against
    one another by total units produced?

Business Value:
    Surfaces top performers for recognition and best-practice sharing, and
    flags operators who may need additional training or support, all
    normalized fairly within their own shift cohort.
*/
WITH OperatorOutput AS (
    SELECT
        o.OperatorID,
        o.FullName,
        o.Shift,
        SUM(pl.UnitsProduced)  AS TotalUnitsProduced,
        SUM(pl.UnitsScrapped)  AS TotalUnitsScrapped
    FROM dbo.ProductionLogs AS pl
    INNER JOIN dbo.Operators AS o ON o.OperatorID = pl.OperatorID
    GROUP BY o.OperatorID, o.FullName, o.Shift
)
SELECT
    OperatorID,
    FullName,
    Shift,
    TotalUnitsProduced,
    TotalUnitsScrapped,
    RANK() OVER (PARTITION BY Shift ORDER BY TotalUnitsProduced DESC) AS ProductivityRankInShift
FROM OperatorOutput
ORDER BY Shift, ProductivityRankInShift;
GO


-- -----------------------------------------------------------------------------
-- PA-04: Scrap Rate by Product
-- -----------------------------------------------------------------------------
/*
Business Question:
    Which products (by item) generate the highest scrap rates in production,
    and how should each be categorized for risk-based follow-up?

Business Value:
    Pinpoints exactly which parts are driving material waste, letting
    engineering and quality teams prioritize root-cause investigations on
    the highest-cost, highest-risk items first.
*/
WITH ProductScrap AS (
    SELECT
        i.ItemID,
        i.ItemName,
        i.ItemCategory,
        SUM(pl.UnitsProduced) AS TotalUnitsProduced,
        SUM(pl.UnitsScrapped) AS TotalUnitsScrapped
    FROM dbo.ProductionLogs AS pl
    INNER JOIN dbo.ProductionOrders AS po ON po.ProductionOrderID = pl.ProductionOrderID
    INNER JOIN dbo.InventoryItems AS i ON i.ItemID = po.ItemID
    GROUP BY i.ItemID, i.ItemName, i.ItemCategory
)
SELECT
    ItemID,
    ItemName,
    ItemCategory,
    TotalUnitsProduced,
    TotalUnitsScrapped,
    CAST(
        100.0 * TotalUnitsScrapped / NULLIF(TotalUnitsProduced + TotalUnitsScrapped, 0)
        AS DECIMAL(5, 2)
    )                                                                                    AS ScrapRatePercentage,
    CASE
        WHEN TotalUnitsScrapped = 0 THEN 'No Scrap'
        WHEN 100.0 * TotalUnitsScrapped / NULLIF(TotalUnitsProduced + TotalUnitsScrapped, 0) < 5  THEN 'Within Tolerance'
        WHEN 100.0 * TotalUnitsScrapped / NULLIF(TotalUnitsProduced + TotalUnitsScrapped, 0) < 15 THEN 'Elevated'
        ELSE 'Critical'
    END                                                                                    AS ScrapRiskCategory
FROM ProductScrap
ORDER BY ScrapRatePercentage DESC;
GO


-- -----------------------------------------------------------------------------
-- PA-05: Shift-Wise Production Performance Summary
-- -----------------------------------------------------------------------------
/*
Business Question:
    How do the Day, Evening, and Night shifts compare on total output, scrap,
    and downtime?

Business Value:
    Highlights systemic shift-level performance gaps (e.g. a night shift
    with materially higher scrap or downtime), pointing to staffing,
    training, or supervision issues that may not be visible in aggregate
    plant-wide numbers.
*/
SELECT
    o.Shift,
    COUNT(DISTINCT pl.ProductionLogID)                                                 AS TotalShiftLogEntries,
    SUM(pl.UnitsProduced)                                                              AS TotalUnitsProduced,
    SUM(pl.UnitsScrapped)                                                              AS TotalUnitsScrapped,
    SUM(pl.DowntimeMinutes)                                                            AS TotalDowntimeMinutes,
    CAST(
        100.0 * SUM(pl.UnitsScrapped) / NULLIF(SUM(pl.UnitsProduced) + SUM(pl.UnitsScrapped), 0)
        AS DECIMAL(5, 2)
    )                                                                                    AS ScrapRatePercentage
FROM dbo.ProductionLogs AS pl
INNER JOIN dbo.Operators AS o ON o.OperatorID = pl.OperatorID
GROUP BY o.Shift
ORDER BY TotalUnitsProduced DESC;
GO


-- -----------------------------------------------------------------------------
-- PA-06: Top Performing Machines by Production Output
-- -----------------------------------------------------------------------------
/*
Business Question:
    Which machines produce the highest output volumes, and how do they rank
    against each other?

Business Value:
    Identifies the highest-performing production machines based on output.
    This helps production managers balance workloads, identify bottlenecks,
    and prioritize maintenance for heavily utilized machines.
*/
WITH WorkCenterOutput AS (
    SELECT
        pl.MachineID,
        SUM(pl.UnitsProduced)   AS TotalUnitsProduced,
        SUM(pl.DowntimeMinutes) AS TotalDowntimeMinutes,
        COUNT(*)                AS TotalLogEntries
    FROM dbo.ProductionLogs AS pl
    GROUP BY pl.MachineID
)
SELECT
    MachineID,
    TotalUnitsProduced,
    TotalDowntimeMinutes,
    TotalLogEntries,
    RANK() OVER (ORDER BY TotalUnitsProduced DESC) AS OutputRank
FROM WorkCenterOutput
ORDER BY OutputRank;
GO


-- -----------------------------------------------------------------------------
-- PA-07: Production Orders At Risk of Schedule Slippage
-- -----------------------------------------------------------------------------
/*
Business Question:
    Which currently open production orders (Scheduled, InProgress, or
    OnHold) have already passed their scheduled end date?

Business Value:
    Gives production control a real-time, actionable watchlist of orders
    that need expediting, re-planning, or customer communication before
    they become formal delivery escalations.
*/
SELECT
    po.ProductionOrderID,
    po.ProductionOrderNumber,
    po.Status,
    po.Priority,
    po.ScheduledStartDate,
    po.ScheduledEndDate,
    DATEDIFF(DAY, po.ScheduledEndDate, CAST(GETDATE() AS DATE)) AS DaysPastDue,
    CASE
        WHEN po.Status IN ('Scheduled', 'InProgress', 'OnHold')
             AND po.ScheduledEndDate < CAST(GETDATE() AS DATE) THEN 'At Risk'
        ELSE 'On Track'
    END                                                          AS ScheduleRiskFlag
FROM dbo.ProductionOrders AS po
WHERE po.Status IN ('Scheduled', 'InProgress', 'OnHold')
ORDER BY DaysPastDue DESC;
GO


-- -----------------------------------------------------------------------------
-- PA-08: Cumulative Units Produced per Production Order Over Time
-- -----------------------------------------------------------------------------
/*
Business Question:
    For each production order, how does cumulative units produced build up
    log entry by log entry, over the life of the order?

Business Value:
    Powers production burn-up charts that let supervisors see, at a glance,
    whether a specific order is tracking to its planned quantity on schedule
    or falling behind pace mid-run.
*/
SELECT
    pl.ProductionOrderID,
    pl.LogDate,
    pl.UnitsProduced,
    SUM(pl.UnitsProduced) OVER (
        PARTITION BY pl.ProductionOrderID
        ORDER BY pl.LogDate
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS CumulativeUnitsProduced
FROM dbo.ProductionLogs AS pl
ORDER BY pl.ProductionOrderID, pl.LogDate;
GO


/* =============================================================================
   AeroPulse AI - Digital Manufacturing Analytics Platform
   analytics_queries.sql  (PART 2 of N)

   Scope of this part:
     Advanced analytics covering Machine Performance, Predictive Maintenance,
     Supplier Performance, Inventory Consumption/Aging/Turnover, Supply Chain
     & Logistics, Customer Demand, Quality/Scrap/Rework Trends, Work Center
     Performance, Production Bottlenecks, Process Stability, and Production
     Forecasting.

   Continues directly from Part 1 (EX-01..EX-08, PA-01..PA-08).
   Target: Microsoft SQL Server (T-SQL)
   ============================================================================= */


----------------------------------------------------------------------------
-- Query 17
-- Machine Utilization Rate Analysis
----------------------------------------------------------------------------
/*
Business Question:
    What percentage of each machine's total logged shift time was actually
    productive (i.e. not lost to downtime)?

Business Value:
    Utilization rate is the core capacity metric for capital-intensive
    aerospace machining assets. Machines running below target utilization
    are candidates for root-cause investigation, rescheduling, or
    reallocation of work.
*/
WITH MachineShiftTime AS (
    SELECT
        pl.MachineID,
        SUM(DATEDIFF(MINUTE, pl.ShiftStartTime, pl.ShiftEndTime)) AS TotalShiftMinutes,
        SUM(pl.DowntimeMinutes)                                   AS TotalDowntimeMinutes
    FROM dbo.ProductionLogs AS pl
    GROUP BY pl.MachineID
),
MachineUtilization AS (
    SELECT
        MachineID,
        TotalShiftMinutes,
        TotalDowntimeMinutes,
        CAST(
            100.0 * (TotalShiftMinutes - TotalDowntimeMinutes) / NULLIF(TotalShiftMinutes, 0)
            AS DECIMAL(5, 2)
        ) AS UtilizationRatePercentage
    FROM MachineShiftTime
)
SELECT
    m.MachineID,
    m.MachineCode,
    m.MachineName,
    m.MachineType,
    mu.TotalShiftMinutes,
    mu.TotalDowntimeMinutes,
    mu.UtilizationRatePercentage,
    CASE
        WHEN mu.UtilizationRatePercentage >= 85 THEN 'High'
        WHEN mu.UtilizationRatePercentage >= 70 THEN 'Moderate'
        ELSE 'Low'
    END AS UtilizationTier
FROM dbo.Machines AS m
INNER JOIN MachineUtilization AS mu ON mu.MachineID = m.MachineID
ORDER BY mu.UtilizationRatePercentage DESC;
GO


----------------------------------------------------------------------------
-- Query 18
-- Machine Performance Ranking
----------------------------------------------------------------------------
/*
Business Question:
    How do machines rank against each other on output volume and on
    reliability (least downtime), and which output quartile does each
    machine fall into?

Business Value:
    Gives plant engineering a single ranked view to prioritize capital
    reinvestment, retirement, or process-improvement projects toward the
    machines with the greatest performance gap.
*/
WITH MachineStats AS (
    SELECT
        pl.MachineID,
        SUM(pl.UnitsProduced)   AS TotalUnitsProduced,
        SUM(pl.DowntimeMinutes) AS TotalDowntimeMinutes,
        COUNT(*)                AS TotalLogEntries
    FROM dbo.ProductionLogs AS pl
    GROUP BY pl.MachineID
)
SELECT
    m.MachineID,
    m.MachineCode,
    m.MachineName,
    m.MachineType,
    m.Status,
    ms.TotalUnitsProduced,
    ms.TotalDowntimeMinutes,
    DENSE_RANK() OVER (ORDER BY ms.TotalUnitsProduced DESC)   AS OutputRank,
    DENSE_RANK() OVER (ORDER BY ms.TotalDowntimeMinutes ASC)  AS ReliabilityRank,
    NTILE(4) OVER (ORDER BY ms.TotalUnitsProduced DESC)       AS OutputQuartile
FROM dbo.Machines AS m
INNER JOIN MachineStats AS ms ON ms.MachineID = m.MachineID
ORDER BY OutputRank;
GO


----------------------------------------------------------------------------
-- Query 19
-- Predictive Maintenance Risk Scoring
----------------------------------------------------------------------------
/*
Business Question:
    Combining sensor anomaly frequency with time elapsed since last
    completed maintenance, which machines carry the highest predictive
    failure risk right now?

Business Value:
    Moves maintenance planning from purely calendar-based (preventive) to
    condition-based (predictive), reducing unplanned downtime and
    catastrophic failures on high-value aerospace machining equipment.
*/
WITH SensorAnomalyRate AS (
    SELECT
        MachineID,
        COUNT(*)                                              AS TotalReadings,
        SUM(CASE WHEN IsAnomaly = 1 THEN 1 ELSE 0 END)         AS AnomalyReadings,
        CAST(
            100.0 * SUM(CASE WHEN IsAnomaly = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0)
            AS DECIMAL(5, 2)
        )                                                      AS AnomalyRatePercentage
    FROM dbo.MachineSensorData
    GROUP BY MachineID
),
LastMaintenance AS (
    SELECT
        MachineID,
        MAX(StartTime) AS LastMaintenanceDate
    FROM dbo.MaintenanceLogs
    WHERE Status = 'Completed'
    GROUP BY MachineID
)
SELECT
    m.MachineID,
    m.MachineCode,
    m.MachineName,
    COALESCE(sar.AnomalyRatePercentage, 0)                                AS AnomalyRatePercentage,
    lm.LastMaintenanceDate,
    DATEDIFF(DAY, lm.LastMaintenanceDate, GETDATE())                      AS DaysSinceLastMaintenance,
    CASE
        WHEN lm.LastMaintenanceDate IS NULL THEN 'Critical - Never Serviced'
        WHEN COALESCE(sar.AnomalyRatePercentage, 0) > 10
             AND DATEDIFF(DAY, lm.LastMaintenanceDate, GETDATE()) > 180 THEN 'Critical'
        WHEN COALESCE(sar.AnomalyRatePercentage, 0) > 5
             OR DATEDIFF(DAY, lm.LastMaintenanceDate, GETDATE()) > 120 THEN 'Elevated'
        ELSE 'Normal'
    END AS PredictiveMaintenanceRiskTier
FROM dbo.Machines AS m
LEFT JOIN SensorAnomalyRate AS sar ON sar.MachineID = m.MachineID
LEFT JOIN LastMaintenance AS lm ON lm.MachineID = m.MachineID
ORDER BY AnomalyRatePercentage DESC;
GO


----------------------------------------------------------------------------
-- Query 20
-- Maintenance Interval Analysis
----------------------------------------------------------------------------
/*
Business Question:
    For each machine, how many days elapse between consecutive completed
    maintenance events, and how consistent are those intervals?

Business Value:
    Reveals whether maintenance is happening at a stable, predictable
    cadence per machine or drifting - a leading indicator of maintenance
    program discipline and a key input to preventive maintenance scheduling.
*/
WITH MaintenanceHistory AS (
    SELECT
        MachineID,
        MaintenanceType,
        StartTime,
        LAG(StartTime) OVER (PARTITION BY MachineID ORDER BY StartTime) AS PriorMaintenanceDate
    FROM dbo.MaintenanceLogs
    WHERE Status = 'Completed'
)
SELECT
    MachineID,
    MaintenanceType,
    StartTime AS MaintenanceDate,
    PriorMaintenanceDate,
    DATEDIFF(DAY, PriorMaintenanceDate, StartTime) AS DaysSincePriorMaintenance
FROM MaintenanceHistory
WHERE PriorMaintenanceDate IS NOT NULL
ORDER BY MachineID, StartTime;
GO


----------------------------------------------------------------------------
-- Query 21
-- Latest Maintenance Snapshot per Machine
----------------------------------------------------------------------------
/*
Business Question:
    What was the most recent completed maintenance event for every machine
    in the fleet, including machines that have never been serviced?

Business Value:
    Gives maintenance planners a single-row-per-machine snapshot for daily
    stand-up review, immediately surfacing machines with no service history
    via a NULL last-maintenance date.
*/
SELECT
    m.MachineID,
    m.MachineCode,
    m.MachineName,
    m.Status,
    lm.MaintenanceType AS LastMaintenanceType,
    lm.StartTime        AS LastMaintenanceStart,
    lm.Cost              AS LastMaintenanceCost
FROM dbo.Machines AS m
OUTER APPLY (
    SELECT TOP (1)
        ml.MaintenanceType,
        ml.StartTime,
        ml.Cost
    FROM dbo.MaintenanceLogs AS ml
    WHERE ml.MachineID = m.MachineID
      AND ml.Status = 'Completed'
    ORDER BY ml.StartTime DESC
) AS lm
ORDER BY lm.StartTime DESC;
GO


----------------------------------------------------------------------------
-- Query 22
-- Supplier On-Time Delivery Performance Ranking
----------------------------------------------------------------------------
/*
Business Question:
    How do suppliers rank against each other based on the rate of open
    purchase orders that have passed their expected delivery date?

Business Value:
    Provides procurement with an objective, ranked view of supplier
    delivery reliability, supporting sourcing decisions, scorecards, and
    supplier development conversations.
*/
WITH SupplierOrders AS (
    SELECT
        po.SupplierID,
        COUNT(*)                                                                    AS TotalOrders,
        SUM(CASE WHEN po.Status = 'Received' THEN 1 ELSE 0 END)                     AS ReceivedOrders,
        SUM(CASE
                WHEN po.Status IN ('Pending', 'Approved', 'Shipped', 'PartiallyReceived')
                     AND po.ExpectedDeliveryDate < CAST(GETDATE() AS DATE) THEN 1
                ELSE 0
            END)                                                                     AS OverdueOpenOrders
    FROM dbo.PurchaseOrders AS po
    WHERE po.Status <> 'Cancelled'
    GROUP BY po.SupplierID
)
SELECT
    s.SupplierID,
    s.SupplierCode,
    s.SupplierName,
    s.QualityRating,
    so.TotalOrders,
    so.ReceivedOrders,
    so.OverdueOpenOrders,
    CAST(100.0 * so.OverdueOpenOrders / NULLIF(so.TotalOrders, 0) AS DECIMAL(5, 2)) AS OverdueRatePercentage,
    RANK() OVER (
        ORDER BY CAST(100.0 * so.OverdueOpenOrders / NULLIF(so.TotalOrders, 0) AS DECIMAL(5, 2)) ASC
    ) AS OnTimePerformanceRank
FROM dbo.Suppliers AS s
INNER JOIN SupplierOrders AS so ON so.SupplierID = s.SupplierID
ORDER BY OnTimePerformanceRank;
GO


----------------------------------------------------------------------------
-- Query 23
-- Supplier Composite Risk Scorecard
----------------------------------------------------------------------------
/*
Business Question:
    Combining quality rating and delivery delay history, how should each
    active supplier be classified into a risk tier?

Business Value:
    Consolidates two independent risk signals - quality and delivery - into
    a single actionable tier that procurement leadership can use to decide
    where to dual-source or apply increased incoming inspection.
*/
WITH SupplierSpend AS (
    SELECT
        SupplierID,
        SUM(TotalAmount) AS TotalSpend,
        COUNT(*)          AS TotalOrders
    FROM dbo.PurchaseOrders
    GROUP BY SupplierID
),
SupplierDelay AS (
    SELECT
        SupplierID,
        SUM(CASE
                WHEN Status IN ('Pending', 'Approved', 'Shipped', 'PartiallyReceived')
                     AND ExpectedDeliveryDate < CAST(GETDATE() AS DATE) THEN 1
                ELSE 0
            END) AS DelayedOrders
    FROM dbo.PurchaseOrders
    GROUP BY SupplierID
)
SELECT
    s.SupplierID,
    s.SupplierName,
    s.QualityRating,
    COALESCE(ss.TotalSpend, 0)  AS TotalSpend,
    COALESCE(ss.TotalOrders, 0) AS TotalOrders,
    COALESCE(sd.DelayedOrders, 0) AS DelayedOrders,
    CASE
        WHEN s.QualityRating < 3 OR COALESCE(sd.DelayedOrders, 0) > 5 THEN 'High Risk'
        WHEN s.QualityRating < 4 OR COALESCE(sd.DelayedOrders, 0) BETWEEN 1 AND 5 THEN 'Moderate Risk'
        ELSE 'Low Risk'
    END AS SupplierRiskTier
FROM dbo.Suppliers AS s
LEFT JOIN SupplierSpend AS ss ON ss.SupplierID = s.SupplierID
LEFT JOIN SupplierDelay AS sd ON sd.SupplierID = s.SupplierID
WHERE s.IsActive = 1
ORDER BY SupplierRiskTier, TotalSpend DESC;
GO


----------------------------------------------------------------------------
-- Query 24
-- Inventory Turnover Ratio Analysis
----------------------------------------------------------------------------
/*
Business Question:
    For each inventory item, how does total quantity received from suppliers
    compare to quantity currently on hand, as a proxy for turnover velocity?

Business Value:
    Highlights fast-moving items (high turnover, tight buffer risk) versus
    slow-moving items (low turnover, working-capital drag), informing
    reorder-point and safety-stock policy by item.
*/
WITH ItemReceipts AS (
    SELECT
        ItemID,
        SUM(QuantityReceived) AS TotalQuantityReceived
    FROM dbo.PurchaseOrderLines
    GROUP BY ItemID
)
SELECT
    i.ItemID,
    i.ItemCode,
    i.ItemName,
    i.ItemCategory,
    i.QuantityOnHand,
    COALESCE(ir.TotalQuantityReceived, 0) AS TotalQuantityReceived,
    CAST(
        COALESCE(ir.TotalQuantityReceived, 0) / NULLIF(i.QuantityOnHand, 0)
        AS DECIMAL(10, 2)
    ) AS InventoryTurnoverRatio
FROM dbo.InventoryItems AS i
LEFT JOIN ItemReceipts AS ir ON ir.ItemID = i.ItemID
ORDER BY InventoryTurnoverRatio DESC;
GO


----------------------------------------------------------------------------
-- Query 25
-- Inventory Aging Analysis
----------------------------------------------------------------------------
/*
Business Question:
    How old is each inventory record since it was first established in the
    system, and which aging quartile and category does it fall into?

Business Value:
    Flags candidates for obsolescence review, cycle counting, or write-off
    consideration - particularly important for aerospace materials with
    shelf-life or certification expiry constraints.
*/
SELECT
    i.ItemID,
    i.ItemCode,
    i.ItemName,
    i.ItemCategory,
    i.CreatedAt,
    DATEDIFF(DAY, i.CreatedAt, GETDATE()) AS InventoryAgeDays,
    NTILE(4) OVER (ORDER BY DATEDIFF(DAY, i.CreatedAt, GETDATE()) DESC) AS AgingQuartile,
    CASE
        WHEN DATEDIFF(DAY, i.CreatedAt, GETDATE()) > 730 THEN 'Aged > 2 Years'
        WHEN DATEDIFF(DAY, i.CreatedAt, GETDATE()) > 365 THEN 'Aged 1-2 Years'
        WHEN DATEDIFF(DAY, i.CreatedAt, GETDATE()) > 180 THEN 'Aged 6-12 Months'
        ELSE 'Recent (< 6 Months)'
    END AS AgingCategory
FROM dbo.InventoryItems AS i
ORDER BY InventoryAgeDays DESC;
GO


----------------------------------------------------------------------------
-- Query 26
-- Inventory Items Never Received From Suppliers
----------------------------------------------------------------------------
/*
Business Question:
    Which inventory items exist in the catalog but have never had a single
    purchase order line raised against them?

Business Value:
    Surfaces likely dead stock, obsolete part numbers, or master-data
    entry errors, helping materials management clean up the catalog and
    avoid carrying cost on items with no procurement history.
*/
SELECT
    i.ItemID,
    i.ItemCode,
    i.ItemName,
    i.ItemCategory,
    i.QuantityOnHand,
    i.WarehouseLocation
FROM dbo.InventoryItems AS i
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.PurchaseOrderLines AS pol
    WHERE pol.ItemID = i.ItemID
)
ORDER BY i.QuantityOnHand DESC;
GO


----------------------------------------------------------------------------
-- Query 27
-- Material Consumption Trend by Item Category
----------------------------------------------------------------------------
/*
Business Question:
    How does monthly material consumption (via actual production quantity)
    trend for each inventory item category, and what is the month-over-month
    change?

Business Value:
    Supports procurement forecasting and supplier capacity planning by
    category (raw material, component, sub-assembly, etc.), helping avoid
    both shortages and excess buffer stock.
*/
WITH MonthlyConsumption AS (
    SELECT
        i.ItemCategory,
        DATEFROMPARTS(YEAR(po.ScheduledStartDate), MONTH(po.ScheduledStartDate), 1) AS ConsumptionMonth,
        SUM(po.ActualQuantity)                                                       AS TotalConsumedQuantity
    FROM dbo.ProductionOrders AS po
    INNER JOIN dbo.InventoryItems AS i ON i.ItemID = po.ItemID
    GROUP BY i.ItemCategory, DATEFROMPARTS(YEAR(po.ScheduledStartDate), MONTH(po.ScheduledStartDate), 1)
)
SELECT
    ItemCategory,
    ConsumptionMonth,
    TotalConsumedQuantity,
    LAG(TotalConsumedQuantity) OVER (PARTITION BY ItemCategory ORDER BY ConsumptionMonth) AS PriorMonthConsumption,
    TotalConsumedQuantity
        - LAG(TotalConsumedQuantity) OVER (PARTITION BY ItemCategory ORDER BY ConsumptionMonth) AS MoMChange
FROM MonthlyConsumption
ORDER BY ItemCategory, ConsumptionMonth;
GO


----------------------------------------------------------------------------
-- Query 28
-- Purchase Order Line Fulfillment Performance
----------------------------------------------------------------------------
/*
Business Question:
    Across all active (non-cancelled) purchase orders, what share of each
    order line has actually been received, and how should each line be
    classified?

Business Value:
    Gives materials management a line-item-level worklist of exactly what
    is fully received, partially received, or entirely outstanding -
    essential for expediting decisions ahead of production need dates.
*/
SELECT
    pol.PurchaseOrderLineID,
    pol.PurchaseOrderID,
    pol.ItemID,
    pol.QuantityOrdered,
    pol.QuantityReceived,
    CAST(100.0 * pol.QuantityReceived / NULLIF(pol.QuantityOrdered, 0) AS DECIMAL(5, 2)) AS FulfillmentRatePercentage,
    CASE
        WHEN pol.QuantityReceived = 0 THEN 'Not Received'
        WHEN pol.QuantityReceived >= pol.QuantityOrdered THEN 'Fully Received'
        ELSE 'Partially Received'
    END AS FulfillmentStatus
FROM dbo.PurchaseOrderLines AS pol
WHERE EXISTS (
    SELECT 1
    FROM dbo.PurchaseOrders AS po
    WHERE po.PurchaseOrderID = pol.PurchaseOrderID
      AND po.Status <> 'Cancelled'
)
ORDER BY FulfillmentRatePercentage ASC;
GO


----------------------------------------------------------------------------
-- Query 29
-- Supply Chain Lead Time Variability by Supplier
----------------------------------------------------------------------------
/*
Business Question:
    For each supplier, what is the average planned lead time, and how much
    does that lead time vary (standard deviation) across their orders?

Business Value:
    A supplier with a long but consistent lead time is often easier to plan
    around than one with a shorter but highly variable lead time. This
    surfaces the true planning risk behind each supplier relationship.
*/
WITH SupplierLeadTimes AS (
    SELECT
        SupplierID,
        DATEDIFF(DAY, OrderDate, ExpectedDeliveryDate) AS PlannedLeadTimeDays
    FROM dbo.PurchaseOrders
    WHERE ExpectedDeliveryDate IS NOT NULL
)
SELECT
    s.SupplierID,
    s.SupplierName,
    COUNT(*)                                        AS TotalOrders,
    AVG(slt.PlannedLeadTimeDays)                     AS AvgLeadTimeDays,
    CAST(STDEV(slt.PlannedLeadTimeDays) AS DECIMAL(8, 2)) AS LeadTimeStdDevDays,
    MIN(slt.PlannedLeadTimeDays)                     AS MinLeadTimeDays,
    MAX(slt.PlannedLeadTimeDays)                     AS MaxLeadTimeDays
FROM SupplierLeadTimes AS slt
INNER JOIN dbo.Suppliers AS s ON s.SupplierID = slt.SupplierID
GROUP BY s.SupplierID, s.SupplierName
HAVING COUNT(*) > 1
ORDER BY LeadTimeStdDevDays DESC;
GO


----------------------------------------------------------------------------
-- Query 30
-- Logistics and Carrier Delivery Performance
----------------------------------------------------------------------------
/*
Business Question:
    How does each outbound carrier perform on on-time delivery rate and
    average transit time across all shipments handled?

Business Value:
    Informs carrier selection and contract negotiation by quantifying which
    logistics partners consistently meet delivery commitments to aerospace
    customers versus which introduce delivery risk.
*/
SELECT
    COALESCE(s.Carrier, 'Unknown')                                                        AS Carrier,
    COUNT(*)                                                                                AS TotalShipments,
    SUM(CASE WHEN s.Status = 'Delivered' THEN 1 ELSE 0 END)                                AS DeliveredShipments,
    SUM(CASE
            WHEN s.Status = 'Delivered' AND s.ActualArrivalDate <= s.EstimatedArrivalDate THEN 1
            ELSE 0
        END)                                                                                AS OnTimeDeliveries,
    CAST(
        100.0 * SUM(CASE
                        WHEN s.Status = 'Delivered' AND s.ActualArrivalDate <= s.EstimatedArrivalDate THEN 1
                        ELSE 0
                    END)
        / NULLIF(SUM(CASE WHEN s.Status = 'Delivered' THEN 1 ELSE 0 END), 0)
        AS DECIMAL(5, 2)
    )                                                                                       AS OnTimeRatePercentage,
    AVG(DATEDIFF(DAY, s.ShipmentDate, s.ActualArrivalDate))                                AS AvgTransitDays
FROM dbo.Shipments AS s
GROUP BY s.Carrier
ORDER BY OnTimeRatePercentage DESC;
GO


----------------------------------------------------------------------------
-- Query 31
-- Customer Demand Trend Analysis
----------------------------------------------------------------------------
/*
Business Question:
    How does each customer's monthly planned demand trend over time, and
    which demand quartile does each customer-month fall into relative to
    all others?

Business Value:
    Supports account-level sales and operations planning (S&OP) by
    revealing which customers are ramping up, flattening, or pulling back
    demand - critical input for capacity and material planning.
*/
WITH MonthlyCustomerDemand AS (
    SELECT
        po.CustomerID,
        DATEFROMPARTS(YEAR(po.ScheduledStartDate), MONTH(po.ScheduledStartDate), 1) AS DemandMonth,
        SUM(po.PlannedQuantity)                                                      AS TotalDemandQuantity
    FROM dbo.ProductionOrders AS po
    WHERE po.CustomerID IS NOT NULL
    GROUP BY po.CustomerID, DATEFROMPARTS(YEAR(po.ScheduledStartDate), MONTH(po.ScheduledStartDate), 1)
),
DemandWithTrend AS (
    SELECT
        CustomerID,
        DemandMonth,
        TotalDemandQuantity,
        LAG(TotalDemandQuantity) OVER (PARTITION BY CustomerID ORDER BY DemandMonth)  AS PriorMonthDemand,
        LEAD(TotalDemandQuantity) OVER (PARTITION BY CustomerID ORDER BY DemandMonth) AS NextMonthDemand
    FROM MonthlyCustomerDemand
)
SELECT
    dwt.CustomerID,
    c.CustomerName,
    dwt.DemandMonth,
    dwt.TotalDemandQuantity,
    dwt.PriorMonthDemand,
    dwt.NextMonthDemand,
    NTILE(4) OVER (ORDER BY dwt.TotalDemandQuantity DESC) AS DemandQuartile
FROM DemandWithTrend AS dwt
INNER JOIN dbo.Customers AS c ON c.CustomerID = dwt.CustomerID
ORDER BY dwt.CustomerID, dwt.DemandMonth;
GO


----------------------------------------------------------------------------
-- Query 32
-- Quality Pass Rate Trend Analysis
----------------------------------------------------------------------------
/*
Business Question:
    How has the plant-wide quality inspection pass rate trended month over
    month, and what is the change versus the prior month?

Business Value:
    Time-series quality tracking distinguishes a one-off bad batch from a
    sustained downward trend that warrants a formal corrective action
    investigation under the quality management system.
*/
WITH MonthlyQuality AS (
    SELECT
        DATEFROMPARTS(YEAR(InspectionDate), MONTH(InspectionDate), 1) AS InspectionMonth,
        COUNT(*)                                                      AS TotalInspections,
        SUM(CASE WHEN Result = 'Pass' THEN 1 ELSE 0 END)               AS PassedInspections
    FROM dbo.QualityInspections
    GROUP BY DATEFROMPARTS(YEAR(InspectionDate), MONTH(InspectionDate), 1)
)
SELECT
    InspectionMonth,
    TotalInspections,
    PassedInspections,
    CAST(100.0 * PassedInspections / NULLIF(TotalInspections, 0) AS DECIMAL(5, 2)) AS PassRatePercentage,
    LAG(CAST(100.0 * PassedInspections / NULLIF(TotalInspections, 0) AS DECIMAL(5, 2)))
        OVER (ORDER BY InspectionMonth) AS PriorMonthPassRate
FROM MonthlyQuality
ORDER BY InspectionMonth;
GO


----------------------------------------------------------------------------
-- Query 33
-- Scrap and Rework Trend Analysis
----------------------------------------------------------------------------
/*
Business Question:
    How do monthly scrap rate (from production logs) and rework volume
    (from quality inspections) trend together over time?

Business Value:
    Correlating scrap and rework trends helps quality engineering determine
    whether cost-of-poor-quality is rising due to process drift, material
    issues, or a specific product introduction, and whether the two metrics
    are moving in tandem.
*/
WITH MonthlyScrap AS (
    SELECT
        DATEFROMPARTS(YEAR(LogDate), MONTH(LogDate), 1) AS ProductionMonth,
        SUM(UnitsProduced)                                AS TotalUnitsProduced,
        SUM(UnitsScrapped)                                AS TotalUnitsScrapped
    FROM dbo.ProductionLogs
    GROUP BY DATEFROMPARTS(YEAR(LogDate), MONTH(LogDate), 1)
),
MonthlyRework AS (
    SELECT
        DATEFROMPARTS(YEAR(InspectionDate), MONTH(InspectionDate), 1) AS InspectionMonth,
        SUM(CASE WHEN Result = 'ReworkRequired' THEN 1 ELSE 0 END)     AS ReworkCount
    FROM dbo.QualityInspections
    GROUP BY DATEFROMPARTS(YEAR(InspectionDate), MONTH(InspectionDate), 1)
)
SELECT
    ms.ProductionMonth,
    ms.TotalUnitsProduced,
    ms.TotalUnitsScrapped,
    CAST(
        100.0 * ms.TotalUnitsScrapped / NULLIF(ms.TotalUnitsProduced + ms.TotalUnitsScrapped, 0)
        AS DECIMAL(5, 2)
    ) AS ScrapRatePercentage,
    COALESCE(mr.ReworkCount, 0) AS ReworkCount
FROM MonthlyScrap AS ms
LEFT JOIN MonthlyRework AS mr ON mr.InspectionMonth = ms.ProductionMonth
ORDER BY ms.ProductionMonth;
GO


----------------------------------------------------------------------------
-- Query 34
-- Downtime Trend Analysis and Top Offending Work Centers
----------------------------------------------------------------------------
/*
Business Question:
    Which machines accumulate the most downtime each month, how does each
    machine's downtime compare to the prior month, and how do machines rank
    against each other within the same month?

Business Value:
    Focuses reliability engineering effort on the specific machines driving
    the largest downtime losses in the most recent period, rather than
    spreading attention evenly across the whole fleet.
*/
WITH MonthlyMachineDowntime AS (
    SELECT
        MachineID,
        DATEFROMPARTS(YEAR(LogDate), MONTH(LogDate), 1) AS DowntimeMonth,
        SUM(DowntimeMinutes)                              AS TotalDowntimeMinutes
    FROM dbo.ProductionLogs
    GROUP BY MachineID, DATEFROMPARTS(YEAR(LogDate), MONTH(LogDate), 1)
)
SELECT
    mmd.MachineID,
    m.MachineCode,
    m.MachineName,
    mmd.DowntimeMonth,
    mmd.TotalDowntimeMinutes,
    LAG(mmd.TotalDowntimeMinutes) OVER (PARTITION BY mmd.MachineID ORDER BY mmd.DowntimeMonth) AS PriorMonthDowntime,
    RANK() OVER (PARTITION BY mmd.DowntimeMonth ORDER BY mmd.TotalDowntimeMinutes DESC)        AS DowntimeRankInMonth
FROM MonthlyMachineDowntime AS mmd
INNER JOIN dbo.Machines AS m ON m.MachineID = mmd.MachineID
ORDER BY mmd.DowntimeMonth, DowntimeRankInMonth;
GO


----------------------------------------------------------------------------
-- Query 35
-- Work Center Performance Deep-Dive with Capacity Utilization
----------------------------------------------------------------------------
/*
Business Question:
    Combining production output, downtime-adjusted capacity utilization,
    and total maintenance spend, how does each work center perform overall?

Business Value:
    A single consolidated view per machine supports capacity planning and
    total-cost-of-ownership conversations, connecting shop-floor output
    directly to the maintenance investment required to sustain it.
*/
WITH ProductionStats AS (
    SELECT
        MachineID,
        SUM(UnitsProduced)                                            AS TotalUnitsProduced,
        SUM(DowntimeMinutes)                                          AS TotalDowntimeMinutes,
        SUM(DATEDIFF(MINUTE, ShiftStartTime, ShiftEndTime))           AS TotalLoggedMinutes
    FROM dbo.ProductionLogs
    GROUP BY MachineID
),
MaintenanceCost AS (
    SELECT
        MachineID,
        SUM(Cost) AS TotalMaintenanceCost,
        COUNT(*)  AS TotalMaintenanceEvents
    FROM dbo.MaintenanceLogs
    GROUP BY MachineID
)
SELECT
    m.MachineID,
    m.MachineCode,
    m.MachineName,
    m.MachineType,
    m.Status,
    COALESCE(ps.TotalUnitsProduced, 0)   AS TotalUnitsProduced,
    COALESCE(ps.TotalDowntimeMinutes, 0) AS TotalDowntimeMinutes,
    CAST(
        100.0 * (COALESCE(ps.TotalLoggedMinutes, 0) - COALESCE(ps.TotalDowntimeMinutes, 0))
        / NULLIF(ps.TotalLoggedMinutes, 0)
        AS DECIMAL(5, 2)
    )                                     AS CapacityUtilizationPercentage,
    COALESCE(mc.TotalMaintenanceCost, 0)  AS TotalMaintenanceCost,
    COALESCE(mc.TotalMaintenanceEvents, 0) AS TotalMaintenanceEvents
FROM dbo.Machines AS m
LEFT JOIN ProductionStats AS ps ON ps.MachineID = m.MachineID
LEFT JOIN MaintenanceCost AS mc ON mc.MachineID = m.MachineID
ORDER BY CapacityUtilizationPercentage DESC;
GO


----------------------------------------------------------------------------
-- Query 36
-- Production Bottleneck Identification
----------------------------------------------------------------------------
/*
Business Question:
    Which machines simultaneously carry both the heaviest production order
    load and the highest downtime, marking them as likely bottlenecks in
    the production flow?

Business Value:
    Bottleneck machines constrain total plant throughput regardless of how
    well other work centers perform. This flags the specific assets where
    a capacity or reliability investment will have the largest plant-wide
    impact.
*/
WITH MachineLoad AS (
    SELECT
        MachineID,
        SUM(UnitsProduced)                     AS TotalUnitsProduced,
        SUM(DowntimeMinutes)                   AS TotalDowntimeMinutes,
        COUNT(DISTINCT ProductionOrderID)      AS OrdersServed
    FROM dbo.ProductionLogs
    GROUP BY MachineID
),
MachineLoadRanked AS (
    SELECT
        MachineID,
        TotalUnitsProduced,
        TotalDowntimeMinutes,
        OrdersServed,
        NTILE(4) OVER (ORDER BY TotalDowntimeMinutes DESC) AS DowntimeQuartile,
        NTILE(4) OVER (ORDER BY OrdersServed DESC)         AS LoadQuartile
    FROM MachineLoad
)
SELECT
    mlr.MachineID,
    m.MachineCode,
    m.MachineName,
    mlr.TotalUnitsProduced,
    mlr.TotalDowntimeMinutes,
    mlr.OrdersServed,
    CASE
        WHEN mlr.DowntimeQuartile = 1 AND mlr.LoadQuartile = 1 THEN 'Critical Bottleneck'
        WHEN mlr.DowntimeQuartile = 1 OR mlr.LoadQuartile = 1 THEN 'Potential Bottleneck'
        ELSE 'Normal'
    END AS BottleneckFlag
FROM MachineLoadRanked AS mlr
INNER JOIN dbo.Machines AS m ON m.MachineID = mlr.MachineID
ORDER BY BottleneckFlag, mlr.TotalDowntimeMinutes DESC;
GO


----------------------------------------------------------------------------
-- Query 37
-- Process Stability Analysis via Sensor Variability
----------------------------------------------------------------------------
/*
Business Question:
    For each machine, how stable are its temperature and vibration readings
    (measured by standard deviation), and what is its overall sensor
    anomaly rate?

Business Value:
    High variability in process signals often precedes a quality escape or
    equipment failure, even before individual readings cross an anomaly
    threshold. This gives process engineers an early statistical-process-
    control style view of machine health.
*/
SELECT
    m.MachineID,
    m.MachineCode,
    m.MachineName,
    COUNT(*)                                       AS TotalReadings,
    CAST(AVG(sd.Temperature) AS DECIMAL(8, 3))      AS AvgTemperature,
    CAST(STDEV(sd.Temperature) AS DECIMAL(8, 3))    AS TemperatureStdDev,
    CAST(AVG(sd.Vibration) AS DECIMAL(8, 3))        AS AvgVibration,
    CAST(STDEV(sd.Vibration) AS DECIMAL(8, 3))      AS VibrationStdDev,
    CAST(
        100.0 * SUM(CASE WHEN sd.IsAnomaly = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0)
        AS DECIMAL(5, 2)
    )                                                AS AnomalyRatePercentage,
    CASE
        WHEN CAST(
                100.0 * SUM(CASE WHEN sd.IsAnomaly = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0)
                AS DECIMAL(5, 2)
             ) > 8 THEN 'Unstable'
        WHEN CAST(
                100.0 * SUM(CASE WHEN sd.IsAnomaly = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0)
                AS DECIMAL(5, 2)
             ) > 3 THEN 'Watch'
        ELSE 'Stable'
    END AS ProcessStabilityStatus
FROM dbo.MachineSensorData AS sd
INNER JOIN dbo.Machines AS m ON m.MachineID = sd.MachineID
GROUP BY m.MachineID, m.MachineCode, m.MachineName
ORDER BY AnomalyRatePercentage DESC;
GO


----------------------------------------------------------------------------
-- Query 38
-- Rolling 3-Month Production Volume Forecast Baseline
----------------------------------------------------------------------------
/*
Business Question:
    Using a 3-month rolling average as a naive forecast baseline, how does
    each month's actual production volume compare to what the trailing
    trend would have predicted?

Business Value:
    Provides operations planning with a simple, transparent forecasting
    baseline to sanity-check more sophisticated forecasts against, and
    highlights months where actual output deviated sharply from the
    recent trend.
*/
WITH MonthlyActual AS (
    SELECT
        DATEFROMPARTS(YEAR(ScheduledStartDate), MONTH(ScheduledStartDate), 1) AS ProductionMonth,
        SUM(ActualQuantity)                                                    AS TotalActualQuantity
    FROM dbo.ProductionOrders
    GROUP BY DATEFROMPARTS(YEAR(ScheduledStartDate), MONTH(ScheduledStartDate), 1)
)
SELECT
    ProductionMonth,
    TotalActualQuantity,
    CAST(
        AVG(TotalActualQuantity) OVER (
            ORDER BY ProductionMonth
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS DECIMAL(12, 2)
    ) AS ThreeMonthRollingAvg,
    TotalActualQuantity - CAST(
        AVG(TotalActualQuantity) OVER (
            ORDER BY ProductionMonth
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS DECIMAL(12, 2)
    ) AS VarianceVsPriorThreeMonthAvg
FROM MonthlyActual
ORDER BY ProductionMonth;
GO


-- -----------------------------------------------------------------------------
-- PA-39: Mean Time Between Maintenance (MTBM) by Machine
-- -----------------------------------------------------------------------------
/*
Business Question:
    Which machines require maintenance most frequently?

Business Value:
    Calculates the average time between maintenance events for each machine.
    Lower MTBM values indicate machines that require more frequent servicing
    and may benefit from preventive maintenance or replacement.
*/

WITH MaintenanceIntervals AS
(
    SELECT
        MachineID,
        StartTime,
        LAG(StartTime) OVER
        (
            PARTITION BY MachineID
            ORDER BY StartTime
        ) AS PreviousMaintenanceTime
    FROM dbo.MaintenanceLogs
)
SELECT
    MachineID,
    COUNT(*) AS MaintenanceEvents,
    CAST(
        AVG(
            DATEDIFF(HOUR,
                     PreviousMaintenanceTime,
                     StartTime)
        ) AS DECIMAL(10,2)
    ) AS MeanTimeBetweenMaintenanceHours
FROM MaintenanceIntervals
WHERE PreviousMaintenanceTime IS NOT NULL
GROUP BY MachineID
ORDER BY MeanTimeBetweenMaintenanceHours ASC;
GO

-- -----------------------------------------------------------------------------
-- PA-40: Maintenance Cost Ranking by Machine
-- -----------------------------------------------------------------------------
/*
Business Question:
    Which machines incur the highest maintenance costs?

Business Value:
    Helps identify expensive equipment and supports maintenance budgeting and
    replacement planning.
*/

SELECT
    MachineID,
    COUNT(*) AS MaintenanceJobs,
    SUM(Cost) AS TotalMaintenanceCost,
    AVG(Cost) AS AverageMaintenanceCost,
    RANK() OVER
    (
        ORDER BY SUM(Cost) DESC
    ) AS CostRank
FROM dbo.MaintenanceLogs
GROUP BY MachineID
ORDER BY CostRank;
GO

-- -----------------------------------------------------------------------------
-- PA-41: Average Maintenance Duration by Machine
-- -----------------------------------------------------------------------------
/*
Business Question:
    Which machines spend the most time under maintenance?

Business Value:
    Measures average maintenance duration, helping identify machines with long
    repair cycles that reduce operational availability.
*/

SELECT
    MachineID,
    COUNT(*) AS MaintenanceJobs,
    AVG(
        DATEDIFF(
            MINUTE,
            StartTime,
            EndTime
        )
    ) AS AverageMaintenanceDurationMinutes,
    MAX(
        DATEDIFF(
            MINUTE,
            StartTime,
            EndTime
        )
    ) AS LongestMaintenanceDurationMinutes
FROM dbo.MaintenanceLogs
WHERE EndTime IS NOT NULL
GROUP BY MachineID
ORDER BY AverageMaintenanceDurationMinutes DESC;
GO


-- -----------------------------------------------------------------------------
-- PA-42: Daily Sensor Anomaly Trend
-- -----------------------------------------------------------------------------
/*
Business Question:
    How do sensor anomalies vary over time?

Business Value:
    Tracks the number and percentage of anomalous sensor readings each day,
    helping maintenance teams detect deteriorating machine conditions early.
*/

WITH DailySensorStats AS
(
    SELECT
        CAST(ReadingTimestamp AS DATE) AS ReadingDate,
        COUNT(*) AS TotalReadings,
        SUM(CASE WHEN IsAnomaly = 1 THEN 1 ELSE 0 END) AS TotalAnomalies
    FROM dbo.MachineSensorData
    GROUP BY CAST(ReadingTimestamp AS DATE)
)
SELECT
    ReadingDate,
    TotalReadings,
    TotalAnomalies,
    CAST(
        100.0 * TotalAnomalies /
        NULLIF(TotalReadings,0)
        AS DECIMAL(6,2)
    ) AS DailyAnomalyPercentage,
    LAG(TotalAnomalies)
        OVER (ORDER BY ReadingDate) AS PreviousDayAnomalies,
    LEAD(TotalAnomalies)
        OVER (ORDER BY ReadingDate) AS NextDayAnomalies
FROM DailySensorStats
ORDER BY ReadingDate;
GO


-- -----------------------------------------------------------------------------
-- PA-43: Machine Health Score
-- -----------------------------------------------------------------------------
/*
Business Question:
    Which machines appear healthiest based on their sensor readings?

Business Value:
    Produces a simple health score by combining average sensor readings and
    anomaly rates, helping prioritize inspection and preventive maintenance.
*/

WITH SensorSummary AS
(
    SELECT
        MachineID,
        AVG(Temperature) AS AvgTemperature,
        AVG(Vibration) AS AvgVibration,
        AVG(Pressure) AS AvgPressure,
        AVG(RPM) AS AvgRPM,
        AVG(PowerConsumptionKW) AS AvgPowerConsumptionKW,
        AVG(CASE WHEN IsAnomaly = 1 THEN 1.0 ELSE 0 END) AS AnomalyRate
    FROM dbo.MachineSensorData
    GROUP BY MachineID
)

SELECT
    MachineID,
    AvgTemperature,
    AvgVibration,
    AvgPressure,
    AvgRPM,
    AvgPowerConsumptionKW,
    CAST(AnomalyRate * 100 AS DECIMAL(6,2)) AS AnomalyPercentage,

    CAST
    (
        100
        -
        (
            (AnomalyRate * 60)
            + (AvgVibration / 2)
            + (AvgTemperature / 10)
        )
        AS DECIMAL(6,2)
    ) AS MachineHealthScore,

    DENSE_RANK() OVER
    (
        ORDER BY
        (
            100
            -
            (
                (AnomalyRate * 60)
                + (AvgVibration / 2)
                + (AvgTemperature / 10)
            )
        ) DESC
    ) AS HealthRank

FROM SensorSummary
ORDER BY HealthRank;
GO


-- -----------------------------------------------------------------------------
-- PA-44: Machine Performance Quartiles
-- -----------------------------------------------------------------------------
/*
Business Question:
    How are machines distributed into performance groups based on production?

Business Value:
    Classifies machines into quartiles according to total production output,
    helping management identify top and bottom performers.
*/

WITH MachinePerformance AS
(
    SELECT
        MachineID,
        SUM(UnitsProduced) AS TotalUnitsProduced,
        SUM(DowntimeMinutes) AS TotalDowntimeMinutes,
        AVG(UnitsProduced) AS AverageUnitsProduced
    FROM dbo.ProductionLogs
    GROUP BY MachineID
)

SELECT
    MachineID,
    TotalUnitsProduced,
    TotalDowntimeMinutes,
    AverageUnitsProduced,

    NTILE(4)
        OVER
        (
            ORDER BY TotalUnitsProduced DESC
        ) AS PerformanceQuartile,

    RANK()
        OVER
        (
            ORDER BY TotalUnitsProduced DESC
        ) AS OutputRank

FROM MachinePerformance
ORDER BY OutputRank;
GO

-- -----------------------------------------------------------------------------
-- PA-46: Daily Sensor Anomaly Percentage
-- -----------------------------------------------------------------------------
/*
Business Question:
    How frequently do sensor anomalies occur each day?

Business Value:
    Tracks operational health trends and highlights abnormal production days.
*/

WITH DailyAnomalies AS
(
    SELECT
        CAST(ReadingTimestamp AS DATE) AS ReadingDate,
        COUNT(*) AS TotalReadings,
        SUM(CASE WHEN IsAnomaly = 1 THEN 1 ELSE 0 END) AS TotalAnomalies
    FROM dbo.MachineSensorData
    GROUP BY CAST(ReadingTimestamp AS DATE)
)

SELECT
    ReadingDate,
    TotalReadings,
    TotalAnomalies,
    CAST
    (
        100.0 * TotalAnomalies /
        NULLIF(TotalReadings,0)
        AS DECIMAL(6,2)
    ) AS DailyAnomalyPercentage
FROM DailyAnomalies
ORDER BY ReadingDate;
GO
-- -----------------------------------------------------------------------------
-- PA-48: Machine Efficiency Ranking
-- -----------------------------------------------------------------------------
/*
Business Question:
    Which machines achieve the highest production efficiency based on
    production output and downtime?

Business Value:
    Helps production managers identify consistently efficient work centers
    and benchmark operational performance.
*/

WITH MachinePerformance AS
(
    SELECT
        MachineID,
        SUM(UnitsProduced) AS TotalUnitsProduced,
        SUM(DowntimeMinutes) AS TotalDowntimeMinutes
    FROM dbo.ProductionLogs
    GROUP BY MachineID
)

SELECT
    MachineID,
    TotalUnitsProduced,
    TotalDowntimeMinutes,

    CAST
    (
        TotalUnitsProduced /
        NULLIF(TotalDowntimeMinutes + 1,0)
        AS DECIMAL(12,2)
    ) AS EfficiencyScore,

    RANK() OVER
    (
        ORDER BY
        TotalUnitsProduced /
        NULLIF(TotalDowntimeMinutes + 1,0) DESC
    ) AS EfficiencyRank

FROM MachinePerformance
ORDER BY EfficiencyRank;
GO
-- -----------------------------------------------------------------------------
-- PA-49: Rolling 7-Day Machine Temperature
-- -----------------------------------------------------------------------------
/*
Business Question:
    How does average machine temperature trend over time?

Business Value:
    Detects gradual overheating patterns before equipment failures occur.
*/

WITH DailyTemperature AS
(
    SELECT
        MachineID,
        CAST(ReadingTimestamp AS DATE) AS ReadingDate,
        AVG(Temperature) AS AvgTemperature
    FROM dbo.MachineSensorData
    GROUP BY
        MachineID,
        CAST(ReadingTimestamp AS DATE)
)

SELECT
    MachineID,
    ReadingDate,
    CAST(AvgTemperature AS DECIMAL(10,2)) AS AvgTemperature,

    CAST
    (
        AVG(AvgTemperature)
        OVER
        (
            PARTITION BY MachineID
            ORDER BY ReadingDate
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        )
        AS DECIMAL(10,2)
    ) AS Rolling7DayTemperature

FROM DailyTemperature
ORDER BY
    MachineID,
    ReadingDate;
GO

-- -----------------------------------------------------------------------------
-- PA-50: Machine Risk Classification
-- -----------------------------------------------------------------------------
/*
Business Question:
    Which machines present the highest operational risk based on
    anomalies and downtime?

Business Value:
    Provides a simple operational risk score for maintenance planning and
    production scheduling.
*/

WITH MachineRisk AS
(
    SELECT
        pl.MachineID,
        SUM(pl.DowntimeMinutes) AS TotalDowntimeMinutes,
        SUM(CASE WHEN ms.IsAnomaly = 1 THEN 1 ELSE 0 END) AS TotalAnomalies
    FROM dbo.ProductionLogs pl
    LEFT JOIN dbo.MachineSensorData ms
        ON pl.MachineID = ms.MachineID
    GROUP BY
        pl.MachineID
)

SELECT
    MachineID,
    TotalDowntimeMinutes,
    TotalAnomalies,

    CASE
        WHEN TotalDowntimeMinutes > 5000
             OR TotalAnomalies > 500
        THEN 'High Risk'

        WHEN TotalDowntimeMinutes > 2500
             OR TotalAnomalies > 250
        THEN 'Medium Risk'

        ELSE 'Low Risk'
    END AS RiskCategory

FROM MachineRisk
ORDER BY
    TotalDowntimeMinutes DESC,
    TotalAnomalies DESC;
GO


-- =============================================================================
-- PA-51: Inventory Reorder Priority Ranking
-- =============================================================================
/*
Business Question:
    Which inventory items are most urgently in need of replenishment?

Business Value:
    Helps inventory planners prioritize procurement by identifying items
    that are below or close to their reorder levels.
*/

SELECT
    ItemID,
    ItemCode,
    ItemName,
    ItemCategory,
    QuantityOnHand,
    ReorderLevel,
    (ReorderLevel - QuantityOnHand) AS QuantityShortage,

    CASE
        WHEN QuantityOnHand <= 0 THEN 'Critical'
        WHEN QuantityOnHand < ReorderLevel THEN 'Reorder Immediately'
        WHEN QuantityOnHand <= ReorderLevel * 1.20 THEN 'Monitor'
        ELSE 'Healthy'
    END AS InventoryStatus,

    DENSE_RANK() OVER
    (
        ORDER BY (ReorderLevel - QuantityOnHand) DESC
    ) AS ReorderPriorityRank

FROM dbo.InventoryItems

ORDER BY
    ReorderPriorityRank;
GO


-- =============================================================================
-- PA-52: Inventory Value by Category
-- =============================================================================
/*
Business Question:
    Which inventory categories hold the highest inventory value?

Business Value:
    Identifies where working capital is concentrated across inventory.
*/

SELECT

    ItemCategory,

    COUNT(*) AS TotalItems,

    SUM(QuantityOnHand) AS TotalUnits,

    CAST
    (
        SUM(QuantityOnHand * UnitCost)
        AS DECIMAL(18,2)
    ) AS InventoryValue,

    RANK() OVER
    (
        ORDER BY
        SUM(QuantityOnHand * UnitCost) DESC
    ) AS ValueRank

FROM dbo.InventoryItems

GROUP BY
    ItemCategory

ORDER BY
    ValueRank;
GO


-- =============================================================================
-- PA-53: Warehouse Inventory Distribution
-- =============================================================================
/*
Business Question:
    How is inventory distributed across warehouse locations?

Business Value:
    Helps warehouse managers understand storage utilization and inventory
    allocation.
*/

SELECT

    WarehouseLocation,

    COUNT(*) AS NumberOfItems,

    SUM(QuantityOnHand) AS TotalUnitsStored,

    CAST
    (
        AVG(UnitCost)
        AS DECIMAL(10,2)
    ) AS AverageUnitCost,

    CAST
    (
        SUM(UnitCost * QuantityOnHand)
        AS DECIMAL(18,2)
    ) AS WarehouseInventoryValue

FROM dbo.InventoryItems

GROUP BY
    WarehouseLocation

ORDER BY
    WarehouseInventoryValue DESC;
GO


-- =============================================================================
-- PA-54: Top Inventory Items by Stock Value
-- =============================================================================
/*
Business Question:
    Which inventory items represent the highest monetary value?

Business Value:
    Identifies high-value inventory that requires tighter inventory control.
*/

SELECT TOP (20)

    ItemID,
    ItemCode,
    ItemName,
    ItemCategory,
    QuantityOnHand,
    UnitCost,

    CAST
    (
        QuantityOnHand * UnitCost
        AS DECIMAL(18,2)
    ) AS TotalInventoryValue,

    RANK() OVER
    (
        ORDER BY
        QuantityOnHand * UnitCost DESC
    ) AS InventoryValueRank

FROM dbo.InventoryItems

ORDER BY
    InventoryValueRank;
GO


-- =============================================================================
-- PA-55: Supplier Inventory Contribution
-- =============================================================================
/*
Business Question:
    Which suppliers contribute the highest inventory value?

Business Value:
    Measures supplier dependency and procurement concentration.
*/

WITH SupplierInventory AS
(
    SELECT

        s.SupplierID,
        s.SupplierName,

        COUNT(i.ItemID) AS TotalItems,

        SUM(i.QuantityOnHand) AS TotalUnits,

        SUM(i.QuantityOnHand * i.UnitCost) AS InventoryValue

    FROM dbo.Suppliers s

    INNER JOIN dbo.InventoryItems i
        ON s.SupplierID = i.PrimarySupplierID

    GROUP BY

        s.SupplierID,
        s.SupplierName
)

SELECT

    SupplierID,
    SupplierName,
    TotalItems,
    TotalUnits,

    CAST
    (
        InventoryValue
        AS DECIMAL(18,2)
    ) AS InventoryValue,

    DENSE_RANK() OVER
    (
        ORDER BY InventoryValue DESC
    ) AS SupplierRank

FROM SupplierInventory

ORDER BY
    SupplierRank;
GO

-- =============================================================================
-- PA-56: Supplier Purchase Spend Ranking
-- =============================================================================
/*
Business Question:
    Which suppliers account for the highest procurement spend?

Business Value:
    Identifies key suppliers by purchasing value and supports supplier
    relationship management.
*/

WITH SupplierSpend AS
(
    SELECT
        s.SupplierID,
        s.SupplierName,
        COUNT(po.PurchaseOrderID) AS TotalPurchaseOrders,
        SUM(po.TotalAmount) AS TotalSpend
    FROM dbo.Suppliers s
    INNER JOIN dbo.PurchaseOrders po
        ON s.SupplierID = po.SupplierID
    GROUP BY
        s.SupplierID,
        s.SupplierName
)

SELECT
    SupplierID,
    SupplierName,
    TotalPurchaseOrders,
    CAST(TotalSpend AS DECIMAL(18,2)) AS TotalSpend,
    DENSE_RANK() OVER
    (
        ORDER BY TotalSpend DESC
    ) AS SpendRank
FROM SupplierSpend
ORDER BY SpendRank;
GO


-- =============================================================================
-- PA-57: Supplier Order Frequency
-- =============================================================================
/*
Business Question:
    Which suppliers receive purchase orders most frequently?

Business Value:
    Highlights heavily utilized suppliers and purchasing concentration.
*/

SELECT
    s.SupplierID,
    s.SupplierName,
    COUNT(po.PurchaseOrderID) AS PurchaseOrderCount,

    DENSE_RANK() OVER
    (
        ORDER BY COUNT(po.PurchaseOrderID) DESC
    ) AS FrequencyRank

FROM dbo.Suppliers s

LEFT JOIN dbo.PurchaseOrders po
ON s.SupplierID = po.SupplierID

GROUP BY
    s.SupplierID,
    s.SupplierName

ORDER BY
    FrequencyRank;
GO


-- =============================================================================
-- PA-58: Monthly Procurement Spend Trend
-- =============================================================================
/*
Business Question:
    How does procurement spending change month over month?

Business Value:
    Helps procurement managers identify seasonal purchasing patterns.
*/

WITH MonthlySpend AS
(
    SELECT
        DATEFROMPARTS(YEAR(OrderDate),MONTH(OrderDate),1) AS PurchaseMonth,
        SUM(TotalAmount) AS MonthlySpend
    FROM dbo.PurchaseOrders
    GROUP BY
        DATEFROMPARTS(YEAR(OrderDate),MONTH(OrderDate),1)
)

SELECT

    PurchaseMonth,

    CAST(MonthlySpend AS DECIMAL(18,2)) AS MonthlySpend,

    CAST
    (
        LAG(MonthlySpend)
        OVER
        (
            ORDER BY PurchaseMonth
        )
        AS DECIMAL(18,2)
    ) AS PreviousMonthSpend,

    CAST
    (
        MonthlySpend
        -
        LAG(MonthlySpend)
        OVER
        (
            ORDER BY PurchaseMonth
        )
        AS DECIMAL(18,2)
    ) AS SpendDifference

FROM MonthlySpend

ORDER BY
    PurchaseMonth;
GO


-- =============================================================================
-- PA-59: Supplier Quality Rating Analysis
-- =============================================================================
/*
Business Question:
    Which suppliers have the highest quality ratings?

Business Value:
    Supports supplier selection and procurement decisions.
*/

SELECT

    SupplierID,
    SupplierCode,
    SupplierName,
    Country,
    QualityRating,

    DENSE_RANK() OVER
    (
        ORDER BY QualityRating DESC
    ) AS QualityRank

FROM dbo.Suppliers

WHERE IsActive = 1

ORDER BY
    QualityRank,
    SupplierName;
GO


-- =============================================================================
-- PA-60: Purchase Order Fulfillment Percentage
-- =============================================================================
/*
Business Question:
    How completely are purchase orders being fulfilled?

Business Value:
    Measures supplier fulfillment performance by comparing quantities
    ordered versus quantities received.
*/

WITH Fulfillment AS
(
    SELECT

        pol.PurchaseOrderID,

        SUM(pol.QuantityOrdered) AS TotalOrdered,

        SUM(pol.QuantityReceived) AS TotalReceived

    FROM dbo.PurchaseOrderLines pol

    GROUP BY
        pol.PurchaseOrderID
)

SELECT

    PurchaseOrderID,

    TotalOrdered,

    TotalReceived,

    CAST
    (
        100.0 * TotalReceived /
        NULLIF(TotalOrdered,0)
        AS DECIMAL(6,2)
    ) AS FulfillmentPercentage,

    CASE

        WHEN TotalReceived = TotalOrdered
            THEN 'Complete'

        WHEN TotalReceived >= TotalOrdered * 0.90
            THEN 'Nearly Complete'

        WHEN TotalReceived >= TotalOrdered * 0.50
            THEN 'Partial'

        ELSE 'Low Fulfillment'

    END AS FulfillmentStatus

FROM Fulfillment

ORDER BY
    FulfillmentPercentage DESC;
GO
-- =============================================================================
-- PA-61: Purchase Order Status Distribution
-- =============================================================================
/*
Business Question:
    What is the distribution of purchase orders by status?

Business Value:
    Gives procurement managers visibility into procurement pipeline health.
*/

SELECT
    Status,
    COUNT(*) AS PurchaseOrderCount,
    CAST(
        100.0 * COUNT(*) /
        SUM(COUNT(*)) OVER ()
        AS DECIMAL(6,2)
    ) AS PercentageOfOrders
FROM dbo.PurchaseOrders
GROUP BY Status
ORDER BY PurchaseOrderCount DESC;
GO


-- =============================================================================
-- PA-62: Monthly Purchase Order Volume
-- =============================================================================
/*
Business Question:
    How many purchase orders are created each month?

Business Value:
    Identifies procurement workload trends over time.
*/

SELECT

    DATEFROMPARTS(
        YEAR(OrderDate),
        MONTH(OrderDate),
        1
    ) AS PurchaseMonth,

    COUNT(*) AS PurchaseOrderCount,

    SUM(TotalAmount) AS TotalSpend,

    AVG(TotalAmount) AS AverageOrderValue

FROM dbo.PurchaseOrders

GROUP BY
    DATEFROMPARTS(
        YEAR(OrderDate),
        MONTH(OrderDate),
        1
    )

ORDER BY PurchaseMonth;
GO


-- =============================================================================
-- PA-63: Supplier Concentration Analysis
-- =============================================================================
/*
Business Question:
    Which suppliers provide the largest variety of inventory items?

Business Value:
    Measures dependency on suppliers and helps identify diversification
    opportunities.
*/

SELECT

    s.SupplierID,
    s.SupplierName,

    COUNT(i.ItemID) AS NumberOfItems,

    SUM(i.QuantityOnHand) AS TotalUnits,

    CAST(
        SUM(i.QuantityOnHand * i.UnitCost)
        AS DECIMAL(18,2)
    ) AS InventoryValue,

    DENSE_RANK() OVER
    (
        ORDER BY COUNT(i.ItemID) DESC
    ) AS SupplierConcentrationRank

FROM dbo.Suppliers s

INNER JOIN dbo.InventoryItems i
ON s.SupplierID = i.PrimarySupplierID

GROUP BY

    s.SupplierID,
    s.SupplierName

ORDER BY SupplierConcentrationRank;
GO


-- =============================================================================
-- PA-64: Procurement Cost Quartiles
-- =============================================================================
/*
Business Question:
    How are purchase orders distributed by spending level?

Business Value:
    Segments procurement spending into quartiles for executive reporting.
*/

SELECT

    PurchaseOrderID,

    PONumber,

    SupplierID,

    TotalAmount,

    NTILE(4) OVER
    (
        ORDER BY TotalAmount DESC
    ) AS SpendQuartile

FROM dbo.PurchaseOrders

ORDER BY
    TotalAmount DESC;
GO


-- =============================================================================
-- PA-65: Procurement Executive Dashboard
-- =============================================================================
/*
Business Question:
    What are the overall procurement KPIs?

Business Value:
    Provides executives with a high-level procurement performance snapshot.
*/

SELECT

    COUNT(*) AS TotalPurchaseOrders,

    COUNT(DISTINCT SupplierID) AS ActiveSuppliers,

    CAST(
        SUM(TotalAmount)
        AS DECIMAL(18,2)
    ) AS TotalProcurementSpend,

    CAST(
        AVG(TotalAmount)
        AS DECIMAL(18,2)
    ) AS AveragePurchaseOrderValue,

    MIN(OrderDate) AS EarliestOrder,

    MAX(OrderDate) AS LatestOrder

FROM dbo.PurchaseOrders;
GO

-- =============================================================================
-- PA-66: Top Customers by Shipped Quantity
-- =============================================================================
/*
Business Question:
    Which customers receive the highest shipment volumes?

Business Value:
    Identifies the organization's most valuable customers based on shipped
    product quantity.
*/

WITH CustomerShipments AS
(
    SELECT
        c.CustomerID,
        c.CustomerName,
        SUM(s.ShippedQuantity) AS TotalShippedQuantity,
        COUNT(s.ShipmentID) AS TotalShipments
    FROM dbo.Customers c
    INNER JOIN dbo.Shipments s
        ON c.CustomerID = s.CustomerID
    GROUP BY
        c.CustomerID,
        c.CustomerName
)

SELECT
    CustomerID,
    CustomerName,
    TotalShippedQuantity,
    TotalShipments,
    DENSE_RANK() OVER
    (
        ORDER BY TotalShippedQuantity DESC
    ) AS CustomerRank
FROM CustomerShipments
ORDER BY CustomerRank;
GO


-- =============================================================================
-- PA-67: Monthly Shipment Trend
-- =============================================================================
/*
Business Question:
    How do shipment quantities change month over month?

Business Value:
    Helps logistics teams understand shipment demand trends.
*/

WITH MonthlyShipments AS
(
    SELECT
        DATEFROMPARTS
        (
            YEAR(ShipmentDate),
            MONTH(ShipmentDate),
            1
        ) AS ShipmentMonth,

        SUM(ShippedQuantity) AS TotalQuantity
    FROM dbo.Shipments
    GROUP BY
        DATEFROMPARTS
        (
            YEAR(ShipmentDate),
            MONTH(ShipmentDate),
            1
        )
)

SELECT

    ShipmentMonth,

    TotalQuantity,

    LAG(TotalQuantity)
    OVER
    (
        ORDER BY ShipmentMonth
    ) AS PreviousMonth,

    TotalQuantity
    -
    LAG(TotalQuantity)
    OVER
    (
        ORDER BY ShipmentMonth
    ) AS MonthlyDifference

FROM MonthlyShipments

ORDER BY ShipmentMonth;
GO


-- =============================================================================
-- PA-68: Carrier Performance Ranking
-- =============================================================================
/*
Business Question:
    Which shipping carriers transport the largest shipment volume?

Business Value:
    Supports logistics optimization and carrier evaluation.
*/

SELECT

    Carrier,

    COUNT(*) AS TotalShipments,

    SUM(ShippedQuantity) AS TotalQuantity,

    AVG(ShippedQuantity) AS AverageShipmentQuantity,

    DENSE_RANK()
    OVER
    (
        ORDER BY SUM(ShippedQuantity) DESC
    ) AS CarrierRank

FROM dbo.Shipments

GROUP BY Carrier

ORDER BY CarrierRank;
GO


-- =============================================================================
-- PA-69: Customer Demand Trend
-- =============================================================================
/*
Business Question:
    How does customer demand change over time?

Business Value:
    Tracks customer purchasing behavior and identifies growing demand.
*/

WITH CustomerDemand AS
(
    SELECT

        CustomerID,

        DATEFROMPARTS
        (
            YEAR(ScheduledStartDate),
            MONTH(ScheduledStartDate),
            1
        ) AS DemandMonth,

        SUM(ActualQuantity) AS MonthlyDemand

    FROM dbo.ProductionOrders

    GROUP BY

        CustomerID,

        DATEFROMPARTS
        (
            YEAR(ScheduledStartDate),
            MONTH(ScheduledStartDate),
            1
        )
)

SELECT

    CustomerID,

    DemandMonth,

    MonthlyDemand,

    LAG(MonthlyDemand)
    OVER
    (
        PARTITION BY CustomerID
        ORDER BY DemandMonth
    ) AS PreviousMonthDemand,

    LEAD(MonthlyDemand)
    OVER
    (
        PARTITION BY CustomerID
        ORDER BY DemandMonth
    ) AS NextMonthDemand

FROM CustomerDemand

ORDER BY
    CustomerID,
    DemandMonth;
GO


-- =============================================================================
-- PA-70: Customer Shipment Frequency
-- =============================================================================
/*
Business Question:
    Which customers receive shipments most frequently?

Business Value:
    Helps identify high-frequency customers for service prioritization.
*/

SELECT

    c.CustomerID,

    c.CustomerName,

    COUNT(s.ShipmentID) AS ShipmentCount,

    SUM(s.ShippedQuantity) AS TotalQuantity,

    DENSE_RANK()
    OVER
    (
        ORDER BY COUNT(s.ShipmentID) DESC
    ) AS FrequencyRank

FROM dbo.Customers c

LEFT JOIN dbo.Shipments s

ON c.CustomerID = s.CustomerID

GROUP BY

    c.CustomerID,
    c.CustomerName

ORDER BY FrequencyRank;
GO






-- =============================================================================
-- PA-71: Top Customers by Production Demand
-- =============================================================================
/*
Business Question:
    Which customers generate the highest production demand?

Business Value:
    Helps production planners identify the organization's largest customers
    based on actual production quantities.
*/

WITH CustomerProduction AS
(
    SELECT
        c.CustomerID,
        c.CustomerName,
        SUM(po.ActualQuantity) AS TotalProduction,
        COUNT(po.ProductionOrderID) AS TotalOrders
    FROM dbo.Customers c
    INNER JOIN dbo.ProductionOrders po
        ON c.CustomerID = po.CustomerID
    GROUP BY
        c.CustomerID,
        c.CustomerName
)

SELECT
    CustomerID,
    CustomerName,
    TotalProduction,
    TotalOrders,
    DENSE_RANK() OVER
    (
        ORDER BY TotalProduction DESC
    ) AS ProductionRank
FROM CustomerProduction
ORDER BY ProductionRank;
GO


-- =============================================================================
-- PA-72: Shipment Quantity by Destination Country
-- =============================================================================
/*
Business Question:
    Which customer countries receive the highest shipment quantities?

Business Value:
    Provides geographical insight into shipment distribution.
*/

SELECT
    c.Country,
    COUNT(s.ShipmentID) AS TotalShipments,
    SUM(s.ShippedQuantity) AS TotalQuantity,

    DENSE_RANK() OVER
    (
        ORDER BY SUM(s.ShippedQuantity) DESC
    ) AS CountryRank

FROM dbo.Customers c
INNER JOIN dbo.Shipments s
    ON c.CustomerID = s.CustomerID

GROUP BY
    c.Country

ORDER BY CountryRank;
GO


-- =============================================================================
-- PA-73: Monthly Customer Growth
-- =============================================================================
/*
Business Question:
    How many new customers were added each month?

Business Value:
    Tracks customer acquisition trends over time.
*/

WITH MonthlyCustomers AS
(
    SELECT
        DATEFROMPARTS
        (
            YEAR(CreatedAt),
            MONTH(CreatedAt),
            1
        ) AS CreatedMonth,

        COUNT(*) AS NewCustomers

    FROM dbo.Customers

    GROUP BY
        DATEFROMPARTS
        (
            YEAR(CreatedAt),
            MONTH(CreatedAt),
            1
        )
)

SELECT

    CreatedMonth,

    NewCustomers,

    SUM(NewCustomers)
    OVER
    (
        ORDER BY CreatedMonth
        ROWS UNBOUNDED PRECEDING
    ) AS CumulativeCustomers

FROM MonthlyCustomers

ORDER BY CreatedMonth;
GO


-- =============================================================================
-- PA-74: Customer Order Completion Rate
-- =============================================================================
/*
Business Question:
    Which customers have the highest percentage of completed production
    orders?

Business Value:
    Measures customer fulfillment performance.
*/

WITH CustomerOrders AS
(
    SELECT
        CustomerID,

        COUNT(*) AS TotalOrders,

        SUM
        (
            CASE
                WHEN Status='Completed'
                THEN 1
                ELSE 0
            END
        ) AS CompletedOrders

    FROM dbo.ProductionOrders

    GROUP BY CustomerID
)

SELECT

    c.CustomerID,

    c.CustomerName,

    TotalOrders,

    CompletedOrders,

    CAST
    (
        100.0*CompletedOrders/
        NULLIF(TotalOrders,0)
        AS DECIMAL(6,2)
    ) AS CompletionRate

FROM CustomerOrders co

INNER JOIN dbo.Customers c

ON co.CustomerID=c.CustomerID

ORDER BY CompletionRate DESC;
GO


-- =============================================================================
-- PA-75: Customer Shipment Timeline
-- =============================================================================
/*
Business Question:
    What is the shipment sequence for each customer?

Business Value:
    Shows shipment history and customer shipment frequency using window
    functions.
*/

SELECT

    CustomerID,

    ShipmentID,

    ShipmentDate,

    ShippedQuantity,

    ROW_NUMBER()
    OVER
    (
        PARTITION BY CustomerID
        ORDER BY ShipmentDate
    ) AS ShipmentSequence,

    LAG(ShipmentDate)
    OVER
    (
        PARTITION BY CustomerID
        ORDER BY ShipmentDate
    ) AS PreviousShipmentDate

FROM dbo.Shipments

ORDER BY
    CustomerID,
    ShipmentSequence;
GO


-- =============================================================================
-- PA-76: Customer Shipment Lead Time Analysis
-- =============================================================================
/*
Business Question:
    How long does shipment delivery take for each customer?

Business Value:
    Measures logistics responsiveness and identifies customers experiencing
    longer delivery times.
*/

SELECT

    c.CustomerID,
    c.CustomerName,

    COUNT(s.ShipmentID) AS TotalShipments,

    CAST
    (
        AVG(DATEDIFF(DAY,
            s.ShipmentDate,
            s.ActualArrivalDate))
        AS DECIMAL(10,2)
    ) AS AverageDeliveryDays,

    MIN(DATEDIFF(DAY,s.ShipmentDate,s.ActualArrivalDate))
        AS FastestDelivery,

    MAX(DATEDIFF(DAY,s.ShipmentDate,s.ActualArrivalDate))
        AS SlowestDelivery

FROM dbo.Customers c

INNER JOIN dbo.Shipments s
ON c.CustomerID=s.CustomerID

WHERE s.ActualArrivalDate IS NOT NULL

GROUP BY
    c.CustomerID,
    c.CustomerName

ORDER BY AverageDeliveryDays;
GO
-- =============================================================================
-- PA-77: Customer Demand Quartiles
-- =============================================================================
/*
Business Question:
    How can customers be segmented according to production demand?

Business Value:
    Groups customers into demand tiers for production planning and account
    management.
*/

WITH CustomerDemand AS
(
    SELECT

        CustomerID,

        SUM(ActualQuantity) AS TotalDemand

    FROM dbo.ProductionOrders

    GROUP BY CustomerID
)

SELECT

    c.CustomerID,

    c.CustomerName,

    cd.TotalDemand,

    NTILE(4)
    OVER
    (
        ORDER BY cd.TotalDemand DESC
    ) AS DemandQuartile

FROM CustomerDemand cd

INNER JOIN dbo.Customers c

ON cd.CustomerID=c.CustomerID

ORDER BY
    DemandQuartile,
    TotalDemand DESC;
GO
-- =============================================================================
-- PA-78: Shipment Carrier Delivery Performance
-- =============================================================================
/*
Business Question:
    Which carriers provide the fastest deliveries?

Business Value:
    Helps logistics teams benchmark carrier performance.
*/

SELECT

    Carrier,

    COUNT(*) AS TotalShipments,

    CAST
    (
        AVG
        (
            DATEDIFF
            (
                DAY,
                ShipmentDate,
                ActualArrivalDate
            )
        )
        AS DECIMAL(10,2)
    ) AS AverageDeliveryDays,

    DENSE_RANK()
    OVER
    (
        ORDER BY
        AVG
        (
            DATEDIFF
            (
                DAY,
                ShipmentDate,
                ActualArrivalDate
            )
        )
    ) AS CarrierPerformanceRank

FROM dbo.Shipments

WHERE ActualArrivalDate IS NOT NULL

GROUP BY Carrier

ORDER BY CarrierPerformanceRank;
GO
-- =============================================================================
-- PA-79: Production Order Priority Distribution
-- =============================================================================
/*
Business Question:
    How are production orders distributed across priorities?

Business Value:
    Gives planners visibility into workload by production priority.
*/

SELECT

    Priority,

    COUNT(*) AS TotalOrders,

    SUM(ActualQuantity) AS TotalActualQuantity,

    AVG(ActualQuantity) AS AverageActualQuantity,

    CAST
    (
        100.0*COUNT(*)/
        SUM(COUNT(*)) OVER()
        AS DECIMAL(6,2)
    ) AS PercentageOfOrders

FROM dbo.ProductionOrders

GROUP BY Priority

ORDER BY
    TotalOrders DESC;
GO
-- =============================================================================
-- PA-80: Customer Executive Dashboard
-- =============================================================================
/*
Business Question:
    What are the key customer and shipment KPIs?

Business Value:
    Provides executives with a consolidated customer performance dashboard.
*/

SELECT

    COUNT(DISTINCT CustomerID) AS TotalCustomers,

    COUNT(*) AS TotalShipments,

    CAST
    (
        SUM(ShippedQuantity)
        AS DECIMAL(18,2)
    ) AS TotalShippedQuantity,

    CAST
    (
        AVG(ShippedQuantity)
        AS DECIMAL(18,2)
    ) AS AverageShipmentQuantity,

    MIN(ShipmentDate) AS FirstShipment,

    MAX(ShipmentDate) AS LatestShipment

FROM dbo.Shipments;
GO