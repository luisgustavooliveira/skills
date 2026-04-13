# 08 - TROUBLESHOOTING & DIAGNOSTICS

**Comprehensive guide to diagnosing and resolving common DurableTask issues, performance problems, and production incidents.**

---

## Table of Contents

1. [Common Error Messages](#common-error-messages)
2. [Non-Determinism Issues](#non-determinism-issues)
3. [Performance Problems](#performance-problems)
4. [Database Issues](#database-issues)
5. [Serialization Problems](#serialization-problems)
6. [Stuck Orchestrations](#stuck-orchestrations)
7. [Version Mismatch Scenarios](#version-mismatch-scenarios)
8. [Connection Pool Exhaustion](#connection-pool-exhaustion)
9. [Debug Queries](#debug-queries)
10. [Production Incident Playbook](#production-incident-playbook)

---

## Common Error Messages

### Error: "TaskScheduler exception: Object reference not set to an instance of an object"

**Cause**: Activity returned `null` when non-nullable type expected.

**Solution**:
```csharp
// ❌ WRONG
public sealed class MyActivity : TaskActivity<string, string>
{
    protected override string Execute(TaskContext context, string input)
    {
        return null!; // This will cause NullReferenceException
    }
}

// ✅ CORRECT
public sealed class MyActivity : TaskActivity<string, string>
{
    protected override string Execute(TaskContext context, string input)
    {
        if (string.IsNullOrEmpty(input))
        {
            throw new ArgumentException("Input cannot be null or empty");
        }
        
        return ProcessInput(input);
    }
}
```

### Error: "Non-deterministic workflow detected"

**Cause**: Orchestration behavior changed between replays.

**Solution**: See [Non-Determinism Issues](#non-determinism-issues) section.

### Error: "Orchestration history is missing or corrupt"

**Cause**: History table data deleted or database corruption.

**Solution**:
```sql
-- Check for orphaned work items
SELECT wi.*
FROM dt.WorkItem wi
LEFT JOIN dt.OrchestrationState os 
    ON wi.InstanceId = os.InstanceId
WHERE os.InstanceId IS NULL;

-- Check for instances without history
SELECT os.InstanceId, os.Name, os.Status
FROM dt.OrchestrationState os
LEFT JOIN dt.OrchestrationStateHistory h 
    ON os.InstanceId = h.InstanceId
WHERE h.InstanceId IS NULL
    AND os.Status = 'Running';

-- If history is truly lost, terminate affected orchestrations
UPDATE dt.OrchestrationState
SET Status = 'Terminated',
    Output = 'Terminated due to missing history',
    CompletedTime = GETUTCDATE()
WHERE InstanceId IN (
    SELECT os.InstanceId
    FROM dt.OrchestrationState os
    LEFT JOIN dt.OrchestrationStateHistory h 
        ON os.InstanceId = h.InstanceId
    WHERE h.InstanceId IS NULL
        AND os.Status = 'Running'
);
```

### Error: "Timeout waiting for lock on work item"

**Cause**: High contention or long-running activities holding locks.

**Solution**:
```csharp
// Adjust lock timeout in settings
var settings = new SqlOrchestrationServiceSettings
{
    TaskActivityLockTimeout = TimeSpan.FromMinutes(30), // Increase timeout
    WorkItemLockTimeout = TimeSpan.FromMinutes(5)
};
```

```sql
-- Find work items locked too long
SELECT 
    WorkItemId,
    InstanceId,
    Type,
    Name,
    LockedUntil,
    DATEDIFF(MINUTE, CreatedTime, GETUTCDATE()) AS MinutesLocked,
    DequeueCount
FROM dt.WorkItem
WHERE LockedUntil > GETUTCDATE()
    AND DATEDIFF(HOUR, CreatedTime, GETUTCDATE()) > 1
ORDER BY MinutesLocked DESC;

-- Force unlock (use with caution)
UPDATE dt.WorkItem
SET LockedUntil = NULL
WHERE LockedUntil < DATEADD(HOUR, -2, GETUTCDATE());
```

---

## Non-Determinism Issues

### Detecting Non-Deterministic Code

```csharp
using DurableTask.Core;

namespace Troubleshooting.Determinism;

/// <summary>
/// Common non-deterministic mistakes and how to fix them.
/// </summary>
public sealed class NonDeterministicExamples
{
    public async Task<string> WrongExamples(OrchestrationContext context)
    {
        // ❌ WRONG: DateTime.UtcNow
        var now = DateTime.UtcNow; // Non-deterministic!
        
        // ✅ CORRECT: Use context.CurrentUtcDateTime
        var correctNow = context.CurrentUtcDateTime;

        // ❌ WRONG: Guid.NewGuid()
        var id = Guid.NewGuid(); // Non-deterministic!
        
        // ✅ CORRECT: Use context.NewGuid()
        var correctId = context.NewGuid();

        // ❌ WRONG: Random
        var random = new Random();
        var value = random.Next(); // Non-deterministic!
        
        // ✅ CORRECT: Use activity to generate random value
        var correctValue = await context.ScheduleTask<int>(
            typeof(GenerateRandomActivity),
            null);

        // ❌ WRONG: Thread.Sleep or Task.Delay
        await Task.Delay(1000); // Non-deterministic!
        
        // ✅ CORRECT: Use CreateTimer
        await context.CreateTimer(
            context.CurrentUtcDateTime.AddSeconds(1),
            CancellationToken.None);

        // ❌ WRONG: HTTP call directly
        using var httpClient = new HttpClient();
        var response = await httpClient.GetStringAsync("https://api.example.com"); // Non-deterministic!
        
        // ✅ CORRECT: Use activity for external calls
        var correctResponse = await context.ScheduleTask<string>(
            typeof(CallExternalApiActivity),
            "https://api.example.com");

        // ❌ WRONG: Database query directly
        // var result = await dbContext.Orders.FirstOrDefaultAsync(); // Non-deterministic!
        
        // ✅ CORRECT: Use activity for database access
        var correctResult = await context.ScheduleTask<Order>(
            typeof(GetOrderActivity),
            orderId);

        return "Example completed";
    }
}
```

### Debugging Non-Determinism

```csharp
using DurableTask.Core;
using Microsoft.Extensions.Logging;

namespace Troubleshooting.Determinism;

/// <summary>
/// Orchestration with determinism debugging.
/// </summary>
public sealed class DebugDeterminismOrchestration : TaskOrchestration<string, string>
{
    private readonly ILogger<DebugDeterminismOrchestration> _logger;

    public DebugDeterminismOrchestration(ILogger<DebugDeterminismOrchestration> logger)
    {
        _logger = logger;
    }

    public override async Task<string> RunTask(OrchestrationContext context, string input)
    {
        // Log every decision point for replay analysis
        _logger.LogInformation(
            "Orchestration started - InstanceId: {InstanceId}, IsReplaying: {IsReplaying}",
            context.OrchestrationInstance.InstanceId,
            context.IsReplaying);

        var step1Result = await context.ScheduleTask<string>(
            typeof(Step1Activity),
            input);

        _logger.LogInformation(
            "Step 1 completed - Result: {Result}, IsReplaying: {IsReplaying}",
            step1Result,
            context.IsReplaying);

        var step2Result = await context.ScheduleTask<string>(
            typeof(Step2Activity),
            step1Result);

        _logger.LogInformation(
            "Step 2 completed - Result: {Result}, IsReplaying: {IsReplaying}",
            step2Result,
            context.IsReplaying);

        return step2Result;
    }
}
```

### Replay Validation Tool

```csharp
using DurableTask.Core;
using Microsoft.Data.SqlClient;
using System.Text.Json;

namespace Troubleshooting.Tools;

/// <summary>
/// Tool to validate orchestration replay behavior.
/// </summary>
public sealed class ReplayValidator
{
    private readonly string _connectionString;

    public ReplayValidator(string connectionString)
    {
        _connectionString = connectionString;
    }

    public async Task<ReplayValidationResult> ValidateReplayAsync(string instanceId)
    {
        // Get history events
        var events = await GetHistoryEvents(instanceId);

        if (events.Count == 0)
        {
            return ReplayValidationResult.NoHistory();
        }

        // Check for common non-determinism patterns
        var issues = new List<string>();

        // Check for timer events with inconsistent fire times
        var timerEvents = events.Where(e => e.EventType == "TimerFired").ToList();
        if (timerEvents.Any())
        {
            // Validate timer consistency
            // ... implementation
        }

        // Check for activity results that changed
        var activityEvents = events.Where(e => 
            e.EventType == "TaskCompleted" || 
            e.EventType == "TaskFailed").ToList();
        
        // Group by sequence to detect changes across replays
        var activityGroups = activityEvents.GroupBy(e => e.SequenceNumber).ToList();
        
        foreach (var group in activityGroups)
        {
            if (group.Count() > 1)
            {
                var results = group.Select(e => e.Result).Distinct().ToList();
                if (results.Count > 1)
                {
                    issues.Add($"Activity at sequence {group.Key} returned different results across replays");
                }
            }
        }

        return new ReplayValidationResult
        {
            IsValid = issues.Count == 0,
            Issues = issues.ToArray(),
            TotalEvents = events.Count
        };
    }

    private async Task<List<HistoryEvent>> GetHistoryEvents(string instanceId)
    {
        var events = new List<HistoryEvent>();

        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync();

        var command = new SqlCommand(@"
            SELECT SequenceNumber, EventType, Name, Input, Result, Timestamp
            FROM dt.OrchestrationStateHistory
            WHERE InstanceId = @InstanceId
            ORDER BY SequenceNumber
        ", connection);

        command.Parameters.AddWithValue("@InstanceId", instanceId);

        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            events.Add(new HistoryEvent
            {
                SequenceNumber = reader.GetInt32(0),
                EventType = reader.GetString(1),
                Name = reader.IsDBNull(2) ? null : reader.GetString(2),
                Input = reader.IsDBNull(3) ? null : reader.GetString(3),
                Result = reader.IsDBNull(4) ? null : reader.GetString(4),
                Timestamp = reader.GetDateTime(5)
            });
        }

        return events;
    }
}

public sealed record HistoryEvent
{
    public required int SequenceNumber { get; init; }
    public required string EventType { get; init; }
    public string? Name { get; init; }
    public string? Input { get; init; }
    public string? Result { get; init; }
    public DateTime Timestamp { get; init; }
}

public sealed record ReplayValidationResult
{
    public required bool IsValid { get; init; }
    public required string[] Issues { get; init; }
    public required int TotalEvents { get; init; }

    public static ReplayValidationResult NoHistory() => new()
    {
        IsValid = false,
        Issues = new[] { "No history found" },
        TotalEvents = 0
    };
}
```

---

## Performance Problems

### Symptom: Slow Orchestration Execution

**Diagnosis**:
```sql
-- Find orchestrations with long duration
SELECT TOP 20
    InstanceId,
    Name,
    Status,
    CreatedTime,
    CompletedTime,
    DATEDIFF(SECOND, CreatedTime, ISNULL(CompletedTime, GETUTCDATE())) AS DurationSeconds
FROM dt.OrchestrationState
WHERE CreatedTime > DATEADD(DAY, -7, GETUTCDATE())
ORDER BY DurationSeconds DESC;

-- Find activities taking longest
SELECT 
    h.Name AS ActivityName,
    COUNT(*) AS ExecutionCount,
    AVG(DATEDIFF(MILLISECOND, 
        h1.Timestamp, 
        h2.Timestamp)) AS AvgDurationMs,
    MAX(DATEDIFF(MILLISECOND, 
        h1.Timestamp, 
        h2.Timestamp)) AS MaxDurationMs
FROM dt.OrchestrationStateHistory h1
INNER JOIN dt.OrchestrationStateHistory h2
    ON h1.InstanceId = h2.InstanceId
    AND h1.ExecutionId = h2.ExecutionId
    AND h1.SequenceNumber + 1 = h2.SequenceNumber
WHERE h1.EventType = 'TaskScheduled'
    AND h2.EventType IN ('TaskCompleted', 'TaskFailed')
    AND h1.Timestamp > DATEADD(DAY, -7, GETUTCDATE())
GROUP BY h.Name
ORDER BY AvgDurationMs DESC;
```

**Solutions**:
1. **Optimize slow activities** - profile and optimize activity code
2. **Increase parallelism** - use fan-out/fan-in pattern
3. **Add caching** - cache expensive operations in activities
4. **Tune concurrency settings** - increase `MaxConcurrentTaskActivities`

### Symptom: High Database CPU

**Diagnosis**:
```sql
-- Find expensive queries
SELECT TOP 20
    qs.execution_count,
    qs.total_worker_time / 1000 AS total_cpu_time_ms,
    qs.total_worker_time / qs.execution_count / 1000 AS avg_cpu_time_ms,
    SUBSTRING(qt.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(qt.text)
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2)+1) AS query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE qt.text LIKE '%dt.%'
ORDER BY qs.total_worker_time DESC;
```

**Solutions**:
1. **Add missing indexes** - check index usage
2. **Update statistics** - `UPDATE STATISTICS dt.OrchestrationState WITH FULLSCAN`
3. **Reduce work item batch size** - lower `WorkItemBatchSize`
4. **Archive old data** - move completed orchestrations to archive tables

### Symptom: Memory Leak

**Diagnosis**:
```csharp
// Monitor memory usage
var process = Process.GetCurrentProcess();
Console.WriteLine($"Working Set: {process.WorkingSet64 / 1024 / 1024} MB");
Console.WriteLine($"Private Memory: {process.PrivateMemorySize64 / 1024 / 1024} MB");
Console.WriteLine($"GC Total Memory: {GC.GetTotalMemory(false) / 1024 / 1024} MB");
```

**Common Causes**:
1. Large orchestration histories not cleaned up
2. Large input/output payloads stored in memory
3. Activities not disposing resources properly
4. Connection pool not properly configured

**Solutions**:
```csharp
// Use ContinueAsNew to reset history
if (iteration % 100 == 0)
{
    context.ContinueAsNew(input with { Iteration = iteration });
}

// Store large payloads externally
if (data.Length > 50_000)
{
    var blobId = await context.ScheduleTask<string>(
        typeof(StoreBlobActivity),
        data);
    // Use blobId instead of data
}

// Ensure activities dispose resources
public sealed class MyActivity : TaskActivity<string, string>
{
    protected override string Execute(TaskContext context, string input)
    {
        using var httpClient = new HttpClient();
        // ... use httpClient
        return result;
    } // Disposed here
}
```

---

## Database Issues

### Issue: Deadlocks

**Diagnosis**:
```sql
-- Enable deadlock trace flag
DBCC TRACEON (1222, -1);

-- View deadlock graph
SELECT 
    xdr.value('(victim-list/victimProcess)[1]/@id', 'varchar(50)') AS VictimProcess,
    xdr.query('.') AS DeadlockGraph
FROM (
    SELECT CAST(target_data AS XML) AS xmldata
    FROM sys.dm_xe_sessions s
    INNER JOIN sys.dm_xe_session_targets t 
        ON s.address = t.event_session_address
    WHERE s.name = 'system_health'
) AS deadlock_data
CROSS APPLY xmldata.nodes('/RingBufferTarget/event[@name="xml_deadlock_report"]') AS xdr(xdr)
WHERE CAST(xdr.query('.') AS NVARCHAR(MAX)) LIKE '%dt.%';
```

**Solutions**:
1. **Reduce lock duration** - optimize long-running queries
2. **Retry on deadlock** - DTFx already retries, but check retry settings
3. **Review indexes** - ensure proper index coverage

### Issue: Database Growth

**Diagnosis**:
```sql
-- Check database size and growth
SELECT 
    name AS FileName,
    size/128.0 AS CurrentSizeMB,
    size/128.0 - CAST(FILEPROPERTY(name, 'SpaceUsed') AS INT)/128.0 AS FreeSizeMB,
    CAST(FILEPROPERTY(name, 'SpaceUsed') AS INT)/128.0 AS UsedSizeMB
FROM sys.database_files
WHERE type_desc = 'ROWS';

-- Check table sizes
SELECT 
    t.name AS TableName,
    SUM(p.rows) AS RowCount,
    SUM(a.total_pages) * 8 / 1024 AS TotalSpaceMB,
    SUM(a.used_pages) * 8 / 1024 AS UsedSpaceMB
FROM sys.tables t
INNER JOIN sys.indexes i ON t.object_id = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.schema_id = SCHEMA_ID('dt')
GROUP BY t.name
ORDER BY TotalSpaceMB DESC;
```

**Solutions**:
1. **Archive old data** - move completed orchestrations to archive
2. **Purge old history** - delete history older than retention period
3. **Shrink database** - after archival (use with caution)

```sql
-- Archive and purge
DECLARE @CutoffDate DATETIME2 = DATEADD(DAY, -90, GETUTCDATE());

-- Archive
INSERT INTO dt.OrchestrationStateArchive
SELECT *, GETUTCDATE() AS ArchivedTime
FROM dt.OrchestrationState
WHERE Status IN ('Completed', 'Failed', 'Terminated')
    AND CompletedTime < @CutoffDate;

-- Delete archived
DELETE FROM dt.OrchestrationState
WHERE Status IN ('Completed', 'Failed', 'Terminated')
    AND CompletedTime < @CutoffDate;

-- Archive history
INSERT INTO dt.OrchestrationStateHistoryArchive
SELECT h.*, GETUTCDATE() AS ArchivedTime
FROM dt.OrchestrationStateHistory h
INNER JOIN dt.OrchestrationStateArchive a
    ON h.InstanceId = a.InstanceId;

DELETE h
FROM dt.OrchestrationStateHistory h
INNER JOIN dt.OrchestrationStateArchive a
    ON h.InstanceId = a.InstanceId;
```

---

## Serialization Problems

### Issue: "Error converting value"

**Cause**: JSON serialization/deserialization failed.

**Diagnosis**:
```csharp
// Test serialization
var input = new MyInput { /* ... */ };
var json = JsonSerializer.Serialize(input);
Console.WriteLine(json);

var deserialized = JsonSerializer.Deserialize<MyInput>(json);
// If this fails, there's a serialization issue
```

**Solutions**:
```csharp
// Ensure types are serializable
public sealed record MyInput
{
    // ✅ CORRECT: Public properties with getters and setters
    public required string Name { get; init; }
    public required int Value { get; init; }
    
    // ❌ WRONG: Private properties won't serialize
    // private string Secret { get; set; }
    
    // ❌ WRONG: Fields don't serialize by default
    // public string _field;
}

// Use JsonConverter for complex types
public sealed record ComplexInput
{
    [JsonConverter(typeof(CustomConverter))]
    public required CustomType Value { get; init; }
}
```

### Issue: Circular Reference

**Cause**: Object graph contains circular references.

**Solution**:
```csharp
// ❌ WRONG: Circular reference
public class Order
{
    public Customer Customer { get; set; }
}

public class Customer
{
    public List<Order> Orders { get; set; } // Circular!
}

// ✅ CORRECT: Break circular reference
public sealed record OrderDto
{
    public required string CustomerId { get; init; } // Reference by ID
    public required string OrderId { get; init; }
}

// Or use JsonIgnore
public class Customer
{
    [JsonIgnore]
    public List<Order> Orders { get; set; }
}
```

---

## Stuck Orchestrations

### Diagnosis

```sql
-- Find stuck orchestrations (running > 24 hours)
SELECT 
    InstanceId,
    Name,
    Status,
    CreatedTime,
    LastUpdatedTime,
    DATEDIFF(HOUR, LastUpdatedTime, GETUTCDATE()) AS HoursSinceUpdate,
    Input
FROM dt.OrchestrationState
WHERE Status IN ('Running', 'Pending')
    AND DATEDIFF(HOUR, LastUpdatedTime, GETUTCDATE()) > 24
ORDER BY LastUpdatedTime ASC;

-- Check if work items exist
SELECT wi.*
FROM dt.WorkItem wi
INNER JOIN dt.OrchestrationState os 
    ON wi.InstanceId = os.InstanceId
WHERE os.Status = 'Running'
    AND DATEDIFF(HOUR, os.LastUpdatedTime, GETUTCDATE()) > 24;
```

### Solutions

```sql
-- Option 1: Unlock work items
UPDATE dt.WorkItem
SET LockedUntil = NULL
WHERE InstanceId IN (
    SELECT InstanceId 
    FROM dt.OrchestrationState 
    WHERE Status = 'Running'
        AND DATEDIFF(HOUR, LastUpdatedTime, GETUTCDATE()) > 24
);

-- Option 2: Terminate stuck orchestrations
UPDATE dt.OrchestrationState
SET Status = 'Terminated',
    Output = 'Terminated due to timeout',
    CompletedTime = GETUTCDATE()
WHERE InstanceId IN (
    SELECT InstanceId 
    FROM dt.OrchestrationState 
    WHERE Status = 'Running'
        AND DATEDIFF(HOUR, LastUpdatedTime, GETUTCDATE()) > 48
);
```

---

## Version Mismatch Scenarios

### Issue: "Type not found" when loading orchestration

**Cause**: Orchestration renamed or moved to different namespace.

**Solution**:
```csharp
// Use [OrchestrationAlias] to maintain compatibility
[OrchestrationAlias("OldNamespace.OldOrchestrationName")]
public sealed class NewOrchestration : TaskOrchestration<string, string>
{
    public override Task<string> RunTask(OrchestrationContext context, string input)
    {
        // Implementation
        return Task.FromResult("OK");
    }
}
```

### Issue: Orchestration logic changed

**Solution**: Use versioning strategies from 03-ADVANCED.md:
- Side-by-side deployment
- Feature flags
- Version detection in orchestration code

---

## Connection Pool Exhaustion

### Symptoms
- `TimeoutException` when getting connection
- "Connection pool exhausted" errors
- High number of connections in SQL Server

### Diagnosis
```sql
-- Check active connections
SELECT 
    program_name,
    COUNT(*) AS ConnectionCount,
    MAX(login_time) AS LastConnectionTime
FROM sys.dm_exec_sessions
WHERE program_name LIKE '%DurableTask%'
GROUP BY program_name
ORDER BY ConnectionCount DESC;
```

### Solutions
```csharp
// Increase pool size
var builder = new SqlConnectionStringBuilder
{
    MaxPoolSize = 500, // Increase from default 100
    MinPoolSize = 20
};

// Ensure proper disposal of connections
public sealed class ProperDisposalActivity : TaskActivity<string, string>
{
    protected override string Execute(TaskContext context, string input)
    {
        using var connection = new SqlConnection(_connectionString);
        connection.Open();
        
        // Use connection
        
        return result;
    } // Connection disposed and returned to pool
}
```

---

## Debug Queries

### Comprehensive Diagnostic Query

```sql
-- Get complete orchestration state
DECLARE @InstanceId NVARCHAR(256) = 'your-instance-id';

-- Orchestration state
SELECT 'Orchestration State' AS Section, *
FROM dt.OrchestrationState
WHERE InstanceId = @InstanceId;

-- History events
SELECT 'History Events' AS Section, *
FROM dt.OrchestrationStateHistory
WHERE InstanceId = @InstanceId
ORDER BY SequenceNumber;

-- Pending work items
SELECT 'Work Items' AS Section, *
FROM dt.WorkItem
WHERE InstanceId = @InstanceId;

-- New events
SELECT 'New Events' AS Section, *
FROM dt.NewEvents
WHERE InstanceId = @InstanceId;

-- History size
SELECT 
    'History Size' AS Section,
    COUNT(*) AS EventCount,
    SUM(DATALENGTH(Input) + DATALENGTH(Result)) / 1024.0 AS SizeKB
FROM dt.OrchestrationStateHistory
WHERE InstanceId = @InstanceId;
```

---

## Production Incident Playbook

### Incident: High Queue Depth

**Steps**:
1. Check queue depth: `SELECT COUNT(*) FROM dt.WorkItem WHERE LockedUntil IS NULL`
2. Identify bottleneck: Check if specific activity is slow
3. Scale workers: Add more worker instances
4. Increase concurrency: Adjust `MaxConcurrentTaskActivities`
5. Monitor: Watch queue depth decrease

### Incident: Mass Orchestration Failures

**Steps**:
1. Identify common failure: Query failed orchestrations
   ```sql
   SELECT TOP 100 Output 
   FROM dt.OrchestrationState 
   WHERE Status = 'Failed' 
       AND CompletedTime > DATEADD(HOUR, -1, GETUTCDATE())
   ```
2. Check for infrastructure issues: Database, network, external APIs
3. Review recent deployments: Rollback if needed
4. Fix root cause
5. Resubmit failed orchestrations if needed

### Incident: Database Outage

**Steps**:
1. Check SQL Server availability
2. Review connection strings and credentials
3. Check firewall rules
4. Verify backup/restore procedures
5. Consider failover to secondary (if configured)

---

## Summary

This module covered:

✅ **Common Errors**: Solutions for frequent error messages  
✅ **Non-Determinism**: Detection and fixes  
✅ **Performance**: Diagnosing slow orchestrations  
✅ **Database Issues**: Deadlocks, growth, optimization  
✅ **Serialization**: JSON errors and circular references  
✅ **Stuck Orchestrations**: Detection and recovery  
✅ **Versioning**: Type migration issues  
✅ **Connection Pools**: Exhaustion and tuning  
✅ **Debug Queries**: SQL diagnostics  
✅ **Incident Playbook**: Production issue response  

---

**Congratulations!** You have completed the DurableTask Expert Skill training. You now have comprehensive knowledge to:
- Design and implement complex workflows
- Optimize performance for production
- Troubleshoot and resolve issues
- Deploy and maintain on-premises SQL Server installations

Refer to [SKILL.md](./SKILL.md) for the complete knowledge base index.
