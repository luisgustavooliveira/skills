# 02 - Patterns: Workflow Implementation Patterns

## Table of Contents

1. [Sequential Execution](#sequential-execution)
2. [Fan-Out/Fan-In (Parallel)](#fan-outfan-in-parallel)
3. [Human Interaction](#human-interaction)
4. [Monitor Pattern](#monitor-pattern)
5. [Saga Pattern (Compensation)](#saga-pattern-compensation)
6. [Eternal Orchestrations](#eternal-orchestrations)
7. [Scheduled Execution](#scheduled-execution)
8. [Circuit Breaker](#circuit-breaker)
9. [Pattern Selection Guide](#pattern-selection-guide)

---

## Sequential Execution

Execute activities in sequence where each step depends on the previous result.

### When to Use
- Steps must execute in order
- Each step needs output from previous step
- Simple linear workflows

### Complete Implementation

```csharp
using DurableTask.Core;
using Microsoft.Extensions.Logging;

namespace Workflows.Patterns;

public sealed record DocumentProcessingInput
{
    public required string DocumentId { get; init; }
    public required string UserId { get; init; }
    public required DocumentType Type { get; init; }
}

public enum DocumentType
{
    Invoice,
    Contract,
    Report
}

public sealed record DocumentProcessingResult
{
    public required bool Success { get; init; }
    public string? ProcessedDocumentUrl { get; init; }
    public string? ErrorMessage { get; init; }
    public required List<string> CompletedSteps { get; init; }
}

/// <summary>
/// Sequential document processing workflow
/// Demonstrates step-by-step processing with dependency chain
/// </summary>
public sealed class DocumentProcessingOrchestration 
    : TaskOrchestration<DocumentProcessingResult, DocumentProcessingInput>
{
    public override async Task<DocumentProcessingResult> RunTask(
        OrchestrationContext context,
        DocumentProcessingInput input)
    {
        var completedSteps = new List<string>();

        try
        {
            // Step 1: Download document from storage
            var downloadResult = await context.ScheduleTask<DownloadResult>(
                typeof(DownloadDocumentActivity),
                new DownloadRequest
                {
                    DocumentId = input.DocumentId,
                    UserId = input.UserId
                });

            completedSteps.Add("Downloaded");

            // Step 2: Extract text from document (depends on download)
            var extractedText = await context.ScheduleTask<string>(
                typeof(ExtractTextActivity),
                downloadResult.LocalFilePath);

            completedSteps.Add("TextExtracted");

            // Step 3: Analyze content (depends on extracted text)
            var analysisResult = await context.ScheduleTask<AnalysisResult>(
                typeof(AnalyzeContentActivity),
                new AnalysisRequest
                {
                    Text = extractedText,
                    DocumentType = input.Type
                });

            completedSteps.Add("Analyzed");

            // Step 4: Generate summary (depends on analysis)
            var summary = await context.ScheduleTask<string>(
                typeof(GenerateSummaryActivity),
                analysisResult);

            completedSteps.Add("SummaryGenerated");

            // Step 5: Upload processed document (depends on summary)
            var uploadedUrl = await context.ScheduleTask<string>(
                typeof(UploadProcessedDocumentActivity),
                new UploadRequest
                {
                    DocumentId = input.DocumentId,
                    Summary = summary,
                    Metadata = analysisResult.Metadata
                });

            completedSteps.Add("Uploaded");

            // Step 6: Notify user (final step)
            await context.ScheduleTask<bool>(
                typeof(NotifyUserActivity),
                new NotificationRequest
                {
                    UserId = input.UserId,
                    DocumentId = input.DocumentId,
                    Url = uploadedUrl
                });

            completedSteps.Add("UserNotified");

            return new DocumentProcessingResult
            {
                Success = true,
                ProcessedDocumentUrl = uploadedUrl,
                CompletedSteps = completedSteps
            };
        }
        catch (TaskFailedException ex)
        {
            if (!context.IsReplaying)
            {
                context.CreateEvent(EventType.LogError,
                    $"Document processing failed at step: {completedSteps.LastOrDefault() ?? "Start"}");
            }

            return new DocumentProcessingResult
            {
                Success = false,
                ErrorMessage = ex.FailureDetails?.ErrorMessage ?? "Unknown error",
                CompletedSteps = completedSteps
            };
        }
    }
}
```

---

## Fan-Out/Fan-In (Parallel)

Execute multiple activities in parallel and wait for all to complete.

### When to Use
- Independent operations that can run concurrently
- Batch processing of items
- Aggregating data from multiple sources
- Performance optimization for I/O-bound work

### Complete Implementation

```csharp
using DurableTask.Core;

namespace Workflows.Patterns;

public sealed record BatchProcessingInput
{
    public required string BatchId { get; init; }
    public required List<string> ItemIds { get; init; }
    public int MaxParallelism { get; init; } = 10;
}

public sealed record BatchProcessingResult
{
    public required string BatchId { get; init; }
    public required int TotalItems { get; init; }
    public required int SuccessCount { get; init; }
    public required int FailureCount { get; init; }
    public required List<ItemResult> Results { get; init; }
    public required TimeSpan Duration { get; init; }
}

public sealed record ItemResult
{
    public required string ItemId { get; init; }
    public required bool Success { get; init; }
    public string? Output { get; init; }
    public string? ErrorMessage { get; init; }
}

/// <summary>
/// Fan-out/fan-in pattern with controlled parallelism
/// Processes items in parallel with batching to control concurrency
/// </summary>
public sealed class BatchProcessingOrchestration 
    : TaskOrchestration<BatchProcessingResult, BatchProcessingInput>
{
    public override async Task<BatchProcessingResult> RunTask(
        OrchestrationContext context,
        BatchProcessingInput input)
    {
        var startTime = context.CurrentUtcDateTime;
        var allResults = new List<ItemResult>();

        // Process in chunks to control parallelism
        var chunks = input.ItemIds
            .Select((id, index) => new { id, index })
            .GroupBy(x => x.index / input.MaxParallelism)
            .Select(g => g.Select(x => x.id).ToList())
            .ToList();

        foreach (var chunk in chunks)
        {
            // Fan-out: Start all activities in this chunk in parallel
            var tasks = chunk.Select(itemId =>
                ProcessItemSafelyAsync(context, itemId)).ToList();

            // Fan-in: Wait for all activities in this chunk to complete
            var chunkResults = await Task.WhenAll(tasks);
            allResults.AddRange(chunkResults);
        }

        var duration = context.CurrentUtcDateTime - startTime;

        return new BatchProcessingResult
        {
            BatchId = input.BatchId,
            TotalItems = input.ItemIds.Count,
            SuccessCount = allResults.Count(r => r.Success),
            FailureCount = allResults.Count(r => !r.Success),
            Results = allResults,
            Duration = duration
        };
    }

    /// <summary>
    /// Process individual item with error handling
    /// </summary>
    private async Task<ItemResult> ProcessItemSafelyAsync(
        OrchestrationContext context,
        string itemId)
    {
        try
        {
            // Configure retry for transient failures
            var retryOptions = new RetryOptions(
                firstRetryInterval: TimeSpan.FromSeconds(2),
                maxNumberOfAttempts: 3)
            {
                BackoffCoefficient = 2.0,
                MaxRetryInterval = TimeSpan.FromSeconds(30)
            };

            var output = await context.ScheduleWithRetry<string>(
                typeof(ProcessItemActivity),
                retryOptions,
                itemId);

            return new ItemResult
            {
                ItemId = itemId,
                Success = true,
                Output = output
            };
        }
        catch (TaskFailedException ex)
        {
            // Item failed even after retries
            return new ItemResult
            {
                ItemId = itemId,
                Success = false,
                ErrorMessage = ex.FailureDetails?.ErrorMessage ?? "Unknown error"
            };
        }
    }
}

/// <summary>
/// Alternative: Simple fan-out/fan-in without batching
/// Use when parallelism is naturally limited or items are few
/// </summary>
public sealed class SimpleFanOutOrchestration 
    : TaskOrchestration<List<string>, List<string>>
{
    public override async Task<List<string>> RunTask(
        OrchestrationContext context,
        List<string> inputs)
    {
        // Fan-out: Start all activities in parallel
        var tasks = inputs.Select(input =>
            context.ScheduleTask<string>(typeof(ProcessItemActivity), input))
            .ToList();

        // Fan-in: Wait for all to complete
        var results = await Task.WhenAll(tasks);

        return results.ToList();
    }
}
```

### Fan-Out to Sub-Orchestrations

For complex item processing, fan-out to sub-orchestrations:

```csharp
/// <summary>
/// Fan-out to sub-orchestrations for complex item workflows
/// Each item gets its own isolated history and lifecycle
/// </summary>
public sealed class ComplexBatchOrchestration 
    : TaskOrchestration<BatchResult, BatchInput>
{
    public override async Task<BatchResult> RunTask(
        OrchestrationContext context,
        BatchInput input)
    {
        // Fan-out to sub-orchestrations
        var tasks = input.Orders.Select(order =>
            context.CreateSubOrchestrationInstance<OrderResult>(
                typeof(OrderProcessingOrchestration),
                instanceId: $"{input.BatchId}:order:{order.OrderId}",
                input: order))
            .ToList();

        // Fan-in: Wait for all sub-orchestrations
        var results = await Task.WhenAll(tasks);

        return new BatchResult
        {
            BatchId = input.BatchId,
            OrderResults = results.ToList()
        };
    }
}
```

---

## Human Interaction

Wait for human approval or input with timeout handling.

### When to Use
- Approval workflows
- Human-in-the-loop processes
- Escalation scenarios
- Time-sensitive decisions

### Complete Implementation

```csharp
using DurableTask.Core;

namespace Workflows.Patterns;

public sealed record ApprovalRequest
{
    public required string RequestId { get; init; }
    public required string Title { get; init; }
    public required string Description { get; init; }
    public required string RequestorId { get; init; }
    public required string ApproverId { get; init; }
    public required decimal Amount { get; init; }
    public TimeSpan Timeout { get; init; } = TimeSpan.FromDays(7);
}

public sealed record ApprovalResult
{
    public required string RequestId { get; init; }
    public required ApprovalStatus Status { get; init; }
    public string? ApprovedBy { get; init; }
    public DateTime? ApprovedAt { get; init; }
    public string? Comments { get; init; }
    public string? RejectionReason { get; init; }
}

public enum ApprovalStatus
{
    Pending,
    Approved,
    Rejected,
    TimedOut,
    Escalated
}

public sealed record ApprovalResponse
{
    public required bool IsApproved { get; init; }
    public string? ApprovedBy { get; init; }
    public string? Comments { get; init; }
    public string? RejectionReason { get; init; }
}

/// <summary>
/// Human interaction pattern with timeout and escalation
/// Demonstrates external event handling using TaskCompletionSource
/// </summary>
public sealed class ApprovalWorkflowOrchestration 
    : TaskOrchestration<ApprovalResult, ApprovalRequest>
{
    private TaskCompletionSource<ApprovalResponse>? _approvalHandle;

    public override async Task<ApprovalResult> RunTask(
        OrchestrationContext context,
        ApprovalRequest request)
    {
        // Step 1: Send approval request notification
        await context.ScheduleTask<bool>(
            typeof(SendApprovalNotificationActivity),
            new ApprovalNotification
            {
                RequestId = request.RequestId,
                ApproverId = request.ApproverId,
                Title = request.Title,
                Description = request.Description,
                Amount = request.Amount,
                ApprovalUrl = $"https://portal.company.com/approvals/{context.OrchestrationInstance.InstanceId}"
            });

        // Step 2: Wait for approval with timeout
        _approvalHandle = new TaskCompletionSource<ApprovalResponse>();
        
        using var cts = new CancellationTokenSource();
        var approvalTask = _approvalHandle.Task;
        var timeoutTask = context.CreateTimer(
            context.CurrentUtcDateTime.Add(request.Timeout),
            "timeout",
            cts.Token);

        var winner = await Task.WhenAny(approvalTask, timeoutTask);

        if (winner == approvalTask)
        {
            // Approval received before timeout
            cts.Cancel();
            var response = await approvalTask;
            _approvalHandle = null;

            if (response.IsApproved)
            {
                // Step 3: Process approval
                await context.ScheduleTask<bool>(
                    typeof(ProcessApprovalActivity),
                    new ProcessApprovalRequest
                    {
                        RequestId = request.RequestId,
                        ApprovedBy = response.ApprovedBy!,
                        Comments = response.Comments
                    });

                return new ApprovalResult
                {
                    RequestId = request.RequestId,
                    Status = ApprovalStatus.Approved,
                    ApprovedBy = response.ApprovedBy,
                    ApprovedAt = context.CurrentUtcDateTime,
                    Comments = response.Comments
                };
            }
            else
            {
                // Step 3: Handle rejection
                await context.ScheduleTask<bool>(
                    typeof(ProcessRejectionActivity),
                    new ProcessRejectionRequest
                    {
                        RequestId = request.RequestId,
                        RejectedBy = response.ApprovedBy!,
                        Reason = response.RejectionReason!
                    });

                return new ApprovalResult
                {
                    RequestId = request.RequestId,
                    Status = ApprovalStatus.Rejected,
                    ApprovedBy = response.ApprovedBy,
                    RejectionReason = response.RejectionReason
                };
            }
        }
        else
        {
            // Timeout occurred - escalate to manager
            _approvalHandle = null;

            // Send escalation notification
            await context.ScheduleTask<bool>(
                typeof(EscalateApprovalActivity),
                new EscalationRequest
                {
                    RequestId = request.RequestId,
                    OriginalApproverId = request.ApproverId,
                    Reason = "Approval timed out after " + request.Timeout
                });

            return new ApprovalResult
            {
                RequestId = request.RequestId,
                Status = ApprovalStatus.TimedOut
            };
        }
    }

    /// <summary>
    /// Receive external approval event
    /// Called by framework when client sends approval event
    /// </summary>
    public override void OnEvent(OrchestrationContext context, string name, string input)
    {
        if (name == "ApprovalResponse" && _approvalHandle is not null)
        {
            var response = context.MessageDataConverter.Deserialize<ApprovalResponse>(input);
            _approvalHandle.SetResult(response);
        }
    }
}

/// <summary>
/// Multi-stage approval pattern
/// Requires multiple approvers with escalation
/// </summary>
public sealed class MultiStageApprovalOrchestration 
    : TaskOrchestration<ApprovalResult, ApprovalRequest>
{
    private TaskCompletionSource<ApprovalResponse>? _currentApprovalHandle;
    private string? _currentStage;

    public override async Task<ApprovalResult> RunTask(
        OrchestrationContext context,
        ApprovalRequest request)
    {
        // Stage 1: Manager approval
        var managerResult = await WaitForApprovalStageAsync(
            context,
            "Manager",
            request.ApproverId,
            TimeSpan.FromDays(3));

        if (managerResult.Status != ApprovalStatus.Approved)
        {
            return managerResult;
        }

        // Stage 2: Director approval (for amounts > $10,000)
        if (request.Amount > 10000)
        {
            var directorId = await context.ScheduleTask<string>(
                typeof(GetDirectorActivity),
                request.ApproverId);

            var directorResult = await WaitForApprovalStageAsync(
                context,
                "Director",
                directorId,
                TimeSpan.FromDays(5));

            if (directorResult.Status != ApprovalStatus.Approved)
            {
                return directorResult;
            }
        }

        // Stage 3: CFO approval (for amounts > $50,000)
        if (request.Amount > 50000)
        {
            var cfoId = await context.ScheduleTask<string>(
                typeof(GetCFOActivity),
                null);

            var cfoResult = await WaitForApprovalStageAsync(
                context,
                "CFO",
                cfoId,
                TimeSpan.FromDays(7));

            return cfoResult;
        }

        return new ApprovalResult
        {
            RequestId = request.RequestId,
            Status = ApprovalStatus.Approved,
            ApprovedBy = managerResult.ApprovedBy,
            ApprovedAt = context.CurrentUtcDateTime
        };
    }

    private async Task<ApprovalResult> WaitForApprovalStageAsync(
        OrchestrationContext context,
        string stage,
        string approverId,
        TimeSpan timeout)
    {
        _currentStage = stage;
        _currentApprovalHandle = new TaskCompletionSource<ApprovalResponse>();

        // Send notification for this stage
        await context.ScheduleTask<bool>(
            typeof(SendApprovalNotificationActivity),
            new { Stage = stage, ApproverId = approverId });

        using var cts = new CancellationTokenSource();
        var approvalTask = _currentApprovalHandle.Task;
        var timeoutTask = context.CreateTimer(
            context.CurrentUtcDateTime.Add(timeout),
            $"timeout-{stage}",
            cts.Token);

        var winner = await Task.WhenAny(approvalTask, timeoutTask);

        if (winner == approvalTask)
        {
            cts.Cancel();
            var response = await approvalTask;
            _currentApprovalHandle = null;
            _currentStage = null;

            return new ApprovalResult
            {
                RequestId = $"stage-{stage}",
                Status = response.IsApproved ? ApprovalStatus.Approved : ApprovalStatus.Rejected,
                ApprovedBy = response.ApprovedBy,
                ApprovedAt = response.IsApproved ? context.CurrentUtcDateTime : null,
                RejectionReason = response.RejectionReason
            };
        }
        else
        {
            _currentApprovalHandle = null;
            _currentStage = null;

            return new ApprovalResult
            {
                RequestId = $"stage-{stage}",
                Status = ApprovalStatus.TimedOut
            };
        }
    }

    public override void OnEvent(OrchestrationContext context, string name, string input)
    {
        if (name == $"ApprovalResponse-{_currentStage}" && _currentApprovalHandle is not null)
        {
            var response = context.MessageDataConverter.Deserialize<ApprovalResponse>(input);
            _currentApprovalHandle.SetResult(response);
        }
    }
}
```

---

## Monitor Pattern

Periodically check external system status until completion or timeout.

### When to Use
- Polling external APIs for job completion
- Waiting for async operations
- Health monitoring
- Long-running external processes

### Complete Implementation

```csharp
using DurableTask.Core;

namespace Workflows.Patterns;

public sealed record MonitoringInput
{
    public required string JobId { get; init; }
    public required string SystemName { get; init; }
    public TimeSpan Timeout { get; init; } = TimeSpan.FromHours(4);
    public TimeSpan InitialPollingInterval { get; init; } = TimeSpan.FromSeconds(30);
    public int MaxPollingInterval { get; init; } = 300; // 5 minutes max
    public double BackoffMultiplier { get; init; } = 1.5;
}

public sealed record MonitoringResult
{
    public required string JobId { get; init; }
    public required JobStatus Status { get; init; }
    public required bool TimedOut { get; init; }
    public required int PollCount { get; init; }
    public required TimeSpan TotalDuration { get; init; }
    public string? Output { get; init; }
    public string? ErrorMessage { get; init; }
}

public enum JobStatus
{
    Pending,
    Running,
    Completed,
    Failed,
    Unknown
}

public sealed record JobStatusResponse
{
    public required JobStatus Status { get; init; }
    public int PercentComplete { get; init; }
    public string? Output { get; init; }
    public string? ErrorMessage { get; init; }
}

/// <summary>
/// Monitor pattern with exponential backoff
/// Polls external system until completion or timeout
/// </summary>
public sealed class JobMonitoringOrchestration 
    : TaskOrchestration<MonitoringResult, MonitoringInput>
{
    public override async Task<MonitoringResult> RunTask(
        OrchestrationContext context,
        MonitoringInput input)
    {
        var startTime = context.CurrentUtcDateTime;
        var expirationTime = startTime.Add(input.Timeout);
        var pollingInterval = input.InitialPollingInterval;
        var pollCount = 0;

        while (context.CurrentUtcDateTime < expirationTime)
        {
            pollCount++;

            // Check job status
            var retryOptions = new RetryOptions(
                firstRetryInterval: TimeSpan.FromSeconds(5),
                maxNumberOfAttempts: 3)
            {
                BackoffCoefficient = 2.0,
                Handle = ex => ex is TimeoutException || ex is HttpRequestException
            };

            var statusResponse = await context.ScheduleWithRetry<JobStatusResponse>(
                typeof(CheckJobStatusActivity),
                retryOptions,
                new CheckJobStatusRequest
                {
                    JobId = input.JobId,
                    SystemName = input.SystemName
                });

            // Check if job completed
            if (statusResponse.Status == JobStatus.Completed)
            {
                // Job completed successfully
                return new MonitoringResult
                {
                    JobId = input.JobId,
                    Status = JobStatus.Completed,
                    TimedOut = false,
                    PollCount = pollCount,
                    TotalDuration = context.CurrentUtcDateTime - startTime,
                    Output = statusResponse.Output
                };
            }

            if (statusResponse.Status == JobStatus.Failed)
            {
                // Job failed
                return new MonitoringResult
                {
                    JobId = input.JobId,
                    Status = JobStatus.Failed,
                    TimedOut = false,
                    PollCount = pollCount,
                    TotalDuration = context.CurrentUtcDateTime - startTime,
                    ErrorMessage = statusResponse.ErrorMessage
                };
            }

            // Job still running - wait before next poll
            var nextPollTime = context.CurrentUtcDateTime.Add(pollingInterval);
            
            // Don't poll past expiration time
            if (nextPollTime > expirationTime)
            {
                break;
            }

            await context.CreateTimer(nextPollTime, true);

            // Exponential backoff up to max interval
            pollingInterval = TimeSpan.FromSeconds(
                Math.Min(
                    pollingInterval.TotalSeconds * input.BackoffMultiplier,
                    input.MaxPollingInterval));
        }

        // Timeout occurred
        return new MonitoringResult
        {
            JobId = input.JobId,
            Status = JobStatus.Unknown,
            TimedOut = true,
            PollCount = pollCount,
            TotalDuration = context.CurrentUtcDateTime - startTime
        };
    }
}

/// <summary>
/// Continuous monitoring with ContinueAsNew
/// For very long-running monitors that need to avoid history growth
/// </summary>
public sealed record ContinuousMonitoringState
{
    public required string TargetUrl { get; init; }
    public required TimeSpan CheckInterval { get; init; }
    public required int MaxConsecutiveFailures { get; init; }
    public int ConsecutiveFailures { get; init; } = 0;
    public DateTime? LastSuccessTime { get; init; }
    public int TotalChecks { get; init; } = 0;
}

public sealed class ContinuousMonitorOrchestration 
    : TaskOrchestration<object, ContinuousMonitoringState>
{
    public override async Task<object?> RunTask(
        OrchestrationContext context,
        ContinuousMonitoringState state)
    {
        // Perform health check
        var isHealthy = await context.ScheduleTask<bool>(
            typeof(HealthCheckActivity),
            state.TargetUrl);

        var newState = state with
        {
            TotalChecks = state.TotalChecks + 1,
            ConsecutiveFailures = isHealthy ? 0 : state.ConsecutiveFailures + 1,
            LastSuccessTime = isHealthy ? context.CurrentUtcDateTime : state.LastSuccessTime
        };

        // Send alert if consecutive failures exceed threshold
        if (newState.ConsecutiveFailures >= state.MaxConsecutiveFailures)
        {
            await context.ScheduleTask<bool>(
                typeof(SendAlertActivity),
                new Alert
                {
                    TargetUrl = state.TargetUrl,
                    ConsecutiveFailures = newState.ConsecutiveFailures,
                    LastSuccessTime = newState.LastSuccessTime
                });

            // Reset counter after alert
            newState = newState with { ConsecutiveFailures = 0 };
        }

        // Wait before next check
        await context.CreateTimer(
            context.CurrentUtcDateTime.Add(state.CheckInterval),
            true);

        // Reset history every 100 checks to avoid growth
        if (newState.TotalChecks >= 100)
        {
            newState = newState with { TotalChecks = 0 };
        }

        // Continue as new to reset history
        context.ContinueAsNew(newState);
        return null;
    }
}
```

---

## Saga Pattern (Compensation)

Implement distributed transactions with compensation logic.

### When to Use
- Multi-step transactions across services
- Need to undo completed steps on failure
- Financial transactions
- Order processing with inventory/payment

### Complete Implementation

```csharp
using DurableTask.Core;

namespace Workflows.Patterns;

public sealed record OrderInput
{
    public required string OrderId { get; init; }
    public required string CustomerId { get; init; }
    public required List<OrderItem> Items { get; init; }
    public required decimal TotalAmount { get; init; }
    public required ShippingAddress ShippingAddress { get; init; }
}

public sealed record OrderItem
{
    public required string ProductId { get; init; }
    public required int Quantity { get; init; }
    public required decimal UnitPrice { get; init; }
}

public sealed record ShippingAddress
{
    public required string Street { get; init; }
    public required string City { get; init; }
    public required string State { get; init; }
    public required string ZipCode { get; init; }
}

public sealed record OrderResult
{
    public required bool Success { get; init; }
    public string? TransactionId { get; init; }
    public string? ReservationId { get; init; }
    public string? ShipmentId { get; init; }
    public string? ErrorMessage { get; init; }
    public required List<string> CompletedSteps { get; init; }
    public required List<string> CompensatedSteps { get; init; }
}

/// <summary>
/// Saga pattern with compensation for distributed transactions
/// If any step fails, compensates all completed steps in reverse order
/// </summary>
public sealed class OrderSagaOrchestration 
    : TaskOrchestration<OrderResult, OrderInput>
{
    public override async Task<OrderResult> RunTask(
        OrchestrationContext context,
        OrderInput input)
    {
        var completedSteps = new List<string>();
        var compensatedSteps = new List<string>();
        string? reservationId = null;
        string? transactionId = null;
        string? shipmentId = null;

        try
        {
            // Step 1: Reserve inventory
            reservationId = await context.ScheduleTask<string>(
                typeof(ReserveInventoryActivity),
                new ReserveInventoryRequest
                {
                    OrderId = input.OrderId,
                    Items = input.Items
                });
            completedSteps.Add("InventoryReserved");

            // Step 2: Charge payment
            var retryOptions = new RetryOptions(
                firstRetryInterval: TimeSpan.FromSeconds(5),
                maxNumberOfAttempts: 3)
            {
                BackoffCoefficient = 2.0,
                Handle = ex => ex is TimeoutException
            };

            transactionId = await context.ScheduleWithRetry<string>(
                typeof(ChargePaymentActivity),
                retryOptions,
                new PaymentRequest
                {
                    OrderId = input.OrderId,
                    CustomerId = input.CustomerId,
                    Amount = input.TotalAmount,
                    IdempotencyKey = input.OrderId // Prevent duplicate charges
                });
            completedSteps.Add("PaymentCharged");

            // Step 3: Create shipment
            shipmentId = await context.ScheduleTask<string>(
                typeof(CreateShipmentActivity),
                new ShipmentRequest
                {
                    OrderId = input.OrderId,
                    Items = input.Items,
                    ShippingAddress = input.ShippingAddress,
                    ReservationId = reservationId
                });
            completedSteps.Add("ShipmentCreated");

            // Step 4: Send confirmation
            await context.ScheduleTask<bool>(
                typeof(SendOrderConfirmationActivity),
                new OrderConfirmation
                {
                    OrderId = input.OrderId,
                    CustomerId = input.CustomerId,
                    TransactionId = transactionId,
                    ShipmentId = shipmentId
                });
            completedSteps.Add("ConfirmationSent");

            return new OrderResult
            {
                Success = true,
                TransactionId = transactionId,
                ReservationId = reservationId,
                ShipmentId = shipmentId,
                CompletedSteps = completedSteps,
                CompensatedSteps = compensatedSteps
            };
        }
        catch (TaskFailedException ex)
        {
            // Saga failed - compensate in reverse order
            if (!context.IsReplaying)
            {
                context.CreateEvent(EventType.LogError,
                    $"Order saga failed at step: {completedSteps.LastOrDefault() ?? "Start"}. Starting compensation.");
            }

            // Compensate steps in reverse order
            if (completedSteps.Contains("ShipmentCreated") && shipmentId is not null)
            {
                try
                {
                    await context.ScheduleTask<bool>(
                        typeof(CancelShipmentActivity),
                        shipmentId);
                    compensatedSteps.Add("ShipmentCancelled");
                }
                catch (TaskFailedException compensationEx)
                {
                    // Log but continue with other compensations
                    if (!context.IsReplaying)
                    {
                        context.CreateEvent(EventType.LogError,
                            $"Failed to cancel shipment: {compensationEx.FailureDetails?.ErrorMessage}");
                    }
                }
            }

            if (completedSteps.Contains("PaymentCharged") && transactionId is not null)
            {
                try
                {
                    await context.ScheduleTask<bool>(
                        typeof(RefundPaymentActivity),
                        new RefundRequest
                        {
                            TransactionId = transactionId,
                            Amount = input.TotalAmount,
                            Reason = "Order processing failed"
                        });
                    compensatedSteps.Add("PaymentRefunded");
                }
                catch (TaskFailedException compensationEx)
                {
                    // Critical: payment refund failed - needs manual intervention
                    if (!context.IsReplaying)
                    {
                        context.CreateEvent(EventType.LogError,
                            $"CRITICAL: Failed to refund payment: {compensationEx.FailureDetails?.ErrorMessage}");
                    }

                    // Send alert for manual intervention
                    await context.ScheduleTask<bool>(
                        typeof(SendCriticalAlertActivity),
                        new CriticalAlert
                        {
                            OrderId = input.OrderId,
                            TransactionId = transactionId,
                            Issue = "Payment refund failed - manual intervention required"
                        });
                }
            }

            if (completedSteps.Contains("InventoryReserved") && reservationId is not null)
            {
                try
                {
                    await context.ScheduleTask<bool>(
                        typeof(ReleaseInventoryActivity),
                        reservationId);
                    compensatedSteps.Add("InventoryReleased");
                }
                catch (TaskFailedException compensationEx)
                {
                    if (!context.IsReplaying)
                    {
                        context.CreateEvent(EventType.LogError,
                            $"Failed to release inventory: {compensationEx.FailureDetails?.ErrorMessage}");
                    }
                }
            }

            return new OrderResult
            {
                Success = false,
                ErrorMessage = ex.FailureDetails?.ErrorMessage ?? "Unknown error",
                ReservationId = reservationId,
                TransactionId = transactionId,
                ShipmentId = shipmentId,
                CompletedSteps = completedSteps,
                CompensatedSteps = compensatedSteps
            };
        }
    }
}
```

---

## Eternal Orchestrations

Long-running orchestrations that periodically restart to prevent history growth.

### When to Use
- Continuous monitoring
- Scheduled jobs (cron-like)
- Long-running state machines
- Periodic batch processing

### Complete Implementation

```csharp
using DurableTask.Core;

namespace Workflows.Patterns;

public sealed record ScheduledJobState
{
    public required string JobName { get; init; }
    public required string CronExpression { get; init; }
    public required int ExecutionCount { get; init; }
    public DateTime? LastExecutionTime { get; init; }
    public DateTime? NextExecutionTime { get; init; }
    public int ConsecutiveFailures { get; init; }
}

/// <summary>
/// Eternal orchestration for scheduled jobs (cron-like)
/// Uses ContinueAsNew to prevent history growth
/// </summary>
public sealed class ScheduledJobOrchestration 
    : TaskOrchestration<object, ScheduledJobState>
{
    public override async Task<object?> RunTask(
        OrchestrationContext context,
        ScheduledJobState state)
    {
        // Calculate next execution time using cron expression
        var nextRun = CalculateNextRunTime(
            state.CronExpression,
            state.LastExecutionTime ?? context.CurrentUtcDateTime);

        // Wait until scheduled time
        if (context.CurrentUtcDateTime < nextRun)
        {
            await context.CreateTimer(nextRun, true);
        }

        // Execute the scheduled job
        var newState = state with
        {
            ExecutionCount = state.ExecutionCount + 1,
            LastExecutionTime = context.CurrentUtcDateTime,
            NextExecutionTime = nextRun
        };

        try
        {
            await context.ScheduleTask<bool>(
                typeof(ExecuteScheduledJobActivity),
                new ScheduledJobExecution
                {
                    JobName = state.JobName,
                    ExecutionCount = newState.ExecutionCount,
                    ExecutionTime = context.CurrentUtcDateTime
                });

            // Reset failure counter on success
            newState = newState with { ConsecutiveFailures = 0 };
        }
        catch (TaskFailedException ex)
        {
            newState = newState with
            {
                ConsecutiveFailures = state.ConsecutiveFailures + 1
            };

            // Send alert if too many consecutive failures
            if (newState.ConsecutiveFailures >= 5)
            {
                await context.ScheduleTask<bool>(
                    typeof(SendJobFailureAlertActivity),
                    new JobFailureAlert
                    {
                        JobName = state.JobName,
                        ConsecutiveFailures = newState.ConsecutiveFailures,
                        LastError = ex.FailureDetails?.ErrorMessage
                    });
            }
        }

        // Continue as new to reset history
        context.ContinueAsNew(newState);
        return null;
    }

    private DateTime CalculateNextRunTime(string cronExpression, DateTime fromTime)
    {
        // Use a cron parsing library like Cronos
        // Example: "0 0 * * *" = daily at midnight
        var expression = Cronos.CronExpression.Parse(cronExpression);
        return expression.GetNextOccurrence(fromTime, TimeZoneInfo.Utc)
               ?? throw new InvalidOperationException("No next occurrence found");
    }
}

/// <summary>
/// Stateful aggregator pattern
/// Accumulates events/data over time with periodic persistence
/// </summary>
public sealed record AggregatorState
{
    public required string AggregatorId { get; init; }
    public required int EventCount { get; init; }
    public required decimal TotalValue { get; init; }
    public required Dictionary<string, int> CategoryCounts { get; init; }
    public DateTime? LastSaveTime { get; init; }
    public DateTime? FirstEventTime { get; init; }
}

public sealed record DataPoint
{
    public required string Category { get; init; }
    public required decimal Value { get; init; }
    public DateTime Timestamp { get; init; }
}

public sealed class AggregatorOrchestration 
    : TaskOrchestration<object, AggregatorState>
{
    private TaskCompletionSource<DataPoint>? _eventHandle;

    public override async Task<object?> RunTask(
        OrchestrationContext context,
        AggregatorState state)
    {
        // Initialize state on first run
        var currentState = state.EventCount == 0
            ? state with { FirstEventTime = context.CurrentUtcDateTime }
            : state;

        using var cts = new CancellationTokenSource();
        
        // Wait for new data event or periodic save timer
        _eventHandle = new TaskCompletionSource<DataPoint>();
        var eventTask = _eventHandle.Task;
        var saveInterval = TimeSpan.FromMinutes(5);
        var saveTask = context.CreateTimer(
            context.CurrentUtcDateTime.Add(saveInterval),
            "save",
            cts.Token);

        var winner = await Task.WhenAny(eventTask, saveTask);
        cts.Cancel();

        if (winner == eventTask)
        {
            // New data received
            var dataPoint = await eventTask;
            _eventHandle = null;

            // Update aggregations
            var newCategoryCounts = new Dictionary<string, int>(currentState.CategoryCounts);
            newCategoryCounts.TryGetValue(dataPoint.Category, out var count);
            newCategoryCounts[dataPoint.Category] = count + 1;

            currentState = currentState with
            {
                EventCount = currentState.EventCount + 1,
                TotalValue = currentState.TotalValue + dataPoint.Value,
                CategoryCounts = newCategoryCounts
            };
        }
        else
        {
            // Periodic save
            _eventHandle = null;

            if (currentState.EventCount > 0)
            {
                // Persist current aggregations
                await context.ScheduleTask<bool>(
                    typeof(SaveAggregationsActivity),
                    new AggregationSnapshot
                    {
                        AggregatorId = currentState.AggregatorId,
                        EventCount = currentState.EventCount,
                        TotalValue = currentState.TotalValue,
                        CategoryCounts = currentState.CategoryCounts,
                        FirstEventTime = currentState.FirstEventTime,
                        LastSaveTime = context.CurrentUtcDateTime
                    });

                currentState = currentState with
                {
                    LastSaveTime = context.CurrentUtcDateTime
                };
            }
        }

        // Reset history every 1000 events to avoid growth
        if (currentState.EventCount >= 1000)
        {
            // Final save before reset
            await context.ScheduleTask<bool>(
                typeof(SaveAggregationsActivity),
                new AggregationSnapshot
                {
                    AggregatorId = currentState.AggregatorId,
                    EventCount = currentState.EventCount,
                    TotalValue = currentState.TotalValue,
                    CategoryCounts = currentState.CategoryCounts,
                    FirstEventTime = currentState.FirstEventTime,
                    LastSaveTime = context.CurrentUtcDateTime
                });

            // Reset counters but keep configuration
            currentState = new AggregatorState
            {
                AggregatorId = currentState.AggregatorId,
                EventCount = 0,
                TotalValue = 0,
                CategoryCounts = new Dictionary<string, int>(),
                LastSaveTime = context.CurrentUtcDateTime,
                FirstEventTime = null
            };
        }

        // Continue as new
        context.ContinueAsNew(currentState);
        return null;
    }

    public override void OnEvent(OrchestrationContext context, string name, string input)
    {
        if (name == "DataPoint" && _eventHandle is not null)
        {
            var dataPoint = context.MessageDataConverter.Deserialize<DataPoint>(input);
            _eventHandle.SetResult(dataPoint);
        }
    }
}
```

---

## Circuit Breaker

Prevent repeated calls to failing services with automatic recovery.

### When to Use
- Protecting against cascading failures
- Giving failing services time to recover
- Rate limiting external dependencies

### Complete Implementation

```csharp
using DurableTask.Core;

namespace Workflows.Patterns;

public sealed record CircuitBreakerState
{
    public required string ServiceName { get; init; }
    public required CircuitState State { get; init; }
    public required int ConsecutiveFailures { get; init; }
    public required int FailureThreshold { get; init; }
    public required TimeSpan CooldownPeriod { get; init; }
    public DateTime? LastFailureTime { get; init; }
    public DateTime? CircuitOpenedTime { get; init; }
}

public enum CircuitState
{
    Closed,    // Normal operation
    Open,      // Circuit breaker tripped - blocking requests
    HalfOpen   // Testing if service recovered
}

/// <summary>
/// Circuit breaker pattern for resilient external service calls
/// Automatically opens circuit after consecutive failures and retries after cooldown
/// </summary>
public sealed class CircuitBreakerOrchestration 
    : TaskOrchestration<object, CircuitBreakerState>
{
    public override async Task<object?> RunTask(
        OrchestrationContext context,
        CircuitBreakerState state)
    {
        var currentState = state;

        // Check if circuit should transition from Open to HalfOpen
        if (currentState.State == CircuitState.Open &&
            currentState.CircuitOpenedTime.HasValue)
        {
            var timeSinceOpen = context.CurrentUtcDateTime - currentState.CircuitOpenedTime.Value;
            if (timeSinceOpen >= currentState.CooldownPeriod)
            {
                // Transition to HalfOpen - will try one request
                currentState = currentState with
                {
                    State = CircuitState.HalfOpen
                };

                if (!context.IsReplaying)
                {
                    context.CreateEvent(EventType.LogInformation,
                        $"Circuit breaker for {currentState.ServiceName} transitioning to HalfOpen");
                }
            }
            else
            {
                // Still in cooldown - wait
                var remainingCooldown = currentState.CooldownPeriod - timeSinceOpen;
                await context.CreateTimer(
                    context.CurrentUtcDateTime.Add(remainingCooldown),
                    true);

                // Continue as new after cooldown
                context.ContinueAsNew(currentState);
                return null;
            }
        }

        // Try to call the service
        bool callSucceeded;
        try
        {
            if (currentState.State == CircuitState.Open)
            {
                // Circuit is open - reject request immediately
                throw new CircuitBreakerOpenException(
                    $"Circuit breaker is open for {currentState.ServiceName}");
            }

            // Make the call
            await context.ScheduleTask<bool>(
                typeof(CallExternalServiceActivity),
                currentState.ServiceName);

            callSucceeded = true;
        }
        catch (TaskFailedException)
        {
            callSucceeded = false;
        }

        // Update circuit state based on result
        if (callSucceeded)
        {
            // Success - reset circuit breaker
            currentState = currentState with
            {
                State = CircuitState.Closed,
                ConsecutiveFailures = 0,
                LastFailureTime = null,
                CircuitOpenedTime = null
            };

            if (!context.IsReplaying)
            {
                context.CreateEvent(EventType.LogInformation,
                    $"Circuit breaker for {currentState.ServiceName} reset to Closed");
            }
        }
        else
        {
            // Failure
            var newFailureCount = currentState.ConsecutiveFailures + 1;
            currentState = currentState with
            {
                ConsecutiveFailures = newFailureCount,
                LastFailureTime = context.CurrentUtcDateTime
            };

            // Check if we should open the circuit
            if (currentState.State == CircuitState.HalfOpen ||
                newFailureCount >= currentState.FailureThreshold)
            {
                currentState = currentState with
                {
                    State = CircuitState.Open,
                    CircuitOpenedTime = context.CurrentUtcDateTime
                };

                if (!context.IsReplaying)
                {
                    context.CreateEvent(EventType.LogWarning,
                        $"Circuit breaker OPENED for {currentState.ServiceName} after {newFailureCount} failures");
                }

                // Send alert
                await context.ScheduleTask<bool>(
                    typeof(SendCircuitBreakerAlertActivity),
                    new CircuitBreakerAlert
                    {
                        ServiceName = currentState.ServiceName,
                        ConsecutiveFailures = newFailureCount,
                        State = CircuitState.Open
                    });
            }
        }

        // Wait before next attempt (exponential backoff)
        var waitTime = CalculateWaitTime(currentState.ConsecutiveFailures);
        await context.CreateTimer(
            context.CurrentUtcDateTime.Add(waitTime),
            true);

        // Continue as new to reset history
        context.ContinueAsNew(currentState);
        return null;
    }

    private TimeSpan CalculateWaitTime(int failureCount)
    {
        // Exponential backoff: 1s, 2s, 4s, 8s, ..., max 60s
        var seconds = Math.Min(Math.Pow(2, failureCount), 60);
        return TimeSpan.FromSeconds(seconds);
    }
}

public class CircuitBreakerOpenException : Exception
{
    public CircuitBreakerOpenException(string message) : base(message) { }
}
```

---

## Pattern Selection Guide

### Decision Matrix

| Scenario | Pattern | Key Benefit |
|----------|---------|-------------|
| Steps must execute in order | Sequential | Simple, clear dependency chain |
| Process list of independent items | Fan-Out/Fan-In | Parallel execution, faster completion |
| Wait for human approval | Human Interaction | External event handling, timeout support |
| Poll external system until done | Monitor | Periodic checking with backoff |
| Multi-step transaction with rollback | Saga | Compensation on failure |
| Recurring job (cron-like) | Eternal + ContinueAsNew | Prevents history growth |
| Prevent cascading failures | Circuit Breaker | Service protection, automatic recovery |

### Combining Patterns

Real-world workflows often combine multiple patterns:

```csharp
/// <summary>
/// Complex workflow combining multiple patterns:
/// - Sequential steps (validation → processing → shipping)
/// - Fan-out for batch item processing
/// - Saga for compensation
/// - Human interaction for high-value orders
/// </summary>
public sealed class ComplexOrderOrchestration 
    : TaskOrchestration<OrderResult, OrderInput>
{
    private TaskCompletionSource<ApprovalResponse>? _approvalHandle;

    public override async Task<OrderResult> RunTask(
        OrchestrationContext context,
        OrderInput input)
    {
        var completedSteps = new List<string>();

        try
        {
            // Sequential: Validate order
            var validationResult = await context.ScheduleTask<ValidationResult>(
                typeof(ValidateOrderActivity),
                input);

            if (!validationResult.IsValid)
            {
                return new OrderResult
                {
                    Success = false,
                    ErrorMessage = validationResult.ErrorMessage
                };
            }
            completedSteps.Add("Validated");

            // Human Interaction: High-value orders need approval
            if (input.TotalAmount > 10000)
            {
                _approvalHandle = new TaskCompletionSource<ApprovalResponse>();
                
                await context.ScheduleTask<bool>(
                    typeof(SendApprovalRequestActivity),
                    input);

                using var cts = new CancellationTokenSource();
                var approvalTask = _approvalHandle.Task;
                var timeoutTask = context.CreateTimer(
                    context.CurrentUtcDateTime.AddDays(2),
                    "approval-timeout",
                    cts.Token);

                var winner = await Task.WhenAny(approvalTask, timeoutTask);
                if (winner == timeoutTask || !(await approvalTask).IsApproved)
                {
                    return new OrderResult
                    {
                        Success = false,
                        ErrorMessage = "Approval denied or timed out"
                    };
                }
                cts.Cancel();
                completedSteps.Add("Approved");
            }

            // Saga Step 1: Reserve inventory
            var reservationId = await context.ScheduleTask<string>(
                typeof(ReserveInventoryActivity),
                input.Items);
            completedSteps.Add("InventoryReserved");

            // Fan-out: Process items in parallel
            var itemTasks = input.Items.Select(item =>
                context.ScheduleTask<ProcessedItem>(
                    typeof(ProcessItemActivity),
                    item)).ToList();
            var processedItems = await Task.WhenAll(itemTasks);
            completedSteps.Add("ItemsProcessed");

            // Saga Step 2: Charge payment
            var transactionId = await context.ScheduleTask<string>(
                typeof(ChargePaymentActivity),
                new PaymentRequest
                {
                    OrderId = input.OrderId,
                    Amount = input.TotalAmount,
                    CustomerId = input.CustomerId
                });
            completedSteps.Add("PaymentCharged");

            // Sequential: Ship order
            var shipmentId = await context.ScheduleTask<string>(
                typeof(ShipOrderActivity),
                new ShipmentRequest
                {
                    OrderId = input.OrderId,
                    Items = processedItems.ToList()
                });
            completedSteps.Add("Shipped");

            return new OrderResult
            {
                Success = true,
                TransactionId = transactionId,
                ShipmentId = shipmentId
            };
        }
        catch (TaskFailedException ex)
        {
            // Saga: Compensate completed steps
            await CompensateAsync(context, completedSteps, input);

            return new OrderResult
            {
                Success = false,
                ErrorMessage = ex.FailureDetails?.ErrorMessage
            };
        }
    }

    private async Task CompensateAsync(
        OrchestrationContext context,
        List<string> completedSteps,
        OrderInput input)
    {
        // Compensate in reverse order
        if (completedSteps.Contains("PaymentCharged"))
        {
            await context.ScheduleTask<bool>(
                typeof(RefundPaymentActivity),
                input.OrderId);
        }

        if (completedSteps.Contains("InventoryReserved"))
        {
            await context.ScheduleTask<bool>(
                typeof(ReleaseInventoryActivity),
                input.OrderId);
        }
    }

    public override void OnEvent(OrchestrationContext context, string name, string input)
    {
        if (name == "ApprovalResponse" && _approvalHandle is not null)
        {
            var response = context.MessageDataConverter.Deserialize<ApprovalResponse>(input);
            _approvalHandle.SetResult(response);
        }
    }
}
```

---

**Next**: [03-ADVANCED.md](./03-ADVANCED.md) - Advanced features including retries, error handling, external events, sub-orchestrations, timers, and versioning.
