# 03 - ADVANCED FEATURES

**Deep dive into retry policies, error handling, external events, sub-orchestrations, timers, and versioning strategies.**

---

## Table of Contents

1. [Retry Policies](#retry-policies)
2. [Error Handling](#error-handling)
3. [External Events](#external-events)
4. [Sub-Orchestrations](#sub-orchestrations)
5. [Timers and Timeouts](#timers-and-timeouts)
6. [Versioning Strategies](#versioning-strategies)
7. [Advanced Patterns Reference](#advanced-patterns-reference)

---

## Retry Policies

### RetryOptions Configuration

```csharp
using DurableTask.Core;

namespace AdvancedRetry;

/// <summary>
/// Comprehensive retry policy configurations for different scenarios.
/// </summary>
public static class RetryPolicyFactory
{
    /// <summary>
    /// Standard retry for transient failures (network, database timeouts).
    /// </summary>
    public static RetryOptions TransientFailurePolicy => new(
        firstRetryInterval: TimeSpan.FromSeconds(2),
        maxNumberOfAttempts: 5)
    {
        BackoffCoefficient = 2.0,        // Exponential backoff: 2s, 4s, 8s, 16s, 32s
        MaxRetryInterval = TimeSpan.FromMinutes(5),
        RetryTimeout = TimeSpan.FromMinutes(30)
    };

    /// <summary>
    /// Aggressive retry for critical operations.
    /// </summary>
    public static RetryOptions CriticalOperationPolicy => new(
        firstRetryInterval: TimeSpan.FromSeconds(1),
        maxNumberOfAttempts: 10)
    {
        BackoffCoefficient = 1.5,
        MaxRetryInterval = TimeSpan.FromMinutes(2),
        RetryTimeout = TimeSpan.FromHours(1)
    };

    /// <summary>
    /// Patient retry for rate-limited external APIs.
    /// </summary>
    public static RetryOptions RateLimitedApiPolicy => new(
        firstRetryInterval: TimeSpan.FromSeconds(30),
        maxNumberOfAttempts: 20)
    {
        BackoffCoefficient = 1.2,
        MaxRetryInterval = TimeSpan.FromMinutes(10),
        RetryTimeout = TimeSpan.FromHours(4)
    };

    /// <summary>
    /// No retry - fail fast for validation errors.
    /// </summary>
    public static RetryOptions NoRetryPolicy => new(
        firstRetryInterval: TimeSpan.FromSeconds(1),
        maxNumberOfAttempts: 1);
}
```

### Custom Retry Handler

```csharp
using DurableTask.Core;
using DurableTask.Core.Exceptions;

namespace AdvancedRetry;

/// <summary>
/// Orchestration with intelligent retry handling based on exception types.
/// </summary>
public sealed class SmartRetryOrchestration : TaskOrchestration<string, OrderRequest>
{
    public override async Task<string> RunTask(OrchestrationContext context, OrderRequest input)
    {
        var retryPolicy = new RetryOptions(
            firstRetryInterval: TimeSpan.FromSeconds(3),
            maxNumberOfAttempts: 5)
        {
            BackoffCoefficient = 2.0,
            MaxRetryInterval = TimeSpan.FromMinutes(5),
            // Custom handler to decide if exception is retryable
            Handle = exception => ShouldRetry(exception)
        };

        try
        {
            // Validate input - no retry for validation errors
            await context.ScheduleTask<bool>(
                typeof(ValidateOrderActivity),
                input);

            // Process payment with smart retry
            var paymentId = await context.ScheduleWithRetry<string>(
                typeof(ProcessPaymentActivity),
                retryPolicy,
                input);

            // Ship order with transient failure retry
            await context.ScheduleWithRetry<bool>(
                typeof(ShipOrderActivity),
                RetryPolicyFactory.TransientFailurePolicy,
                new ShipmentRequest(input.OrderId, paymentId));

            return $"Order {input.OrderId} completed successfully";
        }
        catch (TaskFailedException ex) when (ex.IsCausedBy<ValidationException>())
        {
            // Don't retry validation failures - return user-friendly message
            return $"Order {input.OrderId} validation failed: {ex.InnerException?.Message}";
        }
        catch (TaskFailedException ex) when (ex.IsCausedBy<PaymentDeclinedException>())
        {
            // Payment declined is permanent - don't retry
            await context.ScheduleTask<bool>(
                typeof(NotifyCustomerActivity),
                new Notification(input.CustomerId, "Payment declined"));
            
            return $"Order {input.OrderId} payment declined";
        }
    }

    private static bool ShouldRetry(Exception exception)
    {
        return exception switch
        {
            // Retry transient failures
            TimeoutException => true,
            HttpRequestException => true,
            SqlException { Number: 1205 or -2 } => true, // Deadlock or timeout
            
            // Don't retry business logic failures
            ValidationException => false,
            PaymentDeclinedException => false,
            InsufficientInventoryException => false,
            
            // Default: retry unknown exceptions
            _ => true
        };
    }
}

public sealed class ValidationException : Exception
{
    public ValidationException(string message) : base(message) { }
}

public sealed class PaymentDeclinedException : Exception
{
    public PaymentDeclinedException(string reason) : base(reason) { }
}

public sealed class InsufficientInventoryException : Exception
{
    public InsufficientInventoryException(string productId) 
        : base($"Product {productId} out of stock") { }
}
```

### Retry with Circuit Breaker

```csharp
using DurableTask.Core;
using System.Collections.Concurrent;

namespace AdvancedRetry;

/// <summary>
/// Circuit breaker to prevent cascading failures when external service is down.
/// </summary>
public sealed class CircuitBreakerOrchestration : TaskOrchestration<ProcessingResult, BatchRequest>
{
    private static readonly ConcurrentDictionary<string, CircuitBreakerState> CircuitBreakers = new();

    public override async Task<ProcessingResult> RunTask(
        OrchestrationContext context, 
        BatchRequest input)
    {
        var serviceName = "ExternalPaymentService";
        var circuitKey = $"{serviceName}_{context.CurrentUtcDateTime:yyyyMMddHH}";
        
        var state = CircuitBreakers.GetOrAdd(circuitKey, _ => new CircuitBreakerState());

        // Check circuit breaker state
        if (state.IsOpen && context.CurrentUtcDateTime < state.OpenUntil)
        {
            // Circuit is open - fail fast without retrying
            return new ProcessingResult
            {
                Success = false,
                Message = $"Circuit breaker open for {serviceName}. Will retry after {state.OpenUntil}"
            };
        }

        var retryPolicy = new RetryOptions(
            firstRetryInterval: TimeSpan.FromSeconds(2),
            maxNumberOfAttempts: 3)
        {
            BackoffCoefficient = 2.0,
            Handle = ex => 
            {
                // Track failures for circuit breaker
                if (ex is HttpRequestException or TimeoutException)
                {
                    state.RecordFailure();
                    
                    // Open circuit if threshold exceeded
                    if (state.FailureCount >= 5)
                    {
                        state.OpenCircuit(context.CurrentUtcDateTime.AddMinutes(5));
                        return false; // Don't retry
                    }
                }
                return true;
            }
        };

        try
        {
            var result = await context.ScheduleWithRetry<string>(
                typeof(CallExternalServiceActivity),
                retryPolicy,
                input);

            state.RecordSuccess(); // Reset failure count
            return new ProcessingResult { Success = true, Data = result };
        }
        catch (TaskFailedException ex)
        {
            return new ProcessingResult 
            { 
                Success = false, 
                Message = ex.Message 
            };
        }
    }
}

public sealed class CircuitBreakerState
{
    private int _failureCount;
    private DateTime _openUntil;

    public int FailureCount => _failureCount;
    public bool IsOpen => DateTime.UtcNow < _openUntil;
    public DateTime OpenUntil => _openUntil;

    public void RecordFailure() => Interlocked.Increment(ref _failureCount);
    
    public void RecordSuccess() => Interlocked.Exchange(ref _failureCount, 0);
    
    public void OpenCircuit(DateTime until) => _openUntil = until;
}

public sealed record ProcessingResult
{
    public required bool Success { get; init; }
    public string? Data { get; init; }
    public string? Message { get; init; }
}
```

---

## Error Handling

### ErrorPropagationMode Configuration

**CRITICAL**: Always use `UseFailureDetails` mode for proper exception handling.

```csharp
using DurableTask.Core;
using Microsoft.Extensions.Logging;

namespace AdvancedErrorHandling;

/// <summary>
/// Proper TaskHubWorker configuration with UseFailureDetails mode.
/// </summary>
public sealed class TaskHubConfiguration
{
    public static TaskHubWorker CreateWorker(
        IOrchestrationService orchestrationService,
        ILoggerFactory loggerFactory)
    {
        var worker = new TaskHubWorker(orchestrationService, loggerFactory)
        {
            // REQUIRED: Enable detailed failure information
            ErrorPropagationMode = ErrorPropagationMode.UseFailureDetails
        };

        return worker;
    }
}
```

### IsCausedBy<T> Pattern

```csharp
using DurableTask.Core;
using DurableTask.Core.Exceptions;

namespace AdvancedErrorHandling;

/// <summary>
/// Comprehensive error handling with typed exception checking.
/// </summary>
public sealed class RobustOrchestration : TaskOrchestration<OrderResult, OrderRequest>
{
    public override async Task<OrderResult> RunTask(OrchestrationContext context, OrderRequest input)
    {
        try
        {
            // Step 1: Validate order
            await context.ScheduleTask<bool>(typeof(ValidateOrderActivity), input);
        }
        catch (TaskFailedException ex) when (ex.IsCausedBy<ArgumentNullException>())
        {
            return OrderResult.Failed("Missing required order information");
        }
        catch (TaskFailedException ex) when (ex.IsCausedBy<ValidationException>())
        {
            var validationEx = ex.GetCause<ValidationException>();
            return OrderResult.Failed($"Validation failed: {validationEx?.Message}");
        }

        string paymentId;
        try
        {
            // Step 2: Process payment
            paymentId = await context.ScheduleTask<string>(
                typeof(ProcessPaymentActivity), 
                input);
        }
        catch (TaskFailedException ex) when (ex.IsCausedBy<PaymentDeclinedException>())
        {
            var paymentEx = ex.GetCause<PaymentDeclinedException>();
            await NotifyCustomer(context, input.CustomerId, 
                $"Payment declined: {paymentEx?.Message}");
            
            return OrderResult.PaymentFailed(paymentEx?.Message ?? "Unknown reason");
        }
        catch (TaskFailedException ex) when (ex.IsCausedBy<InsufficientFundsException>())
        {
            await NotifyCustomer(context, input.CustomerId, "Insufficient funds");
            return OrderResult.PaymentFailed("Insufficient funds");
        }

        try
        {
            // Step 3: Reserve inventory
            await context.ScheduleTask<bool>(
                typeof(ReserveInventoryActivity), 
                input);
        }
        catch (TaskFailedException ex) when (ex.IsCausedBy<InsufficientInventoryException>())
        {
            // Compensate: Refund payment
            await context.ScheduleTask<bool>(
                typeof(RefundPaymentActivity), 
                paymentId);
            
            await NotifyCustomer(context, input.CustomerId, "Item out of stock - refunded");
            return OrderResult.OutOfStock();
        }

        try
        {
            // Step 4: Ship order
            await context.ScheduleTask<bool>(
                typeof(ShipOrderActivity), 
                new ShipmentRequest(input.OrderId, paymentId));
            
            return OrderResult.Success(input.OrderId, paymentId);
        }
        catch (TaskFailedException ex) when (ex.IsCausedBy<ShippingException>())
        {
            // Shipping failed but payment succeeded - log for manual intervention
            await context.ScheduleTask<bool>(
                typeof(LogFailedShipmentActivity),
                new FailedShipment(input.OrderId, paymentId, ex.Message));
            
            return OrderResult.ShippingFailed(
                "Order paid but shipping failed - customer service will contact you");
        }
        catch (Exception ex)
        {
            // Unknown error - log and fail safely
            await context.ScheduleTask<bool>(
                typeof(LogCriticalErrorActivity),
                new ErrorLog(input.OrderId, ex.ToString()));
            
            throw; // Re-throw to mark orchestration as failed
        }
    }

    private static Task NotifyCustomer(
        OrchestrationContext context, 
        string customerId, 
        string message)
    {
        return context.ScheduleTask<bool>(
            typeof(SendNotificationActivity),
            new Notification(customerId, message));
    }
}

/// <summary>
/// Result discriminated union for order processing.
/// </summary>
public sealed record OrderResult
{
    public required OrderStatus Status { get; init; }
    public string? OrderId { get; init; }
    public string? PaymentId { get; init; }
    public string? ErrorMessage { get; init; }

    public static OrderResult Success(string orderId, string paymentId) => new()
    {
        Status = OrderStatus.Success,
        OrderId = orderId,
        PaymentId = paymentId
    };

    public static OrderResult Failed(string message) => new()
    {
        Status = OrderStatus.ValidationFailed,
        ErrorMessage = message
    };

    public static OrderResult PaymentFailed(string reason) => new()
    {
        Status = OrderStatus.PaymentFailed,
        ErrorMessage = reason
    };

    public static OrderResult OutOfStock() => new()
    {
        Status = OrderStatus.OutOfStock,
        ErrorMessage = "Item unavailable"
    };

    public static OrderResult ShippingFailed(string message) => new()
    {
        Status = OrderStatus.ShippingFailed,
        ErrorMessage = message
    };
}

public enum OrderStatus
{
    Success,
    ValidationFailed,
    PaymentFailed,
    OutOfStock,
    ShippingFailed
}
```

### FailureDetails API

```csharp
using DurableTask.Core;
using DurableTask.Core.Exceptions;
using System.Text.Json;

namespace AdvancedErrorHandling;

/// <summary>
/// Working with FailureDetails for rich error information.
/// </summary>
public sealed class DetailedErrorOrchestration : TaskOrchestration<ErrorReport, string>
{
    public override async Task<ErrorReport> RunTask(OrchestrationContext context, string input)
    {
        try
        {
            await context.ScheduleTask<bool>(typeof(RiskyActivity), input);
            return ErrorReport.Success();
        }
        catch (TaskFailedException ex)
        {
            var failureDetails = ex.FailureDetails;
            
            return new ErrorReport
            {
                IsSuccess = false,
                ErrorType = failureDetails.ErrorType,
                ErrorMessage = failureDetails.ErrorMessage,
                StackTrace = failureDetails.StackTrace,
                
                // Check for specific exception types
                IsTimeout = ex.IsCausedBy<TimeoutException>(),
                IsValidationError = ex.IsCausedBy<ValidationException>(),
                IsNetworkError = ex.IsCausedBy<HttpRequestException>(),
                
                // Get inner exception details
                InnerException = failureDetails.InnerFailure?.ErrorMessage,
                
                // Serialize full details for logging
                FullDetails = JsonSerializer.Serialize(failureDetails, new JsonSerializerOptions 
                { 
                    WriteIndented = true 
                })
            };
        }
    }
}

public sealed record ErrorReport
{
    public required bool IsSuccess { get; init; }
    public string? ErrorType { get; init; }
    public string? ErrorMessage { get; init; }
    public string? StackTrace { get; init; }
    public bool IsTimeout { get; init; }
    public bool IsValidationError { get; init; }
    public bool IsNetworkError { get; init; }
    public string? InnerException { get; init; }
    public string? FullDetails { get; init; }

    public static ErrorReport Success() => new() { IsSuccess = true };
}
```

---

## External Events

### Basic Event Handling

```csharp
using DurableTask.Core;

namespace ExternalEvents;

/// <summary>
/// Orchestration waiting for external event (e.g., manual approval).
/// </summary>
public sealed class ApprovalOrchestration : TaskOrchestration<ApprovalResult, ApprovalRequest>
{
    public override async Task<ApprovalResult> RunTask(
        OrchestrationContext context, 
        ApprovalRequest input)
    {
        // Send approval request notification
        await context.ScheduleTask<bool>(
            typeof(SendApprovalRequestActivity),
            input);

        // Wait for approval event (external signal)
        var approvalEvent = context.WaitForExternalEvent<ApprovalDecision>("ApprovalDecision");
        
        // Wait for timeout
        var timeout = context.CreateTimer(
            context.CurrentUtcDateTime.AddDays(3), 
            CancellationToken.None);

        // Race between approval and timeout
        var winner = await Task.WhenAny(approvalEvent, timeout);

        if (winner == approvalEvent)
        {
            var decision = await approvalEvent;
            
            if (decision.Approved)
            {
                // Process approved request
                await context.ScheduleTask<bool>(
                    typeof(ProcessApprovedRequestActivity),
                    input);
                
                return ApprovalResult.Approved(decision.ApprovedBy, decision.Comments);
            }
            else
            {
                return ApprovalResult.Rejected(decision.ApprovedBy, decision.Comments);
            }
        }
        else
        {
            // Timeout occurred
            await context.ScheduleTask<bool>(
                typeof(NotifyTimeoutActivity),
                input);
            
            return ApprovalResult.Timeout();
        }
    }
}

// Client code to send event
public sealed class ApprovalClient
{
    private readonly TaskHubClient _client;

    public ApprovalClient(TaskHubClient client)
    {
        _client = client;
    }

    public async Task SendApprovalDecision(
        string instanceId, 
        ApprovalDecision decision)
    {
        await _client.RaiseEventAsync(
            instanceId, 
            "ApprovalDecision", 
            decision);
    }
}

public sealed record ApprovalDecision
{
    public required bool Approved { get; init; }
    public required string ApprovedBy { get; init; }
    public string? Comments { get; init; }
}

public sealed record ApprovalResult
{
    public required ApprovalStatus Status { get; init; }
    public string? ApprovedBy { get; init; }
    public string? Comments { get; init; }

    public static ApprovalResult Approved(string approvedBy, string? comments) => new()
    {
        Status = ApprovalStatus.Approved,
        ApprovedBy = approvedBy,
        Comments = comments
    };

    public static ApprovalResult Rejected(string rejectedBy, string? reason) => new()
    {
        Status = ApprovalStatus.Rejected,
        ApprovedBy = rejectedBy,
        Comments = reason
    };

    public static ApprovalResult Timeout() => new()
    {
        Status = ApprovalStatus.Timeout
    };
}

public enum ApprovalStatus { Approved, Rejected, Timeout }
```

### Multiple Event Handling

```csharp
using DurableTask.Core;

namespace ExternalEvents;

/// <summary>
/// Orchestration handling multiple different external events.
/// </summary>
public sealed class MultiEventOrchestration : TaskOrchestration<ProcessingResult, WorkItem>
{
    public override async Task<ProcessingResult> RunTask(
        OrchestrationContext context, 
        WorkItem input)
    {
        // Start processing
        await context.ScheduleTask<bool>(typeof(StartProcessingActivity), input);

        // Wait for multiple possible events
        var completedEvent = context.WaitForExternalEvent<CompletionData>("Completed");
        var cancelledEvent = context.WaitForExternalEvent<CancellationReason>("Cancelled");
        var pausedEvent = context.WaitForExternalEvent<PauseRequest>("Paused");

        while (true)
        {
            var winner = await Task.WhenAny(completedEvent, cancelledEvent, pausedEvent);

            if (winner == completedEvent)
            {
                var data = await completedEvent;
                return ProcessingResult.Completed(data);
            }
            else if (winner == cancelledEvent)
            {
                var reason = await cancelledEvent;
                await context.ScheduleTask<bool>(typeof(CleanupActivity), input);
                return ProcessingResult.Cancelled(reason);
            }
            else if (winner == pausedEvent)
            {
                var pauseRequest = await pausedEvent;
                
                // Pause processing
                await context.ScheduleTask<bool>(typeof(PauseProcessingActivity), input);
                
                // Wait for resume event
                var resumeEvent = context.WaitForExternalEvent<ResumeRequest>("Resumed");
                var resume = await resumeEvent;
                
                // Resume processing
                await context.ScheduleTask<bool>(typeof(ResumeProcessingActivity), input);
                
                // Continue waiting for completion or cancellation
                completedEvent = context.WaitForExternalEvent<CompletionData>("Completed");
                cancelledEvent = context.WaitForExternalEvent<CancellationReason>("Cancelled");
                pausedEvent = context.WaitForExternalEvent<PauseRequest>("Paused");
            }
        }
    }
}
```

### Event Buffering Pattern

```csharp
using DurableTask.Core;
using System.Collections.Immutable;

namespace ExternalEvents;

/// <summary>
/// Orchestration that buffers multiple events before processing.
/// </summary>
public sealed class EventBufferOrchestration : TaskOrchestration<BatchResult, BatchConfig>
{
    public override async Task<BatchResult> RunTask(
        OrchestrationContext context, 
        BatchConfig input)
    {
        var events = new List<DataEvent>();
        var flushTimer = context.CreateTimer(
            context.CurrentUtcDateTime.Add(input.BufferDuration), 
            CancellationToken.None);

        while (events.Count < input.MaxBatchSize)
        {
            var dataEvent = context.WaitForExternalEvent<DataEvent>("DataReceived");
            var winner = await Task.WhenAny(dataEvent, flushTimer);

            if (winner == dataEvent)
            {
                var evt = await dataEvent;
                events.Add(evt);
            }
            else
            {
                // Timeout - flush buffer
                break;
            }
        }

        if (events.Count == 0)
        {
            return BatchResult.Empty();
        }

        // Process batched events
        var result = await context.ScheduleTask<string>(
            typeof(ProcessBatchActivity),
            events.ToImmutableArray());

        return BatchResult.Success(events.Count, result);
    }
}

public sealed record BatchConfig
{
    public required int MaxBatchSize { get; init; }
    public required TimeSpan BufferDuration { get; init; }
}

public sealed record DataEvent
{
    public required string EventId { get; init; }
    public required string Data { get; init; }
    public required DateTime Timestamp { get; init; }
}

public sealed record BatchResult
{
    public required bool IsSuccess { get; init; }
    public int EventCount { get; init; }
    public string? ProcessingResult { get; init; }

    public static BatchResult Success(int count, string result) => new()
    {
        IsSuccess = true,
        EventCount = count,
        ProcessingResult = result
    };

    public static BatchResult Empty() => new()
    {
        IsSuccess = false,
        EventCount = 0
    };
}
```

---

## Sub-Orchestrations

### When to Use Sub-Orchestrations vs Activities

| Feature | Activity | Sub-Orchestration |
|---------|----------|-------------------|
| **Complexity** | Simple, single operation | Complex, multi-step workflow |
| **Retry** | Entire activity retries | Individual steps retry independently |
| **History** | Single event | Separate history (reduces parent history size) |
| **Reusability** | Reusable function | Reusable workflow |
| **Performance** | Faster (less overhead) | Slower (creates child instance) |
| **Use Case** | I/O operations, API calls | Business workflows, nested processes |

### Basic Sub-Orchestration

```csharp
using DurableTask.Core;

namespace SubOrchestrations;

/// <summary>
/// Parent orchestration coordinating multiple sub-orchestrations.
/// </summary>
public sealed class OrderProcessingOrchestration : TaskOrchestration<OrderSummary, OrderRequest>
{
    public override async Task<OrderSummary> RunTask(
        OrchestrationContext context, 
        OrderRequest input)
    {
        // Process payment as sub-orchestration
        var paymentResult = await context.CreateSubOrchestrationInstance<PaymentResult>(
            typeof(PaymentOrchestration),
            input.PaymentInfo);

        if (!paymentResult.Success)
        {
            return OrderSummary.Failed("Payment failed");
        }

        // Process shipment as sub-orchestration
        var shipmentResult = await context.CreateSubOrchestrationInstance<ShipmentResult>(
            typeof(ShipmentOrchestration),
            new ShipmentRequest(input.OrderId, paymentResult.TransactionId));

        if (!shipmentResult.Success)
        {
            // Compensate: Refund payment
            await context.CreateSubOrchestrationInstance<RefundResult>(
                typeof(RefundOrchestration),
                paymentResult.TransactionId);
            
            return OrderSummary.Failed("Shipment failed - refunded");
        }

        return OrderSummary.Success(
            input.OrderId, 
            paymentResult.TransactionId, 
            shipmentResult.TrackingNumber);
    }
}

/// <summary>
/// Payment sub-orchestration with multiple steps.
/// </summary>
public sealed class PaymentOrchestration : TaskOrchestration<PaymentResult, PaymentInfo>
{
    public override async Task<PaymentResult> RunTask(
        OrchestrationContext context, 
        PaymentInfo input)
    {
        // Step 1: Validate payment method
        var isValid = await context.ScheduleTask<bool>(
            typeof(ValidatePaymentActivity),
            input);

        if (!isValid)
        {
            return PaymentResult.Invalid();
        }

        // Step 2: Authorize payment
        var authCode = await context.ScheduleTask<string>(
            typeof(AuthorizePaymentActivity),
            input);

        // Step 3: Capture payment
        var transactionId = await context.ScheduleTask<string>(
            typeof(CapturePaymentActivity),
            new CaptureRequest(authCode, input.Amount));

        // Step 4: Record transaction
        await context.ScheduleTask<bool>(
            typeof(RecordTransactionActivity),
            transactionId);

        return PaymentResult.Successful(transactionId);
    }
}

public sealed record PaymentResult
{
    public required bool Success { get; init; }
    public string? TransactionId { get; init; }

    public static PaymentResult Successful(string transactionId) => new()
    {
        Success = true,
        TransactionId = transactionId
    };

    public static PaymentResult Invalid() => new() { Success = false };
}
```

### Fan-Out with Sub-Orchestrations

```csharp
using DurableTask.Core;

namespace SubOrchestrations;

/// <summary>
/// Process multiple orders in parallel using sub-orchestrations.
/// </summary>
public sealed class BatchOrderOrchestration : TaskOrchestration<BatchSummary, BatchOrderRequest>
{
    public override async Task<BatchSummary> RunTask(
        OrchestrationContext context, 
        BatchOrderRequest input)
    {
        // Create unique instance IDs for each sub-orchestration
        var tasks = input.Orders.Select(order =>
        {
            var instanceId = $"{context.OrchestrationInstance.InstanceId}:Order:{order.OrderId}";
            
            return context.CreateSubOrchestrationInstance<OrderSummary>(
                typeof(OrderProcessingOrchestration),
                instanceId,
                order);
        }).ToArray();

        // Wait for all sub-orchestrations
        var results = await Task.WhenAll(tasks);

        var successCount = results.Count(r => r.Success);
        var failureCount = results.Length - successCount;

        return new BatchSummary
        {
            TotalOrders = results.Length,
            SuccessCount = successCount,
            FailureCount = failureCount,
            Results = results
        };
    }
}

public sealed record BatchSummary
{
    public required int TotalOrders { get; init; }
    public required int SuccessCount { get; init; }
    public required int FailureCount { get; init; }
    public required OrderSummary[] Results { get; init; }
}
```

### Hierarchical Workflows

```csharp
using DurableTask.Core;

namespace SubOrchestrations;

/// <summary>
/// Three-level hierarchical workflow: Campaign → Batch → Order
/// </summary>
public sealed class MarketingCampaignOrchestration : TaskOrchestration<CampaignResult, Campaign>
{
    public override async Task<CampaignResult> RunTask(
        OrchestrationContext context, 
        Campaign input)
    {
        var batchResults = new List<BatchSummary>();

        // Process campaign in batches
        for (int i = 0; i < input.Batches.Length; i++)
        {
            var batch = input.Batches[i];
            var instanceId = $"{context.OrchestrationInstance.InstanceId}:Batch{i}";

            var batchResult = await context.CreateSubOrchestrationInstance<BatchSummary>(
                typeof(BatchOrderOrchestration),
                instanceId,
                batch);

            batchResults.Add(batchResult);

            // Add delay between batches
            await context.CreateTimer(
                context.CurrentUtcDateTime.AddMinutes(5), 
                CancellationToken.None);
        }

        return new CampaignResult
        {
            CampaignId = input.CampaignId,
            TotalBatches = batchResults.Count,
            TotalOrders = batchResults.Sum(b => b.TotalOrders),
            SuccessfulOrders = batchResults.Sum(b => b.SuccessCount),
            FailedOrders = batchResults.Sum(b => b.FailureCount)
        };
    }
}

public sealed record Campaign
{
    public required string CampaignId { get; init; }
    public required BatchOrderRequest[] Batches { get; init; }
}

public sealed record CampaignResult
{
    public required string CampaignId { get; init; }
    public required int TotalBatches { get; init; }
    public required int TotalOrders { get; init; }
    public required int SuccessfulOrders { get; init; }
    public required int FailedOrders { get; init; }
}
```

---

## Timers and Timeouts

### Basic Timer Usage

```csharp
using DurableTask.Core;

namespace Timers;

/// <summary>
/// Orchestration with scheduled timer.
/// </summary>
public sealed class ScheduledTaskOrchestration : TaskOrchestration<string, ScheduleRequest>
{
    public override async Task<string> RunTask(
        OrchestrationContext context, 
        ScheduleRequest input)
    {
        // Wait until scheduled time
        await context.CreateTimer(input.ScheduledTime, CancellationToken.None);

        // Execute scheduled task
        await context.ScheduleTask<bool>(typeof(ExecuteTaskActivity), input.TaskData);

        return $"Task executed at {context.CurrentUtcDateTime}";
    }
}

public sealed record ScheduleRequest
{
    public required DateTime ScheduledTime { get; init; }
    public required string TaskData { get; init; }
}
```

### Timeout Pattern

```csharp
using DurableTask.Core;
using DurableTask.Core.Exceptions;

namespace Timers;

/// <summary>
/// Activity with timeout protection.
/// </summary>
public sealed class TimeoutOrchestration : TaskOrchestration<OperationResult, OperationRequest>
{
    public override async Task<OperationResult> RunTask(
        OrchestrationContext context, 
        OperationRequest input)
    {
        using var cts = new CancellationTokenSource();
        
        var operationTask = context.ScheduleTask<string>(
            typeof(LongRunningActivity),
            input);

        var timeoutTask = context.CreateTimer(
            context.CurrentUtcDateTime.Add(input.Timeout),
            cts.Token);

        var winner = await Task.WhenAny(operationTask, timeoutTask);

        if (winner == operationTask)
        {
            // Operation completed
            cts.Cancel(); // Cancel timeout timer
            var result = await operationTask;
            return OperationResult.Success(result);
        }
        else
        {
            // Timeout occurred
            return OperationResult.Timeout(input.Timeout);
        }
    }
}

public sealed record OperationResult
{
    public required bool Success { get; init; }
    public string? Result { get; init; }
    public string? ErrorMessage { get; init; }

    public static OperationResult Success(string result) => new()
    {
        Success = true,
        Result = result
    };

    public static OperationResult Timeout(TimeSpan timeout) => new()
    {
        Success = false,
        ErrorMessage = $"Operation timed out after {timeout}"
    };
}
```

### Recurring Timer Pattern

```csharp
using DurableTask.Core;

namespace Timers;

/// <summary>
/// Orchestration with recurring timer (polling pattern).
/// </summary>
public sealed class PollingOrchestration : TaskOrchestration<string, PollingConfig>
{
    public override async Task<string> RunTask(
        OrchestrationContext context, 
        PollingConfig input)
    {
        var attempts = 0;
        var maxAttempts = input.MaxAttempts;
        var pollingInterval = input.PollingInterval;

        while (attempts < maxAttempts)
        {
            attempts++;

            // Check status
            var status = await context.ScheduleTask<CheckResult>(
                typeof(CheckStatusActivity),
                input.ResourceId);

            if (status.IsReady)
            {
                // Resource is ready
                await context.ScheduleTask<bool>(
                    typeof(ProcessResourceActivity),
                    input.ResourceId);
                
                return $"Resource ready after {attempts} attempts";
            }

            if (attempts < maxAttempts)
            {
                // Wait before next poll
                await context.CreateTimer(
                    context.CurrentUtcDateTime.Add(pollingInterval),
                    CancellationToken.None);
            }
        }

        return $"Resource not ready after {maxAttempts} attempts";
    }
}

public sealed record PollingConfig
{
    public required string ResourceId { get; init; }
    public required TimeSpan PollingInterval { get; init; }
    public required int MaxAttempts { get; init; }
}

public sealed record CheckResult
{
    public required bool IsReady { get; init; }
}
```

### Exponential Backoff Timer

```csharp
using DurableTask.Core;

namespace Timers;

/// <summary>
/// Polling with exponential backoff.
/// </summary>
public sealed class ExponentialBackoffOrchestration : TaskOrchestration<string, BackoffConfig>
{
    public override async Task<string> RunTask(
        OrchestrationContext context, 
        BackoffConfig input)
    {
        var attempt = 0;
        var currentDelay = input.InitialDelay;

        while (attempt < input.MaxAttempts)
        {
            attempt++;

            var isComplete = await context.ScheduleTask<bool>(
                typeof(CheckCompletionActivity),
                input.TaskId);

            if (isComplete)
            {
                return $"Task completed after {attempt} checks";
            }

            if (attempt < input.MaxAttempts)
            {
                // Wait with exponential backoff
                await context.CreateTimer(
                    context.CurrentUtcDateTime.Add(currentDelay),
                    CancellationToken.None);

                // Calculate next delay: min(current * coefficient, max)
                currentDelay = TimeSpan.FromSeconds(
                    Math.Min(
                        currentDelay.TotalSeconds * input.BackoffCoefficient,
                        input.MaxDelay.TotalSeconds));
            }
        }

        return $"Task not completed after {input.MaxAttempts} attempts";
    }
}

public sealed record BackoffConfig
{
    public required string TaskId { get; init; }
    public required TimeSpan InitialDelay { get; init; }
    public required TimeSpan MaxDelay { get; init; }
    public required double BackoffCoefficient { get; init; }
    public required int MaxAttempts { get; init; }
}
```

---

## Versioning Strategies

### Side-by-Side Versioning

```csharp
using DurableTask.Core;

namespace Versioning;

/// <summary>
/// Version 1: Original orchestration
/// </summary>
[OrchestrationVersion("V1")]
public sealed class OrderProcessingOrchestrationV1 : TaskOrchestration<string, OrderRequest>
{
    public override async Task<string> RunTask(OrchestrationContext context, OrderRequest input)
    {
        // V1: Simple two-step process
        await context.ScheduleTask<bool>(typeof(ProcessPaymentActivity), input);
        await context.ScheduleTask<bool>(typeof(ShipOrderActivity), input);
        
        return "Order processed (V1)";
    }
}

/// <summary>
/// Version 2: Enhanced with inventory check
/// </summary>
[OrchestrationVersion("V2")]
public sealed class OrderProcessingOrchestrationV2 : TaskOrchestration<string, OrderRequest>
{
    public override async Task<string> RunTask(OrchestrationContext context, OrderRequest input)
    {
        // V2: Added inventory check
        var hasInventory = await context.ScheduleTask<bool>(
            typeof(CheckInventoryActivity), 
            input);

        if (!hasInventory)
        {
            return "Order failed: Out of stock";
        }

        await context.ScheduleTask<bool>(typeof(ProcessPaymentActivity), input);
        await context.ScheduleTask<bool>(typeof(ShipOrderActivity), input);
        
        return "Order processed (V2)";
    }
}

/// <summary>
/// Version 3: Full featured with notifications
/// </summary>
[OrchestrationVersion("V3")]
public sealed class OrderProcessingOrchestrationV3 : TaskOrchestration<OrderResult, OrderRequest>
{
    public override async Task<OrderResult> RunTask(OrchestrationContext context, OrderRequest input)
    {
        // V3: Complete workflow with error handling and notifications
        try
        {
            var hasInventory = await context.ScheduleTask<bool>(
                typeof(CheckInventoryActivity), 
                input);

            if (!hasInventory)
            {
                await context.ScheduleTask<bool>(
                    typeof(NotifyCustomerActivity),
                    new Notification(input.CustomerId, "Out of stock"));
                
                return OrderResult.Failed("Out of stock");
            }

            var paymentId = await context.ScheduleTask<string>(
                typeof(ProcessPaymentActivityV2), 
                input);

            await context.ScheduleTask<bool>(
                typeof(ShipOrderActivityV2), 
                new ShipmentRequest(input.OrderId, paymentId));

            await context.ScheduleTask<bool>(
                typeof(NotifyCustomerActivity),
                new Notification(input.CustomerId, "Order shipped"));

            return OrderResult.Success(input.OrderId, paymentId);
        }
        catch (Exception ex)
        {
            await context.ScheduleTask<bool>(
                typeof(NotifyCustomerActivity),
                new Notification(input.CustomerId, $"Order failed: {ex.Message}"));
            
            throw;
        }
    }
}

// Custom attribute for documentation
[AttributeUsage(AttributeTargets.Class)]
public sealed class OrchestrationVersionAttribute : Attribute
{
    public string Version { get; }
    
    public OrchestrationVersionAttribute(string version)
    {
        Version = version;
    }
}
```

### Version Detection Pattern

```csharp
using DurableTask.Core;

namespace Versioning;

/// <summary>
/// Single orchestration that detects and handles multiple versions.
/// </summary>
public sealed class VersionedOrchestration : TaskOrchestration<string, VersionedRequest>
{
    public override async Task<string> RunTask(
        OrchestrationContext context, 
        VersionedRequest input)
    {
        return input.Version switch
        {
            1 => await RunV1(context, input),
            2 => await RunV2(context, input),
            3 => await RunV3(context, input),
            _ => throw new NotSupportedException($"Version {input.Version} not supported")
        };
    }

    private async Task<string> RunV1(OrchestrationContext context, VersionedRequest input)
    {
        await context.ScheduleTask<bool>(typeof(ProcessPaymentActivity), input);
        return "V1 completed";
    }

    private async Task<string> RunV2(OrchestrationContext context, VersionedRequest input)
    {
        var hasInventory = await context.ScheduleTask<bool>(
            typeof(CheckInventoryActivity), 
            input);

        if (!hasInventory) return "V2: Out of stock";

        await context.ScheduleTask<bool>(typeof(ProcessPaymentActivity), input);
        return "V2 completed";
    }

    private async Task<string> RunV3(OrchestrationContext context, VersionedRequest input)
    {
        // Full V3 implementation
        var hasInventory = await context.ScheduleTask<bool>(
            typeof(CheckInventoryActivity), 
            input);

        if (!hasInventory)
        {
            await context.ScheduleTask<bool>(
                typeof(NotifyCustomerActivity),
                new Notification(input.CustomerId, "Out of stock"));
            return "V3: Out of stock";
        }

        await context.ScheduleTask<bool>(typeof(ProcessPaymentActivity), input);
        await context.ScheduleTask<bool>(
            typeof(NotifyCustomerActivity),
            new Notification(input.CustomerId, "Payment processed"));
        
        return "V3 completed";
    }
}

public sealed record VersionedRequest : OrderRequest
{
    public required int Version { get; init; }
}
```

### Feature Flag Versioning

```csharp
using DurableTask.Core;

namespace Versioning;

/// <summary>
/// Orchestration using feature flags for gradual rollout.
/// </summary>
public sealed class FeatureFlagOrchestration : TaskOrchestration<string, FeatureRequest>
{
    public override async Task<string> RunTask(
        OrchestrationContext context, 
        FeatureRequest input)
    {
        // Get feature flags (stored in durable context for determinism)
        var features = input.FeatureFlags;

        // Always run core logic
        await context.ScheduleTask<bool>(typeof(ProcessPaymentActivity), input);

        // New feature: Inventory check (behind feature flag)
        if (features.EnableInventoryCheck)
        {
            var hasInventory = await context.ScheduleTask<bool>(
                typeof(CheckInventoryActivity), 
                input);

            if (!hasInventory)
            {
                return "Order failed: Out of stock";
            }
        }

        // New feature: Customer notifications (behind feature flag)
        if (features.EnableNotifications)
        {
            await context.ScheduleTask<bool>(
                typeof(NotifyCustomerActivity),
                new Notification(input.CustomerId, "Order processing"));
        }

        // New feature: Loyalty points (behind feature flag)
        if (features.EnableLoyaltyPoints)
        {
            await context.ScheduleTask<bool>(
                typeof(AwardLoyaltyPointsActivity),
                input);
        }

        await context.ScheduleTask<bool>(typeof(ShipOrderActivity), input);

        return "Order processed";
    }
}

public sealed record FeatureRequest : OrderRequest
{
    public required FeatureFlags FeatureFlags { get; init; }
}

public sealed record FeatureFlags
{
    public required bool EnableInventoryCheck { get; init; }
    public required bool EnableNotifications { get; init; }
    public required bool EnableLoyaltyPoints { get; init; }
}

// Client code to determine feature flags
public sealed class FeatureFlagProvider
{
    public static FeatureFlags GetFeatureFlagsForCustomer(string customerId)
    {
        // Example: 10% rollout based on customer ID hash
        var hash = customerId.GetHashCode();
        var bucket = Math.Abs(hash % 100);

        return new FeatureFlags
        {
            EnableInventoryCheck = true, // Fully rolled out
            EnableNotifications = bucket < 50, // 50% rollout
            EnableLoyaltyPoints = bucket < 10  // 10% rollout
        };
    }
}
```

### Migration Strategy

```csharp
using DurableTask.Core;

namespace Versioning;

/// <summary>
/// Orchestration that migrates from old to new version mid-flight.
/// </summary>
public sealed class MigrationOrchestration : TaskOrchestration<string, MigrationRequest>
{
    public override async Task<string> RunTask(
        OrchestrationContext context, 
        MigrationRequest input)
    {
        // Check if this is a migrated instance
        if (input.MigratedFromV1)
        {
            // Skip V1 steps (already completed)
            // Continue with V2 steps only
            await RunV2OnlySteps(context, input);
            return "Migration from V1 to V2 completed";
        }

        // Normal V2 execution
        await RunFullV2(context, input);
        return "V2 completed";
    }

    private async Task RunV2OnlySteps(OrchestrationContext context, MigrationRequest input)
    {
        // Only new V2 features
        await context.ScheduleTask<bool>(
            typeof(NotifyCustomerActivity),
            new Notification(input.CustomerId, "Order update"));
    }

    private async Task RunFullV2(OrchestrationContext context, MigrationRequest input)
    {
        // Full V2 workflow
        await context.ScheduleTask<bool>(typeof(ProcessPaymentActivity), input);
        await context.ScheduleTask<bool>(
            typeof(NotifyCustomerActivity),
            new Notification(input.CustomerId, "Order processed"));
    }
}

public sealed record MigrationRequest : OrderRequest
{
    public bool MigratedFromV1 { get; init; }
}

// Migration utility
public sealed class OrchestrationMigrator
{
    private readonly TaskHubClient _client;

    public OrchestrationMigrator(TaskHubClient client)
    {
        _client = client;
    }

    public async Task MigrateInstance(string instanceId)
    {
        // Send event to trigger migration
        await _client.RaiseEventAsync(
            instanceId,
            "Migrate",
            new { TargetVersion = 2 });
    }
}
```

---

## Advanced Patterns Reference

### Pattern Selection Guide

| Scenario | Recommended Pattern | Key Features |
|----------|-------------------|--------------|
| **API fails occasionally** | Retry with backoff | RetryOptions, exponential backoff |
| **External service unreliable** | Circuit breaker | Failure threshold, cooldown period |
| **Need manual approval** | External event | WaitForExternalEvent, timeout |
| **Complex multi-step workflow** | Sub-orchestration | Hierarchical, independent retry |
| **Long-running operation** | Timeout pattern | CreateTimer, Task.WhenAny |
| **Need to upgrade workflow** | Side-by-side versioning | Multiple implementations |
| **Gradual feature rollout** | Feature flags | Conditional execution |

### Performance Considerations

1. **Activities vs Sub-Orchestrations**:
   - Activities: Fast, single history event
   - Sub-Orchestrations: Slower, separate instance but better for complex logic

2. **Retry Policies**:
   - Be careful with `maxNumberOfAttempts` - high values can delay failure detection
   - Use `Handle` predicate to avoid retrying non-transient failures

3. **External Events**:
   - Events are buffered in orchestration history
   - Too many events can bloat history size

4. **Timers**:
   - Timers are persisted in history
   - Cancel timers that are no longer needed

5. **Versioning**:
   - Side-by-side: Multiple implementations to maintain
   - Feature flags: Single implementation, more complex logic
   - Choose based on deployment capabilities

---

## Summary

This module covered:

✅ **Retry Policies**: Exponential backoff, custom handlers, circuit breakers  
✅ **Error Handling**: UseFailureDetails mode, IsCausedBy<T>, FailureDetails API  
✅ **External Events**: WaitForExternalEvent, timeouts, buffering, multiple events  
✅ **Sub-Orchestrations**: When to use, hierarchical workflows, instance ID management  
✅ **Timers**: Scheduled tasks, timeouts, polling, exponential backoff  
✅ **Versioning**: Side-by-side, version detection, feature flags, migration strategies  

**Next**: [04-OPTIMIZATION.md](./04-OPTIMIZATION.md) - Performance tuning and optimization techniques.
