# 04 - OPTIMIZATION & PERFORMANCE

**Deep dive into performance tuning, history management, serialization, concurrency, and SQL Server optimizations.**

---

## Table of Contents

1. [History Management](#history-management)
2. [Serialization Optimization](#serialization-optimization)
3. [Concurrency Tuning](#concurrency-tuning)
4. [SQL Server Optimizations](#sql-server-optimizations)
5. [Activity vs Sub-Orchestration Performance](#activity-vs-sub-orchestration-performance)
6. [Batching Strategies](#batching-strategies)
7. [Performance Monitoring](#performance-monitoring)
8. [Production Optimization Checklist](#production-optimization-checklist)

---

## History Management

### Understanding History Growth

Every orchestration action creates a history event:
- **ScheduleTask**: +1 event (TaskScheduled)
- **Task Completion**: +1 event (TaskCompleted/TaskFailed)
- **CreateTimer**: +1 event (TimerCreated)
- **Timer Fires**: +1 event (TimerFired)
- **Sub-Orchestration**: +1 event (SubOrchestrationInstanceCreated + SubOrchestrationInstanceCompleted)
- **External Event**: +1 event (EventRaised)

**Problem**: Large history = slow replay, increased memory, database bloat.

### When to Use ContinueAsNew

```csharp
using DurableTask.Core;

namespace Optimization.History;

/// <summary>
/// Eternal orchestration with proper history management.
/// </summary>
public sealed class MonitoringOrchestration : TaskOrchestration<string, MonitorConfig>
{
    private const int MaxIterationsBeforeReset = 100;

    public override async Task<string> RunTask(
        OrchestrationContext context, 
        MonitorConfig input)
    {
        var iteration = input.CurrentIteration;

        // Perform monitoring check
        var status = await context.ScheduleTask<HealthStatus>(
            typeof(CheckHealthActivity),
            input.ServiceUrl);

        if (!status.IsHealthy)
        {
            await context.ScheduleTask<bool>(
                typeof(SendAlertActivity),
                new Alert(input.ServiceUrl, status.ErrorMessage));
        }

        // Wait for next check
        await context.CreateTimer(
            context.CurrentUtcDateTime.Add(input.CheckInterval),
            CancellationToken.None);

        iteration++;

        // Reset history every 100 iterations
        if (iteration >= MaxIterationsBeforeReset)
        {
            // ContinueAsNew creates a new orchestration instance with clean history
            context.ContinueAsNew(input with { CurrentIteration = 0 });
            return "Continued as new";
        }

        // Continue with incremented iteration
        context.ContinueAsNew(input with { CurrentIteration = iteration });
        return "Monitoring continues";
    }
}

public sealed record MonitorConfig
{
    public required string ServiceUrl { get; init; }
    public required TimeSpan CheckInterval { get; init; }
    public int CurrentIteration { get; init; } = 0;
}

public sealed record HealthStatus
{
    public required bool IsHealthy { get; init; }
    public string? ErrorMessage { get; init; }
}
```

### History Size Monitoring

```csharp
using DurableTask.Core;
using Microsoft.Extensions.Logging;

namespace Optimization.History;

/// <summary>
/// Orchestration that monitors its own history size.
/// </summary>
public sealed class SelfMonitoringOrchestration : TaskOrchestration<string, WorkflowInput>
{
    private const int MaxHistoryEvents = 500;

    public override async Task<string> RunTask(
        OrchestrationContext context, 
        WorkflowInput input)
    {
        var currentHistorySize = EstimateHistorySize(context);

        if (currentHistorySize > MaxHistoryEvents)
        {
            // Log warning about large history
            await context.ScheduleTask<bool>(
                typeof(LogWarningActivity),
                $"History size exceeded {MaxHistoryEvents} events for instance {context.OrchestrationInstance.InstanceId}");

            // Consider using ContinueAsNew or sub-orchestrations
            return await MigrateToSubOrchestrations(context, input);
        }

        return await ProcessNormally(context, input);
    }

    private static int EstimateHistorySize(OrchestrationContext context)
    {
        // Rough estimation based on orchestration runtime
        // In production, you'd query the database directly
        var runtime = context.CurrentUtcDateTime - context.OrchestrationInstance.ExecutionId.GetCreatedTime();
        return (int)(runtime.TotalMinutes * 10); // Estimate: 10 events per minute
    }

    private async Task<string> MigrateToSubOrchestrations(
        OrchestrationContext context, 
        WorkflowInput input)
    {
        // Break remaining work into sub-orchestrations to reset history
        var remainingWork = input.RemainingItems;
        var batchSize = 50;

        var batches = remainingWork
            .Select((item, index) => new { item, index })
            .GroupBy(x => x.index / batchSize)
            .Select(g => g.Select(x => x.item).ToArray())
            .ToArray();

        foreach (var batch in batches)
        {
            var instanceId = $"{context.OrchestrationInstance.InstanceId}:Batch{batch.GetHashCode()}";
            
            await context.CreateSubOrchestrationInstance<string>(
                typeof(ProcessBatchOrchestration),
                instanceId,
                new BatchInput { Items = batch });
        }

        return "Migrated to sub-orchestrations";
    }

    private async Task<string> ProcessNormally(
        OrchestrationContext context, 
        WorkflowInput input)
    {
        // Normal processing logic
        foreach (var item in input.RemainingItems.Take(10))
        {
            await context.ScheduleTask<bool>(
                typeof(ProcessItemActivity),
                item);
        }

        return "Processing complete";
    }
}

public sealed record WorkflowInput
{
    public required string[] RemainingItems { get; init; }
}

public sealed record BatchInput
{
    public required string[] Items { get; init; }
}
```

### Pagination with ContinueAsNew

```csharp
using DurableTask.Core;

namespace Optimization.History;

/// <summary>
/// Process large dataset with pagination to manage history.
/// </summary>
public sealed class PaginatedProcessingOrchestration : TaskOrchestration<ProcessingResult, PagedRequest>
{
    private const int ItemsPerPage = 100;
    private const int MaxPagesBeforeReset = 50; // Reset every 5000 items

    public override async Task<ProcessingResult> RunTask(
        OrchestrationContext context, 
        PagedRequest input)
    {
        var currentPage = input.CurrentPage;
        var totalProcessed = input.TotalProcessed;

        // Fetch current page
        var page = await context.ScheduleTask<PageData>(
            typeof(FetchPageActivity),
            new FetchPageRequest(input.DataSource, currentPage, ItemsPerPage));

        if (page.Items.Length == 0)
        {
            // No more data
            return ProcessingResult.Completed(totalProcessed);
        }

        // Process page items in parallel
        var tasks = page.Items.Select(item =>
            context.ScheduleTask<bool>(typeof(ProcessItemActivity), item)
        ).ToArray();

        await Task.WhenAll(tasks);

        totalProcessed += page.Items.Length;
        currentPage++;

        // Reset history periodically
        if (currentPage % MaxPagesBeforeReset == 0)
        {
            context.ContinueAsNew(input with 
            { 
                CurrentPage = currentPage,
                TotalProcessed = totalProcessed 
            });
            return ProcessingResult.InProgress(totalProcessed);
        }

        // Continue to next page
        context.ContinueAsNew(input with 
        { 
            CurrentPage = currentPage,
            TotalProcessed = totalProcessed 
        });
        
        return ProcessingResult.InProgress(totalProcessed);
    }
}

public sealed record PagedRequest
{
    public required string DataSource { get; init; }
    public int CurrentPage { get; init; } = 0;
    public int TotalProcessed { get; init; } = 0;
}

public sealed record PageData
{
    public required string[] Items { get; init; }
}

public sealed record FetchPageRequest(string DataSource, int PageNumber, int PageSize);

public sealed record ProcessingResult
{
    public required ProcessingStatus Status { get; init; }
    public int TotalProcessed { get; init; }

    public static ProcessingResult InProgress(int processed) => new()
    {
        Status = ProcessingStatus.InProgress,
        TotalProcessed = processed
    };

    public static ProcessingResult Completed(int processed) => new()
    {
        Status = ProcessingStatus.Completed,
        TotalProcessed = processed
    };
}

public enum ProcessingStatus { InProgress, Completed }
```

---

## Serialization Optimization

### Custom JsonDataConverter

```csharp
using DurableTask.Core;
using DurableTask.Core.Serializing;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Optimization.Serialization;

/// <summary>
/// Optimized JSON converter with compression and custom settings.
/// </summary>
public sealed class OptimizedJsonDataConverter : JsonDataConverter
{
    public OptimizedJsonDataConverter() : base(CreateSerializerSettings())
    {
    }

    private static JsonSerializerOptions CreateSerializerSettings()
    {
        return new JsonSerializerOptions
        {
            // Performance optimizations
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            PropertyNamingPolicy = null, // Don't convert property names
            WriteIndented = false, // Compact JSON
            
            // Type handling for polymorphism
            Converters =
            {
                new JsonStringEnumConverter(), // Enums as strings for readability
            },
            
            // Enable source generation for AOT (optional)
            // TypeInfoResolver = AppJsonContext.Default
        };
    }
}

// Optional: Source-generated serialization context for AOT
[JsonSourceGenerationOptions(
    WriteIndented = false,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)]
[JsonSerializable(typeof(OrderRequest))]
[JsonSerializable(typeof(OrderResult))]
[JsonSerializable(typeof(PaymentInfo))]
internal partial class AppJsonContext : JsonSerializerContext
{
}
```

### Large Payload Handling

```csharp
using DurableTask.Core;
using System.IO.Compression;
using System.Text;
using System.Text.Json;

namespace Optimization.Serialization;

/// <summary>
/// Handle large payloads with compression and external storage.
/// </summary>
public sealed class LargePayloadOrchestration : TaskOrchestration<string, LargeDataRequest>
{
    private const int MaxInlineDataSize = 50_000; // 50KB

    public override async Task<string> RunTask(
        OrchestrationContext context, 
        LargeDataRequest input)
    {
        string dataReference;

        if (input.DataSize > MaxInlineDataSize)
        {
            // Store large data externally (blob storage, file system, etc.)
            dataReference = await context.ScheduleTask<string>(
                typeof(StoreExternalDataActivity),
                input.LargeData);

            // Process with reference only
            await context.ScheduleTask<bool>(
                typeof(ProcessDataReferenceActivity),
                dataReference);
        }
        else
        {
            // Small data - pass directly
            await context.ScheduleTask<bool>(
                typeof(ProcessDataActivity),
                input.LargeData);
        }

        return "Processing complete";
    }
}

public sealed record LargeDataRequest
{
    public required byte[] LargeData { get; init; }
    public int DataSize => LargeData.Length;
}

/// <summary>
/// Activity that compresses data before serialization.
/// </summary>
public sealed class CompressDataActivity : TaskActivity<byte[], byte[]>
{
    protected override byte[] Execute(TaskContext context, byte[] input)
    {
        using var outputStream = new MemoryStream();
        using (var gzipStream = new GZipStream(outputStream, CompressionLevel.Optimal))
        {
            gzipStream.Write(input, 0, input.Length);
        }
        return outputStream.ToArray();
    }
}

/// <summary>
/// Activity that decompresses data after deserialization.
/// </summary>
public sealed class DecompressDataActivity : TaskActivity<byte[], byte[]>
{
    protected override byte[] Execute(TaskContext context, byte[] input)
    {
        using var inputStream = new MemoryStream(input);
        using var gzipStream = new GZipStream(inputStream, CompressionMode.Decompress);
        using var outputStream = new MemoryStream();
        
        gzipStream.CopyTo(outputStream);
        return outputStream.ToArray();
    }
}
```

### Efficient Data Transfer Pattern

```csharp
using DurableTask.Core;

namespace Optimization.Serialization;

/// <summary>
/// Transfer large datasets efficiently using chunking.
/// </summary>
public sealed class ChunkedDataOrchestration : TaskOrchestration<string, DataTransferRequest>
{
    private const int ChunkSize = 10_000; // 10KB chunks

    public override async Task<string> RunTask(
        OrchestrationContext context, 
        DataTransferRequest input)
    {
        var totalSize = input.TotalDataSize;
        var chunks = (int)Math.Ceiling((double)totalSize / ChunkSize);

        for (int i = 0; i < chunks; i++)
        {
            var chunkRequest = new ChunkRequest
            {
                DataSource = input.DataSource,
                ChunkIndex = i,
                ChunkSize = ChunkSize
            };

            // Process each chunk
            await context.ScheduleTask<bool>(
                typeof(ProcessChunkActivity),
                chunkRequest);

            // Every 10 chunks, reset history
            if ((i + 1) % 10 == 0 && i < chunks - 1)
            {
                context.ContinueAsNew(input with 
                { 
                    StartChunk = i + 1 
                });
                return "Continuing with next batch";
            }
        }

        return $"Processed {chunks} chunks";
    }
}

public sealed record DataTransferRequest
{
    public required string DataSource { get; init; }
    public required long TotalDataSize { get; init; }
    public int StartChunk { get; init; } = 0;
}

public sealed record ChunkRequest
{
    public required string DataSource { get; init; }
    public required int ChunkIndex { get; init; }
    public required int ChunkSize { get; init; }
}
```

---

## Concurrency Tuning

### TaskHubWorker Concurrency Settings

```csharp
using DurableTask.Core;
using DurableTask.SqlServer;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;

namespace Optimization.Concurrency;

/// <summary>
/// Optimal TaskHubWorker configuration for different scenarios.
/// </summary>
public static class WorkerConfigurationFactory
{
    /// <summary>
    /// High-throughput configuration for processing many small tasks.
    /// </summary>
    public static TaskHubWorker CreateHighThroughputWorker(
        string connectionString,
        ILoggerFactory loggerFactory)
    {
        var settings = new SqlOrchestrationServiceSettings
        {
            TaskOrchestrationLockTimeout = TimeSpan.FromMinutes(5),
            TaskActivityLockTimeout = TimeSpan.FromMinutes(5),
            
            // Fetch many work items at once
            WorkItemBatchSize = 100,
            
            // Poll frequently
            WorkItemLockTimeout = TimeSpan.FromSeconds(30),
            
            // Maximum messages to fetch per iteration
            MaxActiveOrchestrations = 200,
            MaxActiveActivities = 500
        };

        var service = new SqlOrchestrationService(settings);
        
        var worker = new TaskHubWorker(service, loggerFactory)
        {
            // High concurrency limits
            MaxConcurrentTaskOrchestrations = 50,
            MaxConcurrentTaskActivities = 100,
            
            ErrorPropagationMode = ErrorPropagationMode.UseFailureDetails
        };

        return worker;
    }

    /// <summary>
    /// Memory-conscious configuration for long-running tasks.
    /// </summary>
    public static TaskHubWorker CreateLowMemoryWorker(
        string connectionString,
        ILoggerFactory loggerFactory)
    {
        var settings = new SqlOrchestrationServiceSettings
        {
            TaskOrchestrationLockTimeout = TimeSpan.FromMinutes(30),
            TaskActivityLockTimeout = TimeSpan.FromMinutes(30),
            
            // Fetch fewer work items
            WorkItemBatchSize = 10,
            
            // Conservative limits
            MaxActiveOrchestrations = 20,
            MaxActiveActivities = 50
        };

        var service = new SqlOrchestrationService(settings);
        
        var worker = new TaskHubWorker(service, loggerFactory)
        {
            // Lower concurrency to reduce memory pressure
            MaxConcurrentTaskOrchestrations = 5,
            MaxConcurrentTaskActivities = 10,
            
            ErrorPropagationMode = ErrorPropagationMode.UseFailureDetails
        };

        return worker;
    }

    /// <summary>
    /// Balanced configuration for general use.
    /// </summary>
    public static TaskHubWorker CreateBalancedWorker(
        string connectionString,
        ILoggerFactory loggerFactory)
    {
        var settings = new SqlOrchestrationServiceSettings
        {
            TaskOrchestrationLockTimeout = TimeSpan.FromMinutes(10),
            TaskActivityLockTimeout = TimeSpan.FromMinutes(10),
            
            WorkItemBatchSize = 50,
            WorkItemLockTimeout = TimeSpan.FromMinutes(1),
            
            MaxActiveOrchestrations = 100,
            MaxActiveActivities = 200
        };

        var service = new SqlOrchestrationService(settings);
        
        var worker = new TaskHubWorker(service, loggerFactory)
        {
            MaxConcurrentTaskOrchestrations = 20,
            MaxConcurrentTaskActivities = 40,
            
            ErrorPropagationMode = ErrorPropagationMode.UseFailureDetails
        };

        return worker;
    }
}
```

### Dynamic Concurrency Control

```csharp
using DurableTask.Core;
using System.Diagnostics;

namespace Optimization.Concurrency;

/// <summary>
/// Orchestration with dynamic parallelism based on load.
/// </summary>
public sealed class AdaptiveConcurrencyOrchestration : TaskOrchestration<string, AdaptiveRequest>
{
    public override async Task<string> RunTask(
        OrchestrationContext context, 
        AdaptiveRequest input)
    {
        // Measure system load
        var systemLoad = await context.ScheduleTask<SystemLoadInfo>(
            typeof(GetSystemLoadActivity),
            null);

        // Adjust parallelism based on load
        var degreeOfParallelism = CalculateOptimalParallelism(systemLoad);

        // Process items in batches
        var batches = input.Items
            .Select((item, index) => new { item, index })
            .GroupBy(x => x.index / degreeOfParallelism)
            .Select(g => g.Select(x => x.item).ToArray());

        var totalProcessed = 0;

        foreach (var batch in batches)
        {
            var tasks = batch.Select(item =>
                context.ScheduleTask<bool>(typeof(ProcessItemActivity), item)
            ).ToArray();

            await Task.WhenAll(tasks);
            totalProcessed += batch.Length;
        }

        return $"Processed {totalProcessed} items with parallelism {degreeOfParallelism}";
    }

    private static int CalculateOptimalParallelism(SystemLoadInfo load)
    {
        return load.CpuUsagePercent switch
        {
            < 30 => 100,  // Low load - high parallelism
            < 60 => 50,   // Medium load - moderate parallelism
            < 80 => 20,   // High load - low parallelism
            _ => 10       // Very high load - minimal parallelism
        };
    }
}

public sealed record AdaptiveRequest
{
    public required string[] Items { get; init; }
}

public sealed record SystemLoadInfo
{
    public required double CpuUsagePercent { get; init; }
    public required double MemoryUsagePercent { get; init; }
}

public sealed class GetSystemLoadActivity : TaskActivity<object?, SystemLoadInfo>
{
    protected override SystemLoadInfo Execute(TaskContext context, object? input)
    {
        var cpuCounter = new PerformanceCounter("Processor", "% Processor Time", "_Total");
        var memCounter = new PerformanceCounter("Memory", "% Committed Bytes In Use");

        return new SystemLoadInfo
        {
            CpuUsagePercent = cpuCounter.NextValue(),
            MemoryUsagePercent = memCounter.NextValue()
        };
    }
}
```

### Batched Activity Execution

```csharp
using DurableTask.Core;

namespace Optimization.Concurrency;

/// <summary>
/// Batch multiple items into single activity call for efficiency.
/// </summary>
public sealed class BatchedActivityOrchestration : TaskOrchestration<BatchSummary, BatchRequest>
{
    private const int OptimalBatchSize = 50;

    public override async Task<BatchSummary> RunTask(
        OrchestrationContext context, 
        BatchRequest input)
    {
        // Split items into optimal batch sizes
        var batches = input.Items
            .Select((item, index) => new { item, index })
            .GroupBy(x => x.index / OptimalBatchSize)
            .Select(g => g.Select(x => x.item).ToArray())
            .ToArray();

        // Process batches in parallel
        var batchTasks = batches.Select(batch =>
            context.ScheduleTask<BatchResult>(
                typeof(ProcessBatchActivity),
                batch)
        ).ToArray();

        var results = await Task.WhenAll(batchTasks);

        return new BatchSummary
        {
            TotalBatches = results.Length,
            TotalItems = input.Items.Length,
            SuccessCount = results.Sum(r => r.SuccessCount),
            FailureCount = results.Sum(r => r.FailureCount)
        };
    }
}

/// <summary>
/// Activity that processes multiple items in one execution.
/// </summary>
public sealed class ProcessBatchActivity : TaskActivity<string[], BatchResult>
{
    protected override BatchResult Execute(TaskContext context, string[] input)
    {
        var successCount = 0;
        var failureCount = 0;

        foreach (var item in input)
        {
            try
            {
                // Process item
                ProcessSingleItem(item);
                successCount++;
            }
            catch
            {
                failureCount++;
            }
        }

        return new BatchResult
        {
            SuccessCount = successCount,
            FailureCount = failureCount
        };
    }

    private static void ProcessSingleItem(string item)
    {
        // Processing logic
    }
}

public sealed record BatchRequest
{
    public required string[] Items { get; init; }
}

public sealed record BatchResult
{
    public required int SuccessCount { get; init; }
    public required int FailureCount { get; init; }
}

public sealed record BatchSummary
{
    public required int TotalBatches { get; init; }
    public required int TotalItems { get; init; }
    public required int SuccessCount { get; init; }
    public required int FailureCount { get; init; }
}
```

---

## SQL Server Optimizations

### Connection Pooling

```csharp
using DurableTask.SqlServer;
using Microsoft.Data.SqlClient;

namespace Optimization.SqlServer;

/// <summary>
/// Optimized SQL Server connection configuration.
/// </summary>
public static class ConnectionStringBuilder
{
    public static string BuildOptimizedConnectionString(
        string server,
        string database,
        string userId,
        string password)
    {
        var builder = new SqlConnectionStringBuilder
        {
            DataSource = server,
            InitialCatalog = database,
            UserID = userId,
            Password = password,
            
            // Connection pooling settings
            Pooling = true,
            MinPoolSize = 5,
            MaxPoolSize = 100,
            
            // Performance settings
            ConnectTimeout = 30,
            CommandTimeout = 300, // 5 minutes for long-running queries
            
            // Reliability
            ConnectRetryCount = 3,
            ConnectRetryInterval = 10,
            
            // Security
            Encrypt = true,
            TrustServerCertificate = false,
            
            // Performance optimizations
            MultipleActiveResultSets = true,
            ApplicationName = "DurableTask.Worker",
            
            // Network performance
            PacketSize = 8192 // Default, can be tuned
        };

        return builder.ConnectionString;
    }

    public static string BuildHighThroughputConnectionString(
        string server,
        string database,
        string userId,
        string password)
    {
        var builder = new SqlConnectionStringBuilder
        {
            DataSource = server,
            InitialCatalog = database,
            UserID = userId,
            Password = password,
            
            // Aggressive pooling for high throughput
            Pooling = true,
            MinPoolSize = 20,
            MaxPoolSize = 500,
            
            // Shorter timeouts for faster failure detection
            ConnectTimeout = 15,
            CommandTimeout = 120,
            
            // Enable MARS for concurrent queries
            MultipleActiveResultSets = true,
            
            ApplicationName = "DurableTask.HighThroughput"
        };

        return builder.ConnectionString;
    }
}
```

### Index Optimization Queries

```sql
-- 01-OPTIMIZE-INDEXES.sql
-- Run these queries to optimize DTFx SQL Server performance

-- Check missing indexes
SELECT 
    OBJECT_NAME(d.object_id) AS TableName,
    d.equality_columns,
    d.inequality_columns,
    d.included_columns,
    s.avg_total_user_cost * s.avg_user_impact * (s.user_seeks + s.user_scans) AS ImprovementMeasure
FROM sys.dm_db_missing_index_details d
INNER JOIN sys.dm_db_missing_index_groups g ON d.index_handle = g.index_handle
INNER JOIN sys.dm_db_missing_index_group_stats s ON g.index_group_handle = s.group_handle
WHERE d.database_id = DB_ID()
    AND OBJECT_NAME(d.object_id) LIKE '%OrchestrationState%'
ORDER BY ImprovementMeasure DESC;

-- Check index fragmentation
SELECT 
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 10
    AND ips.page_count > 1000
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- Rebuild fragmented indexes
ALTER INDEX ALL ON dt.OrchestrationStateHistory REBUILD 
    WITH (ONLINE = ON, SORT_IN_TEMPDB = ON, MAXDOP = 4);

ALTER INDEX ALL ON dt.OrchestrationState REBUILD 
    WITH (ONLINE = ON, SORT_IN_TEMPDB = ON, MAXDOP = 4);

-- Update statistics
UPDATE STATISTICS dt.OrchestrationState WITH FULLSCAN;
UPDATE STATISTICS dt.OrchestrationStateHistory WITH FULLSCAN;
UPDATE STATISTICS dt.WorkItem WITH FULLSCAN;
```

### Database Maintenance Strategy

```csharp
using DurableTask.SqlServer;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Optimization.SqlServer;

/// <summary>
/// Background service for database maintenance tasks.
/// </summary>
public sealed class DatabaseMaintenanceService : BackgroundService
{
    private readonly string _connectionString;
    private readonly ILogger<DatabaseMaintenanceService> _logger;
    private readonly TimeSpan _maintenanceInterval = TimeSpan.FromHours(24);

    public DatabaseMaintenanceService(
        string connectionString,
        ILogger<DatabaseMaintenanceService> logger)
    {
        _connectionString = connectionString;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await PerformMaintenance(stoppingToken);
                await Task.Delay(_maintenanceInterval, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Database maintenance failed");
                await Task.Delay(TimeSpan.FromHours(1), stoppingToken);
            }
        }
    }

    private async Task PerformMaintenance(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Starting database maintenance");

        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        // 1. Archive old orchestration history
        await ArchiveOldHistory(connection, cancellationToken);

        // 2. Clean up completed orchestrations
        await CleanupCompletedOrchestrations(connection, cancellationToken);

        // 3. Rebuild indexes
        await RebuildIndexes(connection, cancellationToken);

        // 4. Update statistics
        await UpdateStatistics(connection, cancellationToken);

        _logger.LogInformation("Database maintenance completed");
    }

    private async Task ArchiveOldHistory(
        SqlConnection connection, 
        CancellationToken cancellationToken)
    {
        var cutoffDate = DateTime.UtcNow.AddDays(-90); // Archive history older than 90 days

        var command = new SqlCommand(@"
            INSERT INTO dt.OrchestrationStateArchive 
            SELECT * FROM dt.OrchestrationStateHistory 
            WHERE CompletedTime < @CutoffDate;
            
            DELETE FROM dt.OrchestrationStateHistory 
            WHERE CompletedTime < @CutoffDate;
        ", connection);

        command.Parameters.AddWithValue("@CutoffDate", cutoffDate);
        command.CommandTimeout = 600; // 10 minutes

        var rowsAffected = await command.ExecuteNonQueryAsync(cancellationToken);
        _logger.LogInformation("Archived {RowCount} history rows", rowsAffected);
    }

    private async Task CleanupCompletedOrchestrations(
        SqlConnection connection, 
        CancellationToken cancellationToken)
    {
        var cutoffDate = DateTime.UtcNow.AddDays(-30); // Keep 30 days

        var command = new SqlCommand(@"
            DELETE FROM dt.OrchestrationState 
            WHERE OrchestrationStatus IN ('Completed', 'Failed', 'Terminated')
                AND CompletedTime < @CutoffDate;
        ", connection);

        command.Parameters.AddWithValue("@CutoffDate", cutoffDate);
        command.CommandTimeout = 600;

        var rowsAffected = await command.ExecuteNonQueryAsync(cancellationToken);
        _logger.LogInformation("Cleaned up {RowCount} completed orchestrations", rowsAffected);
    }

    private async Task RebuildIndexes(
        SqlConnection connection, 
        CancellationToken cancellationToken)
    {
        var command = new SqlCommand(@"
            ALTER INDEX ALL ON dt.OrchestrationState REBUILD 
                WITH (ONLINE = ON, SORT_IN_TEMPDB = ON, MAXDOP = 4);
            
            ALTER INDEX ALL ON dt.OrchestrationStateHistory REBUILD 
                WITH (ONLINE = ON, SORT_IN_TEMPDB = ON, MAXDOP = 4);
        ", connection);

        command.CommandTimeout = 1800; // 30 minutes

        await command.ExecuteNonQueryAsync(cancellationToken);
        _logger.LogInformation("Rebuilt indexes");
    }

    private async Task UpdateStatistics(
        SqlConnection connection, 
        CancellationToken cancellationToken)
    {
        var command = new SqlCommand(@"
            UPDATE STATISTICS dt.OrchestrationState WITH FULLSCAN;
            UPDATE STATISTICS dt.OrchestrationStateHistory WITH FULLSCAN;
            UPDATE STATISTICS dt.WorkItem WITH FULLSCAN;
        ", connection);

        command.CommandTimeout = 600;

        await command.ExecuteNonQueryAsync(cancellationToken);
        _logger.LogInformation("Updated statistics");
    }
}
```

### Query Performance Monitoring

```csharp
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;

namespace Optimization.SqlServer;

/// <summary>
/// Monitor slow queries and performance metrics.
/// </summary>
public sealed class QueryPerformanceMonitor
{
    private readonly string _connectionString;
    private readonly ILogger<QueryPerformanceMonitor> _logger;

    public QueryPerformanceMonitor(
        string connectionString,
        ILogger<QueryPerformanceMonitor> logger)
    {
        _connectionString = connectionString;
        _logger = logger;
    }

    public async Task<SlowQueryReport> GetSlowQueries(TimeSpan threshold)
    {
        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync();

        var command = new SqlCommand(@"
            SELECT TOP 20
                qs.execution_count,
                qs.total_elapsed_time / 1000000.0 AS total_elapsed_time_sec,
                qs.total_elapsed_time / qs.execution_count / 1000000.0 AS avg_elapsed_time_sec,
                SUBSTRING(qt.text, (qs.statement_start_offset/2)+1,
                    ((CASE qs.statement_end_offset
                        WHEN -1 THEN DATALENGTH(qt.text)
                        ELSE qs.statement_end_offset
                    END - qs.statement_start_offset)/2)+1) AS query_text
            FROM sys.dm_exec_query_stats qs
            CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
            WHERE qt.text LIKE '%dt.OrchestrationState%'
                AND qs.total_elapsed_time / qs.execution_count > @ThresholdMicroseconds
            ORDER BY qs.total_elapsed_time / qs.execution_count DESC;
        ", connection);

        command.Parameters.AddWithValue("@ThresholdMicroseconds", 
            threshold.TotalMilliseconds * 1000);

        var slowQueries = new List<SlowQueryInfo>();

        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            slowQueries.Add(new SlowQueryInfo
            {
                ExecutionCount = reader.GetInt64(0),
                TotalElapsedSeconds = reader.GetDouble(1),
                AvgElapsedSeconds = reader.GetDouble(2),
                QueryText = reader.GetString(3)
            });
        }

        return new SlowQueryReport
        {
            Threshold = threshold,
            SlowQueries = slowQueries.ToArray()
        };
    }
}

public sealed record SlowQueryInfo
{
    public required long ExecutionCount { get; init; }
    public required double TotalElapsedSeconds { get; init; }
    public required double AvgElapsedSeconds { get; init; }
    public required string QueryText { get; init; }
}

public sealed record SlowQueryReport
{
    public required TimeSpan Threshold { get; init; }
    public required SlowQueryInfo[] SlowQueries { get; init; }
}
```

---

## Activity vs Sub-Orchestration Performance

### Performance Comparison

```csharp
using DurableTask.Core;
using System.Diagnostics;

namespace Optimization.Performance;

/// <summary>
/// Benchmark activity vs sub-orchestration performance.
/// </summary>
public sealed class PerformanceComparisonOrchestration : TaskOrchestration<PerformanceReport, int>
{
    public override async Task<PerformanceReport> RunTask(
        OrchestrationContext context, 
        int itemCount)
    {
        var stopwatch = Stopwatch.StartNew();

        // Test 1: Activities
        var activityStart = stopwatch.ElapsedMilliseconds;
        for (int i = 0; i < itemCount; i++)
        {
            await context.ScheduleTask<bool>(
                typeof(SimpleActivity), 
                i);
        }
        var activityDuration = stopwatch.ElapsedMilliseconds - activityStart;

        // Test 2: Sub-Orchestrations
        var subOrchStart = stopwatch.ElapsedMilliseconds;
        for (int i = 0; i < itemCount; i++)
        {
            await context.CreateSubOrchestrationInstance<bool>(
                typeof(SimpleOrchestration),
                $"{context.OrchestrationInstance.InstanceId}:SubOrch{i}",
                i);
        }
        var subOrchDuration = stopwatch.ElapsedMilliseconds - subOrchStart;

        return new PerformanceReport
        {
            ItemCount = itemCount,
            ActivityDurationMs = activityDuration,
            SubOrchestrationDurationMs = subOrchDuration,
            SpeedupRatio = (double)subOrchDuration / activityDuration
        };
    }
}

public sealed record PerformanceReport
{
    public required int ItemCount { get; init; }
    public required long ActivityDurationMs { get; init; }
    public required long SubOrchestrationDurationMs { get; init; }
    public required double SpeedupRatio { get; init; }
}

public sealed class SimpleActivity : TaskActivity<int, bool>
{
    protected override bool Execute(TaskContext context, int input)
    {
        // Simple processing
        return true;
    }
}

public sealed class SimpleOrchestration : TaskOrchestration<bool, int>
{
    public override Task<bool> RunTask(OrchestrationContext context, int input)
    {
        return Task.FromResult(true);
    }
}
```

### Decision Matrix

| Criteria | Use Activity | Use Sub-Orchestration |
|----------|-------------|----------------------|
| **Operation Complexity** | Simple, single-step | Multi-step workflow |
| **Retry Granularity** | Retry entire operation | Retry individual steps |
| **History Size** | Small (1-2 events) | Separate instance (reduces parent history) |
| **Performance** | Fast (~10ms overhead) | Slower (~50-100ms overhead) |
| **Reusability** | Reusable function | Reusable workflow |
| **Orchestration Lifecycle** | Tied to parent | Independent (can outlive parent) |
| **Example Use Cases** | API calls, DB queries, file I/O | Payment processing, approval flows, multi-step validation |

---

## Batching Strategies

### Intelligent Batch Sizing

```csharp
using DurableTask.Core;

namespace Optimization.Batching;

/// <summary>
/// Dynamically determine optimal batch size based on item complexity.
/// </summary>
public sealed class AdaptiveBatchingOrchestration : TaskOrchestration<string, ProcessingRequest>
{
    public override async Task<string> RunTask(
        OrchestrationContext context, 
        ProcessingRequest input)
    {
        // Sample first item to determine complexity
        var sampleResult = await context.ScheduleTask<ProcessingMetrics>(
            typeof(AnalyzeComplexityActivity),
            input.Items.First());

        // Calculate optimal batch size
        var batchSize = CalculateOptimalBatchSize(sampleResult);

        // Process in batches
        var batches = input.Items
            .Select((item, index) => new { item, index })
            .GroupBy(x => x.index / batchSize)
            .Select(g => g.Select(x => x.item).ToArray());

        var results = new List<int>();

        foreach (var batch in batches)
        {
            var batchResult = await context.ScheduleTask<int>(
                typeof(ProcessBatchActivity),
                batch);
            
            results.Add(batchResult);
        }

        return $"Processed {input.Items.Length} items in {results.Count} batches of size {batchSize}";
    }

    private static int CalculateOptimalBatchSize(ProcessingMetrics metrics)
    {
        return metrics.EstimatedDurationMs switch
        {
            < 100 => 100,   // Fast items - large batches
            < 500 => 50,    // Medium items - medium batches
            < 2000 => 20,   // Slow items - small batches
            _ => 10         // Very slow items - tiny batches
        };
    }
}

public sealed record ProcessingRequest
{
    public required string[] Items { get; init; }
}

public sealed record ProcessingMetrics
{
    public required long EstimatedDurationMs { get; init; }
    public required long MemoryUsageBytes { get; init; }
}
```

---

## Performance Monitoring

### Instrumentation

```csharp
using DurableTask.Core;
using System.Diagnostics;
using System.Diagnostics.Metrics;
using Microsoft.Extensions.Logging;

namespace Optimization.Monitoring;

/// <summary>
/// Orchestration with comprehensive performance monitoring.
/// </summary>
public sealed class InstrumentedOrchestration : TaskOrchestration<string, WorkRequest>
{
    private static readonly Meter Meter = new("DurableTask.Orchestrations");
    private static readonly Counter<long> OrchestrationCounter = 
        Meter.CreateCounter<long>("orchestrations_executed");
    private static readonly Histogram<double> OrchestrationDuration = 
        Meter.CreateHistogram<double>("orchestration_duration_ms");

    public override async Task<string> RunTask(
        OrchestrationContext context, 
        WorkRequest input)
    {
        var stopwatch = Stopwatch.StartNew();
        
        using var activity = new Activity("ProcessWorkOrchestration")
            .AddTag("orchestration.instance_id", context.OrchestrationInstance.InstanceId)
            .AddTag("orchestration.name", nameof(InstrumentedOrchestration))
            .Start();

        try
        {
            await context.ScheduleTask<bool>(typeof(ProcessWorkActivity), input);
            
            OrchestrationCounter.Add(1, 
                new KeyValuePair<string, object?>("status", "success"));
            
            return "Success";
        }
        catch (Exception ex)
        {
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            
            OrchestrationCounter.Add(1, 
                new KeyValuePair<string, object?>("status", "failed"));
            
            throw;
        }
        finally
        {
            stopwatch.Stop();
            OrchestrationDuration.Record(stopwatch.ElapsedMilliseconds);
        }
    }
}

public sealed record WorkRequest
{
    public required string WorkId { get; init; }
}
```

---

## Production Optimization Checklist

### Pre-Deployment

- [ ] **History Management**
  - [ ] Implement ContinueAsNew for eternal orchestrations
  - [ ] Set history reset thresholds (100-500 iterations)
  - [ ] Use sub-orchestrations for large workflows

- [ ] **Serialization**
  - [ ] Configure optimized JsonDataConverter
  - [ ] Implement external storage for payloads > 50KB
  - [ ] Enable compression for large data

- [ ] **Concurrency**
  - [ ] Tune MaxConcurrentTaskOrchestrations (start with 20)
  - [ ] Tune MaxConcurrentTaskActivities (start with 40)
  - [ ] Configure WorkItemBatchSize (start with 50)

- [ ] **SQL Server**
  - [ ] Enable connection pooling (MinPoolSize=5, MaxPoolSize=100)
  - [ ] Set appropriate timeouts (ConnectTimeout=30, CommandTimeout=300)
  - [ ] Enable MARS (MultipleActiveResultSets=true)

### Post-Deployment

- [ ] **Database Maintenance**
  - [ ] Schedule daily index rebuilds
  - [ ] Archive old history (> 90 days)
  - [ ] Clean up completed orchestrations (> 30 days)
  - [ ] Update statistics weekly

- [ ] **Monitoring**
  - [ ] Track slow queries (> 1 second)
  - [ ] Monitor index fragmentation (> 30%)
  - [ ] Monitor connection pool usage
  - [ ] Track orchestration duration metrics

- [ ] **Performance Testing**
  - [ ] Load test with expected throughput
  - [ ] Stress test with 2x expected load
  - [ ] Monitor memory usage under load
  - [ ] Verify database growth rate

---

## Summary

This module covered:

✅ **History Management**: ContinueAsNew, pagination, monitoring  
✅ **Serialization**: Custom converters, compression, large payloads  
✅ **Concurrency**: Worker configuration, dynamic control, batching  
✅ **SQL Server**: Connection pooling, indexes, maintenance, monitoring  
✅ **Activity vs Sub-Orchestration**: Performance comparison, decision matrix  
✅ **Batching**: Adaptive sizing, intelligent batching  
✅ **Monitoring**: Instrumentation, metrics, performance tracking  

**Next**: [05-TESTING.md](./05-TESTING.md) - Comprehensive testing strategies and patterns.
