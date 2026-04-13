# 06 - SQL SERVER DEEP DIVE

**Complete guide to SQL Server provider: configuration, schema, performance tuning, monitoring, backup, and on-premises deployment.**

---

## Table of Contents

1. [SQL Server Provider Configuration](#sql-server-provider-configuration)
2. [Database Schema](#database-schema)
3. [Connection String Optimization](#connection-string-optimization)
4. [Performance Tuning](#performance-tuning)
5. [Monitoring and Diagnostics](#monitoring-and-diagnostics)
6. [History Management and Archival](#history-management-and-archival)
7. [Backup and Recovery](#backup-and-recovery)
8. [On-Premises Deployment Patterns](#on-premises-deployment-patterns)
9. [Troubleshooting Guide](#troubleshooting-guide)
10. [Production Checklist](#production-checklist)

---

## SQL Server Provider Configuration

### Basic Configuration

```csharp
using DurableTask.SqlServer;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;

namespace SqlServerConfig;

/// <summary>
/// Complete SQL Server provider configuration for production.
/// </summary>
public sealed class SqlServerOrchestrationServiceFactory
{
    public static SqlOrchestrationService CreateService(
        string connectionString,
        string? schemaName = null,
        string? taskHubName = null)
    {
        var settings = new SqlOrchestrationServiceSettings
        {
            // Schema configuration
            SchemaName = schemaName ?? "dt",
            TaskHubName = taskHubName ?? "DefaultHub",
            
            // Lock timeout settings
            TaskOrchestrationLockTimeout = TimeSpan.FromMinutes(10),
            TaskActivityLockTimeout = TimeSpan.FromMinutes(10),
            
            // Work item settings
            WorkItemLockTimeout = TimeSpan.FromMinutes(1),
            WorkItemBatchSize = 50,
            
            // Fetch settings
            MaxActiveOrchestrations = 100,
            MaxActiveActivities = 200,
            
            // Checkpointing
            WorkItemQueuePollingInterval = TimeSpan.FromSeconds(5),
            
            // Performance
            FetchNewOrchestrationMessagesFirst = true,
            UseSeparateQueueForNewTasks = true
        };

        return new SqlOrchestrationService(settings);
    }

    public static SqlOrchestrationService CreateHighThroughputService(
        string connectionString)
    {
        var settings = new SqlOrchestrationServiceSettings
        {
            SchemaName = "dt",
            TaskHubName = "HighThroughputHub",
            
            // Aggressive settings for high throughput
            TaskOrchestrationLockTimeout = TimeSpan.FromMinutes(5),
            TaskActivityLockTimeout = TimeSpan.FromMinutes(5),
            
            WorkItemLockTimeout = TimeSpan.FromSeconds(30),
            WorkItemBatchSize = 100, // Fetch more work items at once
            
            MaxActiveOrchestrations = 500,
            MaxActiveActivities = 1000,
            
            WorkItemQueuePollingInterval = TimeSpan.FromSeconds(1), // Poll more frequently
            
            FetchNewOrchestrationMessagesFirst = true,
            UseSeparateQueueForNewTasks = true
        };

        return new SqlOrchestrationService(settings);
    }

    public static SqlOrchestrationService CreateLowLatencyService(
        string connectionString)
    {
        var settings = new SqlOrchestrationServiceSettings
        {
            SchemaName = "dt",
            TaskHubName = "LowLatencyHub",
            
            // Low latency settings
            TaskOrchestrationLockTimeout = TimeSpan.FromMinutes(2),
            TaskActivityLockTimeout = TimeSpan.FromMinutes(2),
            
            WorkItemLockTimeout = TimeSpan.FromSeconds(10),
            WorkItemBatchSize = 20, // Smaller batches for faster processing
            
            MaxActiveOrchestrations = 50,
            MaxActiveActivities = 100,
            
            WorkItemQueuePollingInterval = TimeSpan.FromMilliseconds(500), // Poll very frequently
            
            FetchNewOrchestrationMessagesFirst = true,
            UseSeparateQueueForNewTasks = true
        };

        return new SqlOrchestrationService(settings);
    }
}
```

### Advanced Configuration Options

```csharp
using DurableTask.SqlServer;

namespace SqlServerConfig;

/// <summary>
/// Advanced configuration scenarios.
/// </summary>
public static class AdvancedConfiguration
{
    /// <summary>
    /// Multi-tenant configuration with separate task hubs per tenant.
    /// </summary>
    public static SqlOrchestrationService CreateTenantService(
        string connectionString,
        string tenantId)
    {
        var settings = new SqlOrchestrationServiceSettings
        {
            SchemaName = "dt",
            TaskHubName = $"Tenant_{tenantId}",
            
            TaskOrchestrationLockTimeout = TimeSpan.FromMinutes(10),
            TaskActivityLockTimeout = TimeSpan.FromMinutes(10),
            
            WorkItemBatchSize = 50,
            MaxActiveOrchestrations = 100,
            MaxActiveActivities = 200
        };

        return new SqlOrchestrationService(settings);
    }

    /// <summary>
    /// Separate service for long-running workflows.
    /// </summary>
    public static SqlOrchestrationService CreateLongRunningService(
        string connectionString)
    {
        var settings = new SqlOrchestrationServiceSettings
        {
            SchemaName = "dt",
            TaskHubName = "LongRunningHub",
            
            // Extended timeouts for long-running workflows
            TaskOrchestrationLockTimeout = TimeSpan.FromHours(1),
            TaskActivityLockTimeout = TimeSpan.FromHours(1),
            
            WorkItemLockTimeout = TimeSpan.FromMinutes(10),
            
            // Conservative settings to avoid resource exhaustion
            WorkItemBatchSize = 10,
            MaxActiveOrchestrations = 10,
            MaxActiveActivities = 20,
            
            WorkItemQueuePollingInterval = TimeSpan.FromSeconds(30)
        };

        return new SqlOrchestrationService(settings);
    }
}
```

---

## Database Schema

### Core Tables Overview

The SQL Server provider creates these tables:

```sql
-- Schema: dt (configurable)

-- Orchestration state (active orchestrations)
dt.OrchestrationState
-- Columns: InstanceId, ExecutionId, Name, Version, Status, Input, Output, 
--          CreatedTime, CompletedTime, LastUpdatedTime, CustomStatus, Tags

-- Orchestration history (event sourcing)
dt.OrchestrationStateHistory
-- Columns: InstanceId, ExecutionId, SequenceNumber, EventType, Name, Input, 
--          Result, Details, Timestamp

-- Work items queue (pending work)
dt.WorkItem
-- Columns: WorkItemId, InstanceId, ExecutionId, Type, Name, Input, 
--          LockedUntil, DequeueCount, CreatedTime

-- New events queue (external events and messages)
dt.NewEvents
-- Columns: EventId, InstanceId, ExecutionId, EventType, Name, Input, Timestamp

-- Instances metadata
dt.Instances
-- Columns: InstanceId, ExecutionId, Name, Version, Status, CreatedTime, 
--          CompletedTime, LastUpdatedTime
```

### Schema Creation Script

```sql
-- 01-CREATE-SCHEMA.sql
-- Run this script to manually create the DurableTask schema

-- Create schema if not exists
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'dt')
BEGIN
    EXEC('CREATE SCHEMA dt');
END
GO

-- OrchestrationState table
CREATE TABLE dt.OrchestrationState
(
    [InstanceId] NVARCHAR(256) NOT NULL,
    [ExecutionId] NVARCHAR(256) NOT NULL,
    [Name] NVARCHAR(256) NOT NULL,
    [Version] NVARCHAR(100) NULL,
    [Status] NVARCHAR(50) NOT NULL,
    [Input] NVARCHAR(MAX) NULL,
    [Output] NVARCHAR(MAX) NULL,
    [CreatedTime] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    [CompletedTime] DATETIME2 NULL,
    [LastUpdatedTime] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    [CustomStatus] NVARCHAR(MAX) NULL,
    [Tags] NVARCHAR(MAX) NULL,
    
    CONSTRAINT PK_OrchestrationState PRIMARY KEY CLUSTERED ([InstanceId], [ExecutionId])
);

-- Indexes for OrchestrationState
CREATE NONCLUSTERED INDEX IX_OrchestrationState_Status_CreatedTime
    ON dt.OrchestrationState ([Status], [CreatedTime])
    INCLUDE ([Name], [LastUpdatedTime]);

CREATE NONCLUSTERED INDEX IX_OrchestrationState_Name_Status
    ON dt.OrchestrationState ([Name], [Status])
    INCLUDE ([InstanceId], [CreatedTime]);

CREATE NONCLUSTERED INDEX IX_OrchestrationState_CreatedTime
    ON dt.OrchestrationState ([CreatedTime] DESC)
    INCLUDE ([Status], [Name]);

-- OrchestrationStateHistory table
CREATE TABLE dt.OrchestrationStateHistory
(
    [HistoryId] BIGINT IDENTITY(1,1) NOT NULL,
    [InstanceId] NVARCHAR(256) NOT NULL,
    [ExecutionId] NVARCHAR(256) NOT NULL,
    [SequenceNumber] INT NOT NULL,
    [EventType] NVARCHAR(100) NOT NULL,
    [Name] NVARCHAR(256) NULL,
    [Input] NVARCHAR(MAX) NULL,
    [Result] NVARCHAR(MAX) NULL,
    [Details] NVARCHAR(MAX) NULL,
    [Timestamp] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    
    CONSTRAINT PK_OrchestrationStateHistory PRIMARY KEY CLUSTERED ([HistoryId])
);

-- Indexes for OrchestrationStateHistory
CREATE NONCLUSTERED INDEX IX_OrchestrationStateHistory_InstanceId_ExecutionId_Sequence
    ON dt.OrchestrationStateHistory ([InstanceId], [ExecutionId], [SequenceNumber]);

CREATE NONCLUSTERED INDEX IX_OrchestrationStateHistory_Timestamp
    ON dt.OrchestrationStateHistory ([Timestamp] DESC);

-- WorkItem table
CREATE TABLE dt.WorkItem
(
    [WorkItemId] BIGINT IDENTITY(1,1) NOT NULL,
    [InstanceId] NVARCHAR(256) NOT NULL,
    [ExecutionId] NVARCHAR(256) NULL,
    [Type] NVARCHAR(50) NOT NULL,
    [Name] NVARCHAR(256) NULL,
    [Input] NVARCHAR(MAX) NULL,
    [LockedUntil] DATETIME2 NULL,
    [DequeueCount] INT NOT NULL DEFAULT 0,
    [CreatedTime] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    [Priority] INT NOT NULL DEFAULT 0,
    
    CONSTRAINT PK_WorkItem PRIMARY KEY CLUSTERED ([WorkItemId])
);

-- Critical index for work item dequeue performance
CREATE NONCLUSTERED INDEX IX_WorkItem_LockedUntil_Type_Priority
    ON dt.WorkItem ([LockedUntil], [Type], [Priority] DESC)
    INCLUDE ([WorkItemId], [InstanceId], [Name], [Input])
    WHERE [LockedUntil] IS NULL OR [LockedUntil] < GETUTCDATE();

-- NewEvents table
CREATE TABLE dt.NewEvents
(
    [EventId] BIGINT IDENTITY(1,1) NOT NULL,
    [InstanceId] NVARCHAR(256) NOT NULL,
    [ExecutionId] NVARCHAR(256) NULL,
    [EventType] NVARCHAR(100) NOT NULL,
    [Name] NVARCHAR(256) NULL,
    [Input] NVARCHAR(MAX) NULL,
    [Timestamp] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    [IsProcessed] BIT NOT NULL DEFAULT 0,
    
    CONSTRAINT PK_NewEvents PRIMARY KEY CLUSTERED ([EventId])
);

-- Index for event processing
CREATE NONCLUSTERED INDEX IX_NewEvents_InstanceId_IsProcessed
    ON dt.NewEvents ([InstanceId], [IsProcessed])
    INCLUDE ([EventType], [Name], [Input], [Timestamp])
    WHERE [IsProcessed] = 0;

GO
```

### Archive Tables

```sql
-- 02-CREATE-ARCHIVE-TABLES.sql
-- Create archive tables for completed orchestrations

CREATE TABLE dt.OrchestrationStateArchive
(
    [InstanceId] NVARCHAR(256) NOT NULL,
    [ExecutionId] NVARCHAR(256) NOT NULL,
    [Name] NVARCHAR(256) NOT NULL,
    [Version] NVARCHAR(100) NULL,
    [Status] NVARCHAR(50) NOT NULL,
    [Input] NVARCHAR(MAX) NULL,
    [Output] NVARCHAR(MAX) NULL,
    [CreatedTime] DATETIME2 NOT NULL,
    [CompletedTime] DATETIME2 NULL,
    [LastUpdatedTime] DATETIME2 NOT NULL,
    [ArchivedTime] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    
    CONSTRAINT PK_OrchestrationStateArchive PRIMARY KEY CLUSTERED 
        ([ArchivedTime], [InstanceId], [ExecutionId])
);

-- Partitioned by archive date for efficient queries and purging
CREATE NONCLUSTERED INDEX IX_OrchestrationStateArchive_InstanceId
    ON dt.OrchestrationStateArchive ([InstanceId])
    INCLUDE ([Name], [Status], [CreatedTime], [CompletedTime]);

CREATE TABLE dt.OrchestrationStateHistoryArchive
(
    [HistoryId] BIGINT IDENTITY(1,1) NOT NULL,
    [InstanceId] NVARCHAR(256) NOT NULL,
    [ExecutionId] NVARCHAR(256) NOT NULL,
    [SequenceNumber] INT NOT NULL,
    [EventType] NVARCHAR(100) NOT NULL,
    [Name] NVARCHAR(256) NULL,
    [Input] NVARCHAR(MAX) NULL,
    [Result] NVARCHAR(MAX) NULL,
    [Details] NVARCHAR(MAX) NULL,
    [Timestamp] DATETIME2 NOT NULL,
    [ArchivedTime] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    
    CONSTRAINT PK_OrchestrationStateHistoryArchive PRIMARY KEY CLUSTERED 
        ([ArchivedTime], [HistoryId])
);

GO
```

---

## Connection String Optimization

### Production Connection String

```csharp
using Microsoft.Data.SqlClient;

namespace SqlServerConfig;

/// <summary>
/// Optimized connection string builder for production.
/// </summary>
public static class ConnectionStringFactory
{
    public static string BuildProductionConnectionString(
        string server,
        string database,
        string username,
        string password)
    {
        var builder = new SqlConnectionStringBuilder
        {
            // Server configuration
            DataSource = server,
            InitialCatalog = database,
            
            // Authentication
            UserID = username,
            Password = password,
            IntegratedSecurity = false,
            
            // Connection pooling (CRITICAL for performance)
            Pooling = true,
            MinPoolSize = 10,
            MaxPoolSize = 200,
            
            // Timeouts
            ConnectTimeout = 30,
            CommandTimeout = 300, // 5 minutes
            
            // Reliability
            ConnectRetryCount = 3,
            ConnectRetryInterval = 10,
            
            // Security
            Encrypt = true,
            TrustServerCertificate = false, // Use true for self-signed certs in dev
            
            // Performance optimizations
            MultipleActiveResultSets = true, // MARS - important for concurrent queries
            PacketSize = 8192,
            ApplicationName = "DurableTask.Production",
            
            // Network performance
            ApplicationIntent = ApplicationIntent.ReadWrite,
            
            // Additional settings
            Pooling = true,
            LoadBalanceTimeout = 0,
            Replication = false
        };

        return builder.ConnectionString;
    }

    public static string BuildWindowsAuthConnectionString(
        string server,
        string database)
    {
        var builder = new SqlConnectionStringBuilder
        {
            DataSource = server,
            InitialCatalog = database,
            
            // Windows Authentication
            IntegratedSecurity = true,
            
            // Connection pooling
            Pooling = true,
            MinPoolSize = 10,
            MaxPoolSize = 200,
            
            // Timeouts
            ConnectTimeout = 30,
            CommandTimeout = 300,
            
            // Reliability
            ConnectRetryCount = 3,
            ConnectRetryInterval = 10,
            
            // Performance
            MultipleActiveResultSets = true,
            PacketSize = 8192,
            ApplicationName = "DurableTask.Production"
        };

        return builder.ConnectionString;
    }

    public static string BuildHighAvailabilityConnectionString(
        string primaryServer,
        string secondaryServer,
        string database,
        string username,
        string password)
    {
        var builder = new SqlConnectionStringBuilder
        {
            // Always On Availability Groups / Failover
            DataSource = primaryServer,
            FailoverPartner = secondaryServer,
            InitialCatalog = database,
            
            UserID = username,
            Password = password,
            
            // Pooling
            Pooling = true,
            MinPoolSize = 10,
            MaxPoolSize = 200,
            
            // Timeouts - shorter for faster failover detection
            ConnectTimeout = 15,
            CommandTimeout = 300,
            
            // Reliability
            ConnectRetryCount = 5,
            ConnectRetryInterval = 5,
            
            // Security
            Encrypt = true,
            TrustServerCertificate = false,
            
            // Performance
            MultipleActiveResultSets = true,
            ApplicationName = "DurableTask.HighAvailability"
        };

        return builder.ConnectionString;
    }
}
```

### Connection String from Configuration

```csharp
using Microsoft.Extensions.Configuration;

namespace SqlServerConfig;

/// <summary>
/// Load connection string from appsettings.json or environment variables.
/// </summary>
public sealed class ConnectionStringProvider
{
    private readonly IConfiguration _configuration;

    public ConnectionStringProvider(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    public string GetConnectionString()
    {
        // Try appsettings.json first
        var connectionString = _configuration.GetConnectionString("DurableTask");
        
        if (!string.IsNullOrEmpty(connectionString))
        {
            return connectionString;
        }

        // Fallback to environment variables
        var server = _configuration["DURABLETASK_SQL_SERVER"] 
            ?? throw new InvalidOperationException("SQL Server not configured");
        var database = _configuration["DURABLETASK_SQL_DATABASE"] 
            ?? throw new InvalidOperationException("Database not configured");
        var username = _configuration["DURABLETASK_SQL_USERNAME"];
        var password = _configuration["DURABLETASK_SQL_PASSWORD"];

        if (!string.IsNullOrEmpty(username) && !string.IsNullOrEmpty(password))
        {
            return ConnectionStringFactory.BuildProductionConnectionString(
                server, database, username, password);
        }

        // Use Windows Authentication
        return ConnectionStringFactory.BuildWindowsAuthConnectionString(
            server, database);
    }
}

// appsettings.json example:
/*
{
  "ConnectionStrings": {
    "DurableTask": "Server=localhost;Database=DurableTask;Integrated Security=true;TrustServerCertificate=true;MultipleActiveResultSets=true;Min Pool Size=10;Max Pool Size=200;"
  }
}
*/
```

---

## Performance Tuning

### Critical Indexes

```sql
-- 03-PERFORMANCE-INDEXES.sql
-- Additional indexes for optimal performance

-- Index for status queries (most common)
CREATE NONCLUSTERED INDEX IX_OrchestrationState_Status_LastUpdatedTime
    ON dt.OrchestrationState ([Status], [LastUpdatedTime] DESC)
    INCLUDE ([InstanceId], [Name], [CreatedTime])
    WITH (ONLINE = ON, FILLFACTOR = 90);

-- Index for instance lookup by name and date range
CREATE NONCLUSTERED INDEX IX_OrchestrationState_Name_CreatedTime
    ON dt.OrchestrationState ([Name], [CreatedTime] DESC)
    INCLUDE ([InstanceId], [Status], [ExecutionId])
    WITH (ONLINE = ON, FILLFACTOR = 90);

-- Covering index for history replay (CRITICAL for performance)
CREATE NONCLUSTERED INDEX IX_OrchestrationStateHistory_Replay
    ON dt.OrchestrationStateHistory ([InstanceId], [ExecutionId], [SequenceNumber])
    INCLUDE ([EventType], [Name], [Input], [Result], [Details], [Timestamp])
    WITH (ONLINE = ON, FILLFACTOR = 95);

-- Index for completed orchestrations cleanup
CREATE NONCLUSTERED INDEX IX_OrchestrationState_Cleanup
    ON dt.OrchestrationState ([Status], [CompletedTime])
    INCLUDE ([InstanceId], [ExecutionId])
    WHERE [Status] IN ('Completed', 'Failed', 'Terminated')
    WITH (ONLINE = ON);

-- Optimize work item dequeue (HOT PATH)
CREATE NONCLUSTERED INDEX IX_WorkItem_Dequeue_Optimized
    ON dt.WorkItem ([Type], [Priority] DESC, [CreatedTime])
    INCLUDE ([WorkItemId], [InstanceId], [ExecutionId], [Name], [Input])
    WHERE ([LockedUntil] IS NULL OR [LockedUntil] < GETUTCDATE())
    WITH (ONLINE = ON, FILLFACTOR = 80); -- Lower fill factor for high insert rate

GO
```

### Table Partitioning

```sql
-- 04-PARTITION-HISTORY.sql
-- Partition history table by date for better performance and maintenance

-- Create partition function (monthly partitions)
CREATE PARTITION FUNCTION PF_OrchestrationHistory(DATETIME2)
AS RANGE RIGHT FOR VALUES 
(
    '2026-01-01', '2026-02-01', '2026-03-01', '2026-04-01',
    '2026-05-01', '2026-06-01', '2026-07-01', '2026-08-01',
    '2026-09-01', '2026-10-01', '2026-11-01', '2026-12-01'
);

-- Create partition scheme
CREATE PARTITION SCHEME PS_OrchestrationHistory
AS PARTITION PF_OrchestrationHistory
ALL TO ([PRIMARY]); -- Or specify different filegroups

-- Recreate history table with partitioning
-- (Note: In production, create new table, migrate data, swap names)
CREATE TABLE dt.OrchestrationStateHistory_Partitioned
(
    [HistoryId] BIGINT IDENTITY(1,1) NOT NULL,
    [InstanceId] NVARCHAR(256) NOT NULL,
    [ExecutionId] NVARCHAR(256) NOT NULL,
    [SequenceNumber] INT NOT NULL,
    [EventType] NVARCHAR(100) NOT NULL,
    [Name] NVARCHAR(256) NULL,
    [Input] NVARCHAR(MAX) NULL,
    [Result] NVARCHAR(MAX) NULL,
    [Details] NVARCHAR(MAX) NULL,
    [Timestamp] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    
    CONSTRAINT PK_OrchestrationStateHistory_Partitioned 
        PRIMARY KEY CLUSTERED ([Timestamp], [HistoryId])
) ON PS_OrchestrationHistory([Timestamp]);

GO
```

### Statistics and Maintenance

```sql
-- 05-STATISTICS-MAINTENANCE.sql
-- Automated statistics update for optimal query plans

-- Create custom statistics on frequently queried columns
CREATE STATISTICS ST_OrchestrationState_StatusName
    ON dt.OrchestrationState ([Status], [Name])
    WITH FULLSCAN;

CREATE STATISTICS ST_WorkItem_TypePriority
    ON dt.WorkItem ([Type], [Priority])
    WITH FULLSCAN;

-- Update statistics with full scan (run weekly)
UPDATE STATISTICS dt.OrchestrationState WITH FULLSCAN;
UPDATE STATISTICS dt.OrchestrationStateHistory WITH FULLSCAN;
UPDATE STATISTICS dt.WorkItem WITH FULLSCAN;
UPDATE STATISTICS dt.NewEvents WITH FULLSCAN;

-- Check statistics health
SELECT 
    OBJECT_NAME(s.object_id) AS TableName,
    s.name AS StatisticName,
    sp.last_updated,
    sp.rows,
    sp.rows_sampled,
    sp.modification_counter
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE OBJECT_SCHEMA_NAME(s.object_id) = 'dt'
ORDER BY sp.last_updated ASC;

GO
```

### Query Store Configuration

```sql
-- 06-QUERY-STORE.sql
-- Enable Query Store for performance monitoring

ALTER DATABASE DurableTask
SET QUERY_STORE = ON
(
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 15,
    MAX_STORAGE_SIZE_MB = 1024,
    QUERY_CAPTURE_MODE = AUTO,
    SIZE_BASED_CLEANUP_MODE = AUTO
);

-- Query to find slow queries
SELECT TOP 20
    q.query_id,
    qt.query_sql_text,
    rs.avg_duration / 1000.0 AS avg_duration_ms,
    rs.avg_cpu_time / 1000.0 AS avg_cpu_time_ms,
    rs.avg_logical_io_reads,
    rs.count_executions
FROM sys.query_store_query q
INNER JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
WHERE qt.query_sql_text LIKE '%dt.OrchestrationState%'
    OR qt.query_sql_text LIKE '%dt.WorkItem%'
ORDER BY rs.avg_duration DESC;

GO
```

---

## Monitoring and Diagnostics

### Performance Monitoring Queries

```sql
-- 07-MONITORING-QUERIES.sql
-- Queries for monitoring DTFx performance

-- 1. Active orchestrations by status
SELECT 
    Status,
    COUNT(*) AS Count,
    AVG(DATEDIFF(SECOND, CreatedTime, GETUTCDATE())) AS AvgAgeSeconds
FROM dt.OrchestrationState
GROUP BY Status
ORDER BY Count DESC;

-- 2. Oldest pending work items
SELECT TOP 20
    WorkItemId,
    InstanceId,
    Type,
    Name,
    CreatedTime,
    DATEDIFF(SECOND, CreatedTime, GETUTCDATE()) AS AgeSeconds,
    DequeueCount
FROM dt.WorkItem
WHERE LockedUntil IS NULL OR LockedUntil < GETUTCDATE()
ORDER BY CreatedTime ASC;

-- 3. Orchestrations by duration
SELECT 
    Name,
    COUNT(*) AS TotalRuns,
    AVG(DATEDIFF(SECOND, CreatedTime, CompletedTime)) AS AvgDurationSeconds,
    MAX(DATEDIFF(SECOND, CreatedTime, CompletedTime)) AS MaxDurationSeconds,
    MIN(DATEDIFF(SECOND, CreatedTime, CompletedTime)) AS MinDurationSeconds
FROM dt.OrchestrationState
WHERE Status IN ('Completed', 'Failed')
    AND CompletedTime IS NOT NULL
    AND CreatedTime > DATEADD(DAY, -7, GETUTCDATE())
GROUP BY Name
ORDER BY AvgDurationSeconds DESC;

-- 4. History size by instance (identify bloated histories)
SELECT TOP 20
    InstanceId,
    ExecutionId,
    COUNT(*) AS EventCount,
    SUM(DATALENGTH(Input) + DATALENGTH(Result) + DATALENGTH(Details)) / 1024.0 AS SizeKB
FROM dt.OrchestrationStateHistory
GROUP BY InstanceId, ExecutionId
ORDER BY EventCount DESC;

-- 5. Failed orchestrations in last 24 hours
SELECT 
    InstanceId,
    Name,
    CreatedTime,
    CompletedTime,
    Output AS ErrorDetails
FROM dt.OrchestrationState
WHERE Status = 'Failed'
    AND CompletedTime > DATEADD(HOUR, -24, GETUTCDATE())
ORDER BY CompletedTime DESC;

-- 6. Work item queue depth over time
SELECT 
    Type,
    COUNT(*) AS QueueDepth,
    AVG(DATEDIFF(SECOND, CreatedTime, GETUTCDATE())) AS AvgWaitTimeSeconds,
    MAX(DATEDIFF(SECOND, CreatedTime, GETUTCDATE())) AS MaxWaitTimeSeconds
FROM dt.WorkItem
WHERE LockedUntil IS NULL OR LockedUntil < GETUTCDATE()
GROUP BY Type;

-- 7. Lock contention (work items locked too long)
SELECT TOP 20
    WorkItemId,
    InstanceId,
    Type,
    Name,
    CreatedTime,
    LockedUntil,
    DATEDIFF(SECOND, CreatedTime, GETUTCDATE()) AS LockedForSeconds,
    DequeueCount
FROM dt.WorkItem
WHERE LockedUntil > GETUTCDATE()
    AND DATEDIFF(MINUTE, CreatedTime, GETUTCDATE()) > 15
ORDER BY LockedForSeconds DESC;

-- 8. Database size and growth
SELECT 
    name AS TableName,
    SUM(CASE WHEN index_id IN (0, 1) THEN row_count ELSE 0 END) AS RowCount,
    SUM(reserved_page_count) * 8.0 / 1024 AS ReservedSizeMB,
    SUM(used_page_count) * 8.0 / 1024 AS UsedSizeMB
FROM sys.dm_db_partition_stats ps
INNER JOIN sys.objects o ON ps.object_id = o.object_id
WHERE o.schema_id = SCHEMA_ID('dt')
GROUP BY name
ORDER BY ReservedSizeMB DESC;

GO
```

### Performance Counters

```csharp
using System.Diagnostics;
using System.Diagnostics.Metrics;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace SqlServerConfig;

/// <summary>
/// Background service to collect and report DTFx performance metrics.
/// </summary>
public sealed class DurableTaskMetricsCollector : BackgroundService
{
    private readonly string _connectionString;
    private readonly ILogger<DurableTaskMetricsCollector> _logger;
    private readonly Meter _meter;
    
    private readonly ObservableGauge<long> _activeOrchestrations;
    private readonly ObservableGauge<long> _pendingWorkItems;
    private readonly ObservableGauge<long> _failedOrchestrations;
    private readonly Counter<long> _orchestrationsCompleted;
    private readonly Histogram<double> _orchestrationDuration;

    public DurableTaskMetricsCollector(
        string connectionString,
        ILogger<DurableTaskMetricsCollector> logger)
    {
        _connectionString = connectionString;
        _logger = logger;
        _meter = new Meter("DurableTask.SqlServer");

        _activeOrchestrations = _meter.CreateObservableGauge(
            "durabletask_active_orchestrations",
            GetActiveOrchestrationsCount,
            description: "Number of active orchestrations");

        _pendingWorkItems = _meter.CreateObservableGauge(
            "durabletask_pending_workitems",
            GetPendingWorkItemsCount,
            description: "Number of pending work items");

        _failedOrchestrations = _meter.CreateObservableGauge(
            "durabletask_failed_orchestrations_24h",
            GetFailedOrchestrationsCount,
            description: "Number of failed orchestrations in last 24 hours");

        _orchestrationsCompleted = _meter.CreateCounter<long>(
            "durabletask_orchestrations_completed",
            description: "Total orchestrations completed");

        _orchestrationDuration = _meter.CreateHistogram<double>(
            "durabletask_orchestration_duration_seconds",
            unit: "s",
            description: "Orchestration duration in seconds");
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    private long GetActiveOrchestrationsCount()
    {
        try
        {
            using var connection = new SqlConnection(_connectionString);
            connection.Open();

            var command = new SqlCommand(@"
                SELECT COUNT(*) 
                FROM dt.OrchestrationState 
                WHERE Status IN ('Running', 'Pending')
            ", connection);

            return (long)(int)command.ExecuteScalar()!;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get active orchestrations count");
            return 0;
        }
    }

    private long GetPendingWorkItemsCount()
    {
        try
        {
            using var connection = new SqlConnection(_connectionString);
            connection.Open();

            var command = new SqlCommand(@"
                SELECT COUNT(*) 
                FROM dt.WorkItem 
                WHERE LockedUntil IS NULL OR LockedUntil < GETUTCDATE()
            ", connection);

            return (long)(int)command.ExecuteScalar()!;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get pending work items count");
            return 0;
        }
    }

    private long GetFailedOrchestrationsCount()
    {
        try
        {
            using var connection = new SqlConnection(_connectionString);
            connection.Open();

            var command = new SqlCommand(@"
                SELECT COUNT(*) 
                FROM dt.OrchestrationState 
                WHERE Status = 'Failed' 
                    AND CompletedTime > DATEADD(HOUR, -24, GETUTCDATE())
            ", connection);

            return (long)(int)command.ExecuteScalar()!;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get failed orchestrations count");
            return 0;
        }
    }
}
```

---

## History Management and Archival

### Automated Archival Strategy

```csharp
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace SqlServerConfig;

/// <summary>
/// Background service to archive completed orchestrations.
/// </summary>
public sealed class OrchestrationArchivalService : BackgroundService
{
    private readonly string _connectionString;
    private readonly ILogger<OrchestrationArchivalService> _logger;
    private readonly TimeSpan _archivalInterval = TimeSpan.FromHours(6);
    private readonly int _retentionDays = 30;

    public OrchestrationArchivalService(
        string connectionString,
        ILogger<OrchestrationArchivalService> logger)
    {
        _connectionString = connectionString;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Orchestration archival service started");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await PerformArchival(stoppingToken);
                await Task.Delay(_archivalInterval, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Archival failed");
                await Task.Delay(TimeSpan.FromMinutes(30), stoppingToken);
            }
        }

        _logger.LogInformation("Orchestration archival service stopped");
    }

    private async Task PerformArchival(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Starting orchestration archival");

        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        try
        {
            var cutoffDate = DateTime.UtcNow.AddDays(-_retentionDays);

            // Archive orchestration state
            var stateArchived = await ArchiveOrchestrationState(
                connection, 
                transaction, 
                cutoffDate, 
                cancellationToken);

            // Archive history
            var historyArchived = await ArchiveOrchestrationHistory(
                connection, 
                transaction, 
                cutoffDate, 
                cancellationToken);

            await transaction.CommitAsync(cancellationToken);

            _logger.LogInformation(
                "Archival completed: {StateCount} states, {HistoryCount} history records",
                stateArchived,
                historyArchived);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Archival transaction failed, rolling back");
            await transaction.RollbackAsync(cancellationToken);
            throw;
        }
    }

    private async Task<int> ArchiveOrchestrationState(
        SqlConnection connection,
        SqlTransaction transaction,
        DateTime cutoffDate,
        CancellationToken cancellationToken)
    {
        var command = new SqlCommand(@"
            -- Move to archive
            INSERT INTO dt.OrchestrationStateArchive
            SELECT *, GETUTCDATE() AS ArchivedTime
            FROM dt.OrchestrationState
            WHERE Status IN ('Completed', 'Failed', 'Terminated')
                AND CompletedTime < @CutoffDate;
            
            -- Delete from active table
            DELETE FROM dt.OrchestrationState
            WHERE Status IN ('Completed', 'Failed', 'Terminated')
                AND CompletedTime < @CutoffDate;
            
            SELECT @@ROWCOUNT;
        ", connection, transaction);

        command.Parameters.AddWithValue("@CutoffDate", cutoffDate);
        command.CommandTimeout = 600; // 10 minutes

        return (int)(await command.ExecuteScalarAsync(cancellationToken) ?? 0);
    }

    private async Task<int> ArchiveOrchestrationHistory(
        SqlConnection connection,
        SqlTransaction transaction,
        DateTime cutoffDate,
        CancellationToken cancellationToken)
    {
        var command = new SqlCommand(@"
            -- Move to archive
            INSERT INTO dt.OrchestrationStateHistoryArchive
            SELECT h.*, GETUTCDATE() AS ArchivedTime
            FROM dt.OrchestrationStateHistory h
            INNER JOIN dt.OrchestrationStateArchive a
                ON h.InstanceId = a.InstanceId 
                AND h.ExecutionId = a.ExecutionId
            WHERE a.ArchivedTime >= DATEADD(MINUTE, -10, GETUTCDATE());
            
            -- Delete from active table
            DELETE h
            FROM dt.OrchestrationStateHistory h
            INNER JOIN dt.OrchestrationStateArchive a
                ON h.InstanceId = a.InstanceId 
                AND h.ExecutionId = a.ExecutionId
            WHERE a.ArchivedTime >= DATEADD(MINUTE, -10, GETUTCDATE());
            
            SELECT @@ROWCOUNT;
        ", connection, transaction);

        command.CommandTimeout = 600;

        return (int)(await command.ExecuteScalarAsync(cancellationToken) ?? 0);
    }
}
```

---

## Backup and Recovery

### Backup Strategy

```sql
-- 08-BACKUP-STRATEGY.sql
-- Automated backup script for DurableTask database

-- Full backup daily
BACKUP DATABASE [DurableTask]
TO DISK = 'D:\Backups\DurableTask_Full.bak'
WITH 
    COMPRESSION,
    INIT,
    NAME = 'DurableTask Full Backup',
    STATS = 10,
    CHECKSUM;

-- Differential backup every 6 hours
BACKUP DATABASE [DurableTask]
TO DISK = 'D:\Backups\DurableTask_Diff.bak'
WITH 
    DIFFERENTIAL,
    COMPRESSION,
    INIT,
    NAME = 'DurableTask Differential Backup',
    STATS = 10,
    CHECKSUM;

-- Transaction log backup every 15 minutes
BACKUP LOG [DurableTask]
TO DISK = 'D:\Backups\DurableTask_Log.trn'
WITH 
    COMPRESSION,
    INIT,
    NAME = 'DurableTask Log Backup',
    STATS = 10,
    CHECKSUM;

GO
```

### Recovery Procedures

```sql
-- 09-RECOVERY.sql
-- Recovery procedures for disaster scenarios

-- Point-in-time recovery
RESTORE DATABASE [DurableTask]
FROM DISK = 'D:\Backups\DurableTask_Full.bak'
WITH NORECOVERY, REPLACE;

RESTORE DATABASE [DurableTask]
FROM DISK = 'D:\Backups\DurableTask_Diff.bak'
WITH NORECOVERY;

RESTORE LOG [DurableTask]
FROM DISK = 'D:\Backups\DurableTask_Log.trn'
WITH RECOVERY, STOPAT = '2026-01-30 14:30:00';

GO

-- Verify database integrity after recovery
DBCC CHECKDB ([DurableTask]) WITH NO_INFOMSGS;

GO
```

---

## On-Premises Deployment Patterns

### Windows Service Deployment

```csharp
using DurableTask.Core;
using DurableTask.SqlServer;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Deployment;

/// <summary>
/// Windows Service host for DurableTask worker.
/// </summary>
public class Program
{
    public static async Task Main(string[] args)
    {
        await Host.CreateDefaultBuilder(args)
            .UseWindowsService() // Enable Windows Service support
            .ConfigureServices((hostContext, services) =>
            {
                // Configuration
                var connectionString = hostContext.Configuration
                    .GetConnectionString("DurableTask")
                    ?? throw new InvalidOperationException("Connection string not configured");

                // Register SQL Server service
                var sqlService = SqlServerOrchestrationServiceFactory
                    .CreateService(connectionString);
                
                services.AddSingleton<IOrchestrationService>(sqlService);

                // Register worker as hosted service
                services.AddHostedService<DurableTaskWorkerService>();

                // Register metrics collector
                services.AddSingleton(connectionString);
                services.AddHostedService<DurableTaskMetricsCollector>();

                // Register archival service
                services.AddHostedService<OrchestrationArchivalService>();
            })
            .Build()
            .RunAsync();
    }
}

/// <summary>
/// Hosted service that runs the DurableTask worker.
/// </summary>
public sealed class DurableTaskWorkerService : BackgroundService
{
    private readonly IOrchestrationService _orchestrationService;
    private readonly ILogger<DurableTaskWorkerService> _logger;
    private readonly ILoggerFactory _loggerFactory;
    private TaskHubWorker? _worker;

    public DurableTaskWorkerService(
        IOrchestrationService orchestrationService,
        ILogger<DurableTaskWorkerService> logger,
        ILoggerFactory loggerFactory)
    {
        _orchestrationService = orchestrationService;
        _logger = logger;
        _loggerFactory = loggerFactory;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("DurableTask worker starting");

        // Create database schema if not exists
        await _orchestrationService.CreateIfNotExistsAsync();

        // Create worker
        _worker = new TaskHubWorker(_orchestrationService, _loggerFactory)
        {
            ErrorPropagationMode = ErrorPropagationMode.UseFailureDetails,
            MaxConcurrentTaskOrchestrations = 50,
            MaxConcurrentTaskActivities = 100
        };

        // Register orchestrations and activities
        RegisterWorkflows(_worker);

        // Start worker
        await _worker.StartAsync();
        _logger.LogInformation("DurableTask worker started");

        // Wait for cancellation
        await Task.Delay(Timeout.Infinite, stoppingToken);
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("DurableTask worker stopping");

        if (_worker != null)
        {
            await _worker.StopAsync();
        }

        _logger.LogInformation("DurableTask worker stopped");
        await base.StopAsync(cancellationToken);
    }

    private void RegisterWorkflows(TaskHubWorker worker)
    {
        // Register orchestrations
        worker.AddTaskOrchestrations(
            typeof(OrderProcessingOrchestration),
            typeof(PaymentOrchestration),
            typeof(ShipmentOrchestration)
        );

        // Register activities
        worker.AddTaskActivities(
            typeof(ValidateOrderActivity),
            typeof(ProcessPaymentActivity),
            typeof(ShipOrderActivity)
        );
    }
}
```

### IIS Deployment (Not Recommended)

```xml
<!-- web.config for IIS deployment -->
<!-- Note: IIS is NOT recommended for long-running workers -->
<!-- Use Windows Service or console application instead -->

<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <handlers>
      <add name="aspNetCore" path="*" verb="*" modules="AspNetCoreModuleV2" resourceType="Unspecified" />
    </handlers>
    <aspNetCore processPath="dotnet" 
                arguments=".\DurableTaskWorker.dll" 
                stdoutLogEnabled="true" 
                stdoutLogFile=".\logs\stdout" 
                hostingModel="outofprocess">
      <environmentVariables>
        <environmentVariable name="ASPNETCORE_ENVIRONMENT" value="Production" />
      </environmentVariables>
    </aspNetCore>
  </system.webServer>
</configuration>
```

### Docker Deployment

```dockerfile
# Dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS base
WORKDIR /app

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY ["DurableTaskWorker.csproj", "./"]
RUN dotnet restore "DurableTaskWorker.csproj"
COPY . .
RUN dotnet build "DurableTaskWorker.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "DurableTaskWorker.csproj" -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl --fail http://localhost:8080/health || exit 1

ENTRYPOINT ["dotnet", "DurableTaskWorker.dll"]
```

```yaml
# docker-compose.yml
version: '3.8'

services:
  sqlserver:
    image: mcr.microsoft.com/mssql/server:2022-latest
    environment:
      - ACCEPT_EULA=Y
      - SA_PASSWORD=YourStrong!Passw0rd
    ports:
      - "1433:1433"
    volumes:
      - sqldata:/var/opt/mssql

  durabletask-worker:
    build: .
    depends_on:
      - sqlserver
    environment:
      - ConnectionStrings__DurableTask=Server=sqlserver;Database=DurableTask;User Id=sa;Password=YourStrong!Passw0rd;TrustServerCertificate=true;
    restart: unless-stopped
    deploy:
      replicas: 3 # Scale workers

volumes:
  sqldata:
```

---

## Troubleshooting Guide

### Common Issues

```sql
-- 10-TROUBLESHOOTING.sql
-- Diagnostic queries for common issues

-- Issue 1: Stuck orchestrations (running too long)
SELECT 
    InstanceId,
    Name,
    Status,
    CreatedTime,
    LastUpdatedTime,
    DATEDIFF(MINUTE, LastUpdatedTime, GETUTCDATE()) AS MinutesSinceUpdate
FROM dt.OrchestrationState
WHERE Status = 'Running'
    AND DATEDIFF(HOUR, LastUpdatedTime, GETUTCDATE()) > 24
ORDER BY LastUpdatedTime ASC;

-- Issue 2: Work items stuck (locked too long)
SELECT 
    WorkItemId,
    InstanceId,
    Type,
    Name,
    LockedUntil,
    DATEDIFF(MINUTE, LockedUntil, GETUTCDATE()) AS MinutesOverdue,
    DequeueCount
FROM dt.WorkItem
WHERE LockedUntil < GETUTCDATE()
    AND DATEDIFF(HOUR, LockedUntil, GETUTCDATE()) > 1
ORDER BY DequeueCount DESC;

-- Fix: Unlock stuck work items
UPDATE dt.WorkItem
SET LockedUntil = NULL
WHERE LockedUntil < DATEADD(HOUR, -1, GETUTCDATE());

-- Issue 3: Deadlocks
SELECT 
    *
FROM sys.dm_db_deadlock_errors
WHERE database_id = DB_ID('DurableTask')
ORDER BY timestamp DESC;

-- Issue 4: Index fragmentation
SELECT 
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE OBJECT_SCHEMA_NAME(ips.object_id) = 'dt'
    AND ips.avg_fragmentation_in_percent > 30
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- Fix: Rebuild fragmented indexes
ALTER INDEX ALL ON dt.OrchestrationState REBUILD WITH (ONLINE = ON);
ALTER INDEX ALL ON dt.OrchestrationStateHistory REBUILD WITH (ONLINE = ON);
ALTER INDEX ALL ON dt.WorkItem REBUILD WITH (ONLINE = ON);

GO
```

---

## Production Checklist

### Pre-Deployment

- [ ] **Database Setup**
  - [ ] Create database with appropriate size and growth settings
  - [ ] Run schema creation scripts
  - [ ] Create indexes (including custom performance indexes)
  - [ ] Enable Query Store
  - [ ] Configure backup strategy

- [ ] **Security**
  - [ ] Create dedicated SQL user for DurableTask
  - [ ] Grant minimum required permissions
  - [ ] Enable encryption (TLS/SSL)
  - [ ] Configure firewall rules

- [ ] **Configuration**
  - [ ] Optimize connection string (pooling, timeouts, MARS)
  - [ ] Configure SqlOrchestrationServiceSettings
  - [ ] Set appropriate lock timeouts
  - [ ] Configure work item batch sizes

- [ ] **Monitoring**
  - [ ] Set up performance counter collection
  - [ ] Configure alerting (failed orchestrations, queue depth)
  - [ ] Enable diagnostic logging
  - [ ] Set up dashboard

### Post-Deployment

- [ ] **Maintenance**
  - [ ] Schedule index maintenance (weekly)
  - [ ] Schedule statistics updates (weekly)
  - [ ] Configure archival service (retention: 30 days)
  - [ ] Set up automated backups (full daily, diff 6h, log 15min)

- [ ] **Monitoring**
  - [ ] Verify metrics collection
  - [ ] Check alert thresholds
  - [ ] Monitor queue depth
  - [ ] Track failed orchestrations

- [ ] **Performance**
  - [ ] Monitor query performance (Query Store)
  - [ ] Check index fragmentation weekly
  - [ ] Monitor database growth
  - [ ] Review slow queries

---

## Summary

This module covered:

✅ **SQL Server Configuration**: Production-ready settings  
✅ **Database Schema**: Tables, indexes, partitioning  
✅ **Connection Optimization**: Pooling, timeouts, MARS  
✅ **Performance Tuning**: Indexes, statistics, Query Store  
✅ **Monitoring**: Queries, metrics, diagnostics  
✅ **History Management**: Archival, retention, cleanup  
✅ **Backup/Recovery**: Strategy, procedures  
✅ **On-Premises Deployment**: Windows Service, Docker  
✅ **Troubleshooting**: Common issues, diagnostic queries  
✅ **Production Checklist**: Pre/post deployment tasks  

**Next**: [07-SCAFFOLDING.md](./07-SCAFFOLDING.md) - Complete project templates and code generation for .NET 9+.
