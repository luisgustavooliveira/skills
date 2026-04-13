# 01 - Foundation: Core Concepts & Architecture

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Core Components](#core-components)
3. [Orchestrations](#orchestrations)
4. [Activities](#activities)
5. [Deterministic Constraints](#deterministic-constraints)
6. [Replay & Durability](#replay--durability)
7. [Event Sourcing Model](#event-sourcing-model)

---

## Architecture Overview

### The Big Picture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Task Hub                                   │
│                                                                      │
│  ┌────────────────────────┐              ┌────────────────────────┐ │
│  │    TaskHubWorker       │              │    TaskHubClient       │ │
│  │                        │              │                        │ │
│  │  ┌──────────────────┐  │              │  • CreateInstance     │ │
│  │  │  Orchestrations  │  │              │  • QueryStatus        │ │
│  │  │  - Execute logic │  │              │  • RaiseEvent         │ │
│  │  │  - Schedule work │  │              │  • Terminate          │ │
│  │  └──────────────────┘  │              │  • WaitForCompletion  │ │
│  │                        │              │                        │ │
│  │  ┌──────────────────┐  │              └───────────┬────────────┘ │
│  │  │    Activities    │  │                          │              │
│  │  │  - Perform work  │  │                          │              │
│  │  │  - Call APIs     │  │                          │              │
│  │  │  - Access DB     │  │                          │              │
│  │  └──────────────────┘  │                          │              │
│  └───────────┬────────────┘                          │              │
│              │                                        │              │
│              └────────────────┬───────────────────────┘              │
│                               │                                      │
│                               ▼                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │           IOrchestrationService (Backend Provider)          │    │
│  │                                                             │    │
│  │  • Control Queue  - Orchestration messages                 │    │
│  │  • Work Queue     - Activity messages                      │    │
│  │  • History Store  - Event sourcing data                    │    │
│  │  • Instance Store - Query and status metadata              │    │
│  └─────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
```

### Key Concepts

**Task Hub**: A logical container that isolates orchestration state and execution. All workers and clients must connect to the same task hub to interact.

**Worker**: Hosts and executes orchestrations and activities. Multiple workers can connect to the same task hub for scale-out.

**Client**: External API for managing orchestration instances - starting, querying, sending events, terminating.

**Backend Provider**: Pluggable storage implementation (SQL Server, Azure Storage, etc.) that provides message queues and state persistence.

---

## Core Components

### 1. TaskHubWorker

The worker hosts and executes orchestrations and activities.

#### Complete Worker Setup (.NET 9+)

```csharp
using DurableTask.Core;
using DurableTask.SqlServer;
using Microsoft.Extensions.Logging;

namespace OrderProcessing;

// Worker configuration
public sealed class WorkerConfiguration
{
    public required string ConnectionString { get; init; }
    public required string TaskHubName { get; init; }
    public int MaxConcurrentOrchestrations { get; init; } = 100;
    public int MaxConcurrentActivities { get; init; } = 200;
}

// Worker host
public sealed class OrchestrationWorkerHost : IAsyncDisposable
{
    private readonly ILoggerFactory _loggerFactory;
    private readonly WorkerConfiguration _config;
    private SqlOrchestrationService? _orchestrationService;
    private TaskHubWorker? _worker;

    public OrchestrationWorkerHost(
        WorkerConfiguration config,
        ILoggerFactory loggerFactory)
    {
        _config = config;
        _loggerFactory = loggerFactory;
    }

    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        // Create SQL Server orchestration service
        var settings = new SqlOrchestrationServiceSettings
        {
            TaskHubConnectionString = _config.ConnectionString,
            TaskHubName = _config.TaskHubName,
            
            // Performance tuning
            WorkItemLockTimeout = TimeSpan.FromMinutes(5),
            MaxConcurrentTaskOrchestrationWorkItems = _config.MaxConcurrentOrchestrations,
            MaxConcurrentTaskActivityWorkItems = _config.MaxConcurrentActivities,
            
            // Enable compression for large payloads
            CompressLargeMessages = true,
        };

        _orchestrationService = new SqlOrchestrationService(settings);
        
        // Create task hub tables if they don't exist
        await _orchestrationService.CreateIfNotExistsAsync();

        // Create worker
        _worker = new TaskHubWorker(_orchestrationService, _loggerFactory)
        {
            // Use FailureDetails for consistent error handling
            ErrorPropagationMode = ErrorPropagationMode.UseFailureDetails
        };

        // Register orchestrations
        _worker.AddTaskOrchestrations(
            typeof(OrderProcessingOrchestration),
            typeof(PaymentProcessingOrchestration),
            typeof(ShipmentOrchestration));

        // Register activities
        _worker.AddTaskActivities(
            typeof(ValidateInventoryActivity),
            typeof(ChargePaymentActivity),
            typeof(ShipOrderActivity));

        // Add middleware for cross-cutting concerns
        AddMiddleware(_worker);

        // Start processing
        await _worker.StartAsync();
        
        _loggerFactory.CreateLogger<OrchestrationWorkerHost>()
            .LogInformation("Worker started for task hub: {TaskHubName}", _config.TaskHubName);
    }

    private void AddMiddleware(TaskHubWorker worker)
    {
        var logger = _loggerFactory.CreateLogger<OrchestrationWorkerHost>();

        // Orchestration logging middleware
        worker.AddOrchestrationDispatcherMiddleware(async (context, next) =>
        {
            var instance = context.GetProperty<OrchestrationInstance>();
            var runtimeState = context.GetProperty<OrchestrationRuntimeState>();
            
            var stopwatch = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                await next();
                logger.LogInformation(
                    "Orchestration {Name} ({InstanceId}) executed in {ElapsedMs}ms",
                    runtimeState?.Name ?? "Unknown",
                    instance?.InstanceId ?? "Unknown",
                    stopwatch.ElapsedMilliseconds);
            }
            catch (Exception ex)
            {
                logger.LogError(ex,
                    "Orchestration {Name} ({InstanceId}) failed after {ElapsedMs}ms",
                    runtimeState?.Name ?? "Unknown",
                    instance?.InstanceId ?? "Unknown",
                    stopwatch.ElapsedMilliseconds);
                throw;
            }
        });

        // Activity logging middleware
        worker.AddActivityDispatcherMiddleware(async (context, next) =>
        {
            var scheduledEvent = context.GetProperty<TaskScheduledEvent>();
            var instance = context.GetProperty<OrchestrationInstance>();
            
            var stopwatch = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                await next();
                logger.LogInformation(
                    "Activity {Name} for orchestration {InstanceId} completed in {ElapsedMs}ms",
                    scheduledEvent?.Name ?? "Unknown",
                    instance?.InstanceId ?? "Unknown",
                    stopwatch.ElapsedMilliseconds);
            }
            catch (Exception ex)
            {
                logger.LogError(ex,
                    "Activity {Name} for orchestration {InstanceId} failed after {ElapsedMs}ms",
                    scheduledEvent?.Name ?? "Unknown",
                    instance?.InstanceId ?? "Unknown",
                    stopwatch.ElapsedMilliseconds);
                throw;
            }
        });
    }

    public async Task StopAsync()
    {
        if (_worker is not null)
        {
            await _worker.StopAsync(isForced: false);
            _loggerFactory.CreateLogger<OrchestrationWorkerHost>()
                .LogInformation("Worker stopped gracefully");
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (_worker is not null)
        {
            await _worker.StopAsync(isForced: true);
        }
        
        _orchestrationService?.Dispose();
    }
}
```

### 2. TaskHubClient

The client manages orchestration instances from external code.

#### Complete Client Implementation

```csharp
using DurableTask.Core;
using DurableTask.SqlServer;
using Microsoft.Extensions.Logging;

namespace OrderProcessing;

/// <summary>
/// Client for managing orchestration instances
/// </summary>
public sealed class OrchestrationClient : IAsyncDisposable
{
    private readonly SqlOrchestrationService _orchestrationService;
    private readonly TaskHubClient _client;
    private readonly ILogger<OrchestrationClient> _logger;

    public OrchestrationClient(
        string connectionString,
        string taskHubName,
        ILoggerFactory loggerFactory)
    {
        _logger = loggerFactory.CreateLogger<OrchestrationClient>();
        
        var settings = new SqlOrchestrationServiceSettings
        {
            TaskHubConnectionString = connectionString,
            TaskHubName = taskHubName
        };

        _orchestrationService = new SqlOrchestrationService(settings);
        _client = new TaskHubClient(_orchestrationService, loggerFactory: loggerFactory);
    }

    /// <summary>
    /// Start a new orchestration instance
    /// </summary>
    public async Task<string> StartOrchestrationAsync<TOrchestration, TInput>(
        TInput input,
        string? instanceId = null,
        CancellationToken cancellationToken = default)
        where TOrchestration : TaskOrchestration
    {
        instanceId ??= Guid.NewGuid().ToString();

        _logger.LogInformation(
            "Starting orchestration {OrchType} with instance ID: {InstanceId}",
            typeof(TOrchestration).Name,
            instanceId);

        var instance = await _client.CreateOrchestrationInstanceAsync(
            typeof(TOrchestration),
            instanceId,
            input);

        return instance.InstanceId;
    }

    /// <summary>
    /// Get orchestration status
    /// </summary>
    public async Task<OrchestrationState?> GetStatusAsync(
        string instanceId,
        CancellationToken cancellationToken = default)
    {
        var state = await _client.GetOrchestrationStateAsync(instanceId);
        return state;
    }

    /// <summary>
    /// Wait for orchestration to complete and get result
    /// </summary>
    public async Task<TOutput?> WaitForCompletionAsync<TOutput>(
        string instanceId,
        TimeSpan timeout,
        CancellationToken cancellationToken = default)
    {
        var instance = new OrchestrationInstance { InstanceId = instanceId };
        var state = await _client.WaitForOrchestrationAsync(instance, timeout);

        if (state.OrchestrationStatus == OrchestrationStatus.Completed)
        {
            return state.GetOutput<TOutput>();
        }

        return default;
    }

    /// <summary>
    /// Raise an external event to an orchestration
    /// </summary>
    public async Task RaiseEventAsync<TEventData>(
        string instanceId,
        string eventName,
        TEventData eventData,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "Raising event {EventName} to orchestration {InstanceId}",
            eventName,
            instanceId);

        await _client.RaiseEventAsync(
            new OrchestrationInstance { InstanceId = instanceId },
            eventName,
            eventData);
    }

    /// <summary>
    /// Terminate a running orchestration
    /// </summary>
    public async Task TerminateAsync(
        string instanceId,
        string reason,
        CancellationToken cancellationToken = default)
    {
        _logger.LogWarning(
            "Terminating orchestration {InstanceId} with reason: {Reason}",
            instanceId,
            reason);

        await _client.TerminateInstanceAsync(
            new OrchestrationInstance { InstanceId = instanceId },
            reason);
    }

    public ValueTask DisposeAsync()
    {
        _orchestrationService?.Dispose();
        return ValueTask.CompletedTask;
    }
}
```

---

## Orchestrations

Orchestrations define the workflow logic. They must be **deterministic** and **replayable**.

### Orchestration Structure (.NET 9+)

```csharp
using DurableTask.Core;

namespace OrderProcessing.Orchestrations;

/// <summary>
/// Input for order processing orchestration
/// </summary>
public sealed record OrderInput
{
    public required string OrderId { get; init; }
    public required string CustomerId { get; init; }
    public required decimal TotalAmount { get; init; }
    public required List<OrderItem> Items { get; init; }
}

public sealed record OrderItem
{
    public required string ProductId { get; init; }
    public required int Quantity { get; init; }
    public required decimal Price { get; init; }
}

/// <summary>
/// Output from order processing orchestration
/// </summary>
public sealed record OrderResult
{
    public required bool Success { get; init; }
    public string? TransactionId { get; init; }
    public string? TrackingNumber { get; init; }
    public string? ErrorMessage { get; init; }
}

/// <summary>
/// Order processing orchestration with validation, payment, and fulfillment
/// </summary>
public sealed class OrderProcessingOrchestration : TaskOrchestration<OrderResult, OrderInput>
{
    public override async Task<OrderResult> RunTask(
        OrchestrationContext context,
        OrderInput input)
    {
        // ✅ CORRECT: Use context for logging during replay
        if (!context.IsReplaying)
        {
            context.CreateEvent(EventType.LogInformation,
                $"Starting order processing for {input.OrderId}");
        }

        try
        {
            // Step 1: Validate inventory
            var inventoryValid = await context.ScheduleTask<bool>(
                typeof(ValidateInventoryActivity),
                input.Items);

            if (!inventoryValid)
            {
                return new OrderResult
                {
                    Success = false,
                    ErrorMessage = "Insufficient inventory"
                };
            }

            // Step 2: Charge payment with retry policy
            var retryOptions = new RetryOptions(
                firstRetryInterval: TimeSpan.FromSeconds(5),
                maxNumberOfAttempts: 3)
            {
                BackoffCoefficient = 2.0,
                MaxRetryInterval = TimeSpan.FromMinutes(1),
                Handle = exception => exception is TimeoutException
                                   || exception is HttpRequestException
            };

            var transactionId = await context.ScheduleWithRetry<string>(
                typeof(ChargePaymentActivity),
                retryOptions,
                new PaymentRequest
                {
                    OrderId = input.OrderId,
                    Amount = input.TotalAmount,
                    CustomerId = input.CustomerId
                });

            // Step 3: Ship order
            var trackingNumber = await context.ScheduleTask<string>(
                typeof(ShipOrderActivity),
                new ShipmentRequest
                {
                    OrderId = input.OrderId,
                    Items = input.Items,
                    CustomerId = input.CustomerId
                });

            return new OrderResult
            {
                Success = true,
                TransactionId = transactionId,
                TrackingNumber = trackingNumber
            };
        }
        catch (TaskFailedException ex)
        {
            // Check specific error types using FailureDetails
            if (ex.FailureDetails?.IsCausedBy<PaymentDeclinedException>() == true)
            {
                return new OrderResult
                {
                    Success = false,
                    ErrorMessage = "Payment was declined"
                };
            }

            // Log and rethrow for other failures
            if (!context.IsReplaying)
            {
                context.CreateEvent(EventType.LogError,
                    $"Order processing failed: {ex.FailureDetails?.ErrorMessage}");
            }

            throw;
        }
    }
}
```

### OrchestrationContext API Reference

```csharp
// Core orchestration info
string instanceId = context.OrchestrationInstance.InstanceId;
DateTime now = context.CurrentUtcDateTime;  // ✅ Always use this, never DateTime.UtcNow
Guid newGuid = context.NewGuid();           // ✅ Always use this, never Guid.NewGuid()
bool isReplaying = context.IsReplaying;     // True when replaying history

// Scheduling work
TResult result = await context.ScheduleTask<TResult>(typeof(MyActivity), input);
TResult result = await context.ScheduleWithRetry<TResult>(typeof(MyActivity), retryOptions, input);

// Sub-orchestrations
TResult result = await context.CreateSubOrchestrationInstance<TResult>(
    typeof(ChildOrchestration), 
    input);
TResult result = await context.CreateSubOrchestrationInstance<TResult>(
    typeof(ChildOrchestration), 
    instanceId: "child-123",
    input);

// Timers
await context.CreateTimer(context.CurrentUtcDateTime.AddMinutes(5), true);
await context.CreateTimer(deadline, true, cancellationToken);

// External events (requires OnEvent override)
// See 03-ADVANCED.md for external event patterns

// Continue as new (reset history)
context.ContinueAsNew(newInput);
```

---

## Activities

Activities perform the actual work - API calls, database operations, computations.

### Activity Structure (.NET 9+)

```csharp
using DurableTask.Core;
using Microsoft.Extensions.Logging;

namespace OrderProcessing.Activities;

public sealed record PaymentRequest
{
    public required string OrderId { get; init; }
    public required string CustomerId { get; init; }
    public required decimal Amount { get; init; }
}

/// <summary>
/// Activity that charges payment for an order
/// Implements idempotency to prevent duplicate charges
/// </summary>
public sealed class ChargePaymentActivity : AsyncTaskActivity<PaymentRequest, string>
{
    private readonly IPaymentService _paymentService;
    private readonly ILogger<ChargePaymentActivity> _logger;

    public ChargePaymentActivity(
        IPaymentService paymentService,
        ILogger<ChargePaymentActivity> logger)
    {
        _paymentService = paymentService;
        _logger = logger;
    }

    protected override async Task<string> ExecuteAsync(
        TaskContext context,
        PaymentRequest input)
    {
        var instanceId = context.OrchestrationInstance.InstanceId;

        _logger.LogInformation(
            "Processing payment for order {OrderId}, orchestration {InstanceId}",
            input.OrderId,
            instanceId);

        try
        {
            // Use order ID as idempotency key to prevent duplicate charges
            var transactionId = await _paymentService.ChargeAsync(
                customerId: input.CustomerId,
                amount: input.Amount,
                idempotencyKey: input.OrderId,
                cancellationToken: CancellationToken.None);

            _logger.LogInformation(
                "Payment processed successfully. Order: {OrderId}, Transaction: {TransactionId}",
                input.OrderId,
                transactionId);

            return transactionId;
        }
        catch (PaymentDeclinedException ex)
        {
            _logger.LogWarning(
                "Payment declined for order {OrderId}: {Reason}",
                input.OrderId,
                ex.Reason);
            
            // Re-throw to fail the activity
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex,
                "Payment processing failed for order {OrderId}",
                input.OrderId);
            
            throw;
        }
    }
}

/// <summary>
/// Synchronous activity example for simple operations
/// </summary>
public sealed class ValidateInventoryActivity : TaskActivity<List<OrderItem>, bool>
{
    private readonly IInventoryService _inventoryService;

    public ValidateInventoryActivity(IInventoryService inventoryService)
    {
        _inventoryService = inventoryService;
    }

    protected override bool Execute(TaskContext context, List<OrderItem> items)
    {
        // Synchronous validation
        foreach (var item in items)
        {
            var available = _inventoryService.GetAvailableQuantity(item.ProductId);
            if (available < item.Quantity)
            {
                return false;
            }
        }

        return true;
    }
}
```

### Activity Best Practices

✅ **Make Activities Idempotent**
```csharp
// Use idempotency keys for operations that shouldn't be repeated
var result = await _service.ProcessAsync(
    input,
    idempotencyKey: context.OrchestrationInstance.InstanceId);
```

✅ **Include Orchestration Context in Logs**
```csharp
_logger.LogInformation(
    "Processing {Operation} for orchestration {InstanceId}",
    operationName,
    context.OrchestrationInstance.InstanceId);
```

✅ **Return Errors Instead of Throwing for Expected Failures**
```csharp
// When failure is expected, return a result
public sealed record ValidationResult
{
    public required bool IsValid { get; init; }
    public string? ErrorMessage { get; init; }
}

// Activity returns result instead of throwing
protected override ValidationResult Execute(TaskContext context, Input input)
{
    if (string.IsNullOrEmpty(input.Email))
    {
        return new ValidationResult
        {
            IsValid = false,
            ErrorMessage = "Email is required"
        };
    }
    
    return new ValidationResult { IsValid = true };
}
```

---

## Deterministic Constraints

**THE GOLDEN RULE**: Same input must always produce same sequence of durable operations.

### ❌ NEVER Do This in Orchestrations

```csharp
public override async Task<string> RunTask(OrchestrationContext context, string input)
{
    // ❌ WRONG: Uses current time (changes on replay)
    if (DateTime.UtcNow.Hour < 12)
    {
        await context.ScheduleTask<string>(typeof(MorningActivity), input);
    }
    
    // ❌ WRONG: Generates different GUID on replay
    var id = Guid.NewGuid().ToString();
    
    // ❌ WRONG: Random value changes on replay
    var random = new Random();
    if (random.Next(100) > 50) { }
    
    // ❌ WRONG: Blocks thread, doesn't persist
    await Task.Delay(TimeSpan.FromMinutes(5));
    Thread.Sleep(1000);
    
    // ❌ WRONG: Background work is non-deterministic
    await Task.Run(() => DoWork());
    
    // ❌ WRONG: Network call in orchestration
    var response = await httpClient.GetAsync("https://api.example.com/data");
    
    // ❌ WRONG: Database access in orchestration
    var user = await dbContext.Users.FindAsync(userId);
    
    // ❌ WRONG: Reading environment variables
    var endpoint = Environment.GetEnvironmentVariable("API_URL");
    
    // ❌ WRONG: Non-deterministic collection iteration
    var items = new HashSet<string> { "a", "b", "c" };
    foreach (var item in items) // Order not guaranteed!
    {
        await context.ScheduleTask<string>(typeof(ProcessActivity), item);
    }
    
    return "done";
}
```

### ✅ ALWAYS Do This Instead

```csharp
public override async Task<string> RunTask(OrchestrationContext context, string input)
{
    // ✅ CORRECT: Use orchestration time
    if (context.CurrentUtcDateTime.Hour < 12)
    {
        await context.ScheduleTask<string>(typeof(MorningActivity), input);
    }
    
    // ✅ CORRECT: Use context for GUID generation
    var id = context.NewGuid().ToString();
    
    // ✅ CORRECT: Get random value from activity or use fixed seed
    var randomValue = await context.ScheduleTask<int>(typeof(GetRandomActivity), 100);
    // OR use fixed seed: var random = new Random(42);
    
    // ✅ CORRECT: Use durable timer
    await context.CreateTimer(context.CurrentUtcDateTime.AddMinutes(5), true);
    
    // ✅ CORRECT: Use fan-out pattern instead of Task.Run
    var tasks = items.Select(item =>
        context.ScheduleTask<string>(typeof(ProcessActivity), item));
    await Task.WhenAll(tasks);
    
    // ✅ CORRECT: Network calls in activities
    var data = await context.ScheduleTask<string>(typeof(FetchDataActivity), "https://api.example.com/data");
    
    // ✅ CORRECT: Database queries in activities
    var user = await context.ScheduleTask<User>(typeof(GetUserActivity), userId);
    
    // ✅ CORRECT: Pass config as input or read in activity
    var result = await context.ScheduleTask<string>(typeof(CallApiActivity), input.ApiEndpoint);
    
    // ✅ CORRECT: Use ordered collection
    var items = new List<string> { "a", "b", "c" };
    foreach (var item in items)
    {
        await context.ScheduleTask<string>(typeof(ProcessActivity), item);
    }
    
    return "done";
}
```

---

## Replay & Durability

### How Replay Works

DTFx uses **event sourcing** to achieve durability. Every orchestration decision is recorded as an event.

#### First Execution

```csharp
public override async Task<string> RunTask(OrchestrationContext context, string input)
{
    var a = await context.ScheduleTask<string>(typeof(ActivityA), input);  // Records TaskScheduled
    var b = await context.ScheduleTask<string>(typeof(ActivityB), a);      // Records TaskScheduled
    return b;
}
```

**History after first execution:**
```
1. ExecutionStarted { Input: "hello" }
2. TaskScheduled { Name: "ActivityA", Input: "hello" }
3. TaskCompleted { Result: "A-result" }
4. TaskScheduled { Name: "ActivityB", Input: "A-result" }
5. TaskCompleted { Result: "B-result" }
6. ExecutionCompleted { Result: "B-result" }
```

#### Replay After Restart

If the process crashes and restarts:

1. Framework loads history from SQL Server
2. `RunTask` executes again **from the beginning**
3. Each `await` checks history for existing result
4. If result exists in history, return it immediately (no actual execution)
5. If no result, schedule work and wait

```csharp
// During replay:
var a = await context.ScheduleTask<string>(typeof(ActivityA), input);
// ↑ Sees TaskCompleted in history, returns "A-result" immediately (does NOT execute activity)

var b = await context.ScheduleTask<string>(typeof(ActivityB), a);
// ↑ Sees TaskCompleted in history, returns "B-result" immediately
```

### Checkpointing

State is saved (checkpointed) when:
- An `await` yields control to framework
- Orchestration completes or fails
- `ContinueAsNew` is called

**What gets saved:**
- Complete event history
- Orchestration input/output
- Custom status (if set)

**What does NOT get saved:**
- Local variables (rebuilt during replay)
- In-memory state outside orchestration

### IsReplaying Property

Use `context.IsReplaying` to avoid duplicate side effects:

```csharp
public override async Task<string> RunTask(OrchestrationContext context, string input)
{
    // This code runs during EVERY replay
    var data = ProcessInput(input);
    
    if (!context.IsReplaying)
    {
        // This only runs during FIRST execution (not during replay)
        _logger.LogInformation("Processing order {OrderId}", input);
        _metrics.IncrementCounter("orders.started");
    }
    
    var result = await context.ScheduleTask<string>(typeof(MyActivity), data);
    return result;
}
```

**When to use IsReplaying:**

| Use Case | Use IsReplaying? |
|----------|------------------|
| Logging | ✅ Yes - avoid duplicate logs |
| Metrics | ✅ Yes - avoid double-counting |
| Business logic | ❌ No - must work identically during replay |
| Side effects | ❌ No - use activities instead |

---

## Event Sourcing Model

### Event Types

| Event | When Created | Purpose |
|-------|-------------|---------|
| `ExecutionStarted` | Orchestration begins | Records input and start time |
| `TaskScheduled` | Activity scheduled | Records activity name, version, input |
| `TaskCompleted` | Activity succeeds | Records result |
| `TaskFailed` | Activity fails | Records exception details |
| `SubOrchestrationInstanceCreated` | Sub-orch starts | Records child info |
| `SubOrchestrationInstanceCompleted` | Sub-orch completes | Records result |
| `TimerCreated` | Timer created | Records fire time |
| `TimerFired` | Timer elapses | Marks timer complete |
| `EventRaised` | External event received | Records event data |
| `ExecutionCompleted` | Orchestration completes | Records final result |
| `ExecutionFailed` | Orchestration fails | Records exception |
| `ExecutionTerminated` | Explicit termination | Records reason |

### Viewing History (SQL Server)

```sql
-- View orchestration history
SELECT 
    InstanceID,
    EventType,
    TaskID,
    [Timestamp],
    DataText
FROM dt.History
WHERE InstanceID = 'your-instance-id'
ORDER BY SequenceNumber;
```

### History Growth Considerations

Long-running orchestrations accumulate history events:

```
After 1000 iterations without ContinueAsNew:
- History events: 10,000+
- Memory usage: High
- Replay time: Slow
- Risk: OutOfMemoryException

After 1000 iterations with ContinueAsNew (every 100 ops):
- History events: ~100 per restart
- Memory usage: Low
- Replay time: Fast
```

**Solution**: Use `ContinueAsNew` for eternal orchestrations (see 02-PATTERNS.md).

---

## Quick Reference Card

### Orchestration Essentials

```csharp
// Time
context.CurrentUtcDateTime          // ✅ Use this
DateTime.UtcNow                     // ❌ Never use

// GUIDs
context.NewGuid()                   // ✅ Use this
Guid.NewGuid()                      // ❌ Never use

// Delays
context.CreateTimer(when, true)     // ✅ Use this
Task.Delay() / Thread.Sleep()      // ❌ Never use

// Work
context.ScheduleTask()              // ✅ Schedule activity
await httpClient.GetAsync()         // ❌ Never in orchestration

// Replay
context.IsReplaying                 // Use for logging/metrics only
```

### Error Handling

```csharp
// Configure worker
worker.ErrorPropagationMode = ErrorPropagationMode.UseFailureDetails;

// Handle in orchestration
catch (TaskFailedException ex) when (ex.FailureDetails?.IsCausedBy<TimeoutException>() == true)
{
    // Handle timeout
}
```

### Common Patterns

```csharp
// Sequential
var a = await context.ScheduleTask<string>(typeof(A), input);
var b = await context.ScheduleTask<string>(typeof(B), a);

// Parallel (fan-out/fan-in)
var tasks = items.Select(i => context.ScheduleTask<Result>(typeof(Activity), i));
var results = await Task.WhenAll(tasks);

// With timeout
using var cts = new CancellationTokenSource();
var workTask = context.ScheduleTask<string>(typeof(Activity), input);
var timeoutTask = context.CreateTimer(deadline, true, cts.Token);
var winner = await Task.WhenAny(workTask, timeoutTask);
if (winner == workTask) cts.Cancel();
```

---

**Next**: [02-PATTERNS.md](./02-PATTERNS.md) - Comprehensive workflow patterns with complete implementations.
