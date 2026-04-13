# 05 - TESTING STRATEGIES

**Comprehensive testing patterns for orchestrations, activities, determinism validation, and integration tests.**

---

## Table of Contents

1. [Unit Testing Activities](#unit-testing-activities)
2. [Testing Orchestrations](#testing-orchestrations)
3. [Integration Testing](#integration-testing)
4. [Testing Retry Behavior](#testing-retry-behavior)
5. [Testing Timeouts and Timers](#testing-timeouts-and-timers)
6. [Testing External Events](#testing-external-events)
7. [Testing Sub-Orchestrations](#testing-sub-orchestrations)
8. [Determinism Validation](#determinism-validation)
9. [Test Helpers and Utilities](#test-helpers-and-utilities)
10. [Testing Best Practices](#testing-best-practices)

---

## Unit Testing Activities

### Simple Activity Tests

```csharp
using DurableTask.Core;
using Xunit;

namespace Testing.Activities;

/// <summary>
/// Activity to test.
/// </summary>
public sealed class CalculateTotalActivity : TaskActivity<Order, decimal>
{
    protected override decimal Execute(TaskContext context, Order input)
    {
        if (input.Items.Length == 0)
        {
            throw new ArgumentException("Order must have at least one item");
        }

        return input.Items.Sum(item => item.Price * item.Quantity);
    }
}

/// <summary>
/// Unit tests for CalculateTotalActivity.
/// </summary>
public sealed class CalculateTotalActivityTests
{
    [Fact]
    public void Execute_WithValidOrder_ReturnsCorrectTotal()
    {
        // Arrange
        var activity = new CalculateTotalActivity();
        var context = new TaskContext(new OrchestrationInstance 
        { 
            InstanceId = "test", 
            ExecutionId = "exec" 
        });
        
        var order = new Order
        {
            OrderId = "ORDER-001",
            Items = new[]
            {
                new OrderItem { ProductId = "P1", Price = 10.00m, Quantity = 2 },
                new OrderItem { ProductId = "P2", Price = 5.50m, Quantity = 3 }
            }
        };

        // Act
        var result = activity.Execute(context, order);

        // Assert
        Assert.Equal(36.50m, result); // (10 * 2) + (5.50 * 3) = 36.50
    }

    [Fact]
    public void Execute_WithEmptyOrder_ThrowsArgumentException()
    {
        // Arrange
        var activity = new CalculateTotalActivity();
        var context = new TaskContext(new OrchestrationInstance 
        { 
            InstanceId = "test", 
            ExecutionId = "exec" 
        });
        
        var order = new Order
        {
            OrderId = "ORDER-002",
            Items = Array.Empty<OrderItem>()
        };

        // Act & Assert
        var exception = Assert.Throws<ArgumentException>(() => 
            activity.Execute(context, order));
        
        Assert.Contains("at least one item", exception.Message);
    }

    [Theory]
    [InlineData(100.00, 1, 100.00)]
    [InlineData(25.50, 4, 102.00)]
    [InlineData(0.99, 100, 99.00)]
    public void Execute_WithVariousInputs_CalculatesCorrectly(
        decimal price, 
        int quantity, 
        decimal expectedTotal)
    {
        // Arrange
        var activity = new CalculateTotalActivity();
        var context = new TaskContext(new OrchestrationInstance 
        { 
            InstanceId = "test", 
            ExecutionId = "exec" 
        });
        
        var order = new Order
        {
            OrderId = "ORDER-003",
            Items = new[]
            {
                new OrderItem { ProductId = "P1", Price = price, Quantity = quantity }
            }
        };

        // Act
        var result = activity.Execute(context, order);

        // Assert
        Assert.Equal(expectedTotal, result);
    }
}

public sealed record Order
{
    public required string OrderId { get; init; }
    public required OrderItem[] Items { get; init; }
}

public sealed record OrderItem
{
    public required string ProductId { get; init; }
    public required decimal Price { get; init; }
    public required int Quantity { get; init; }
}
```

### Testing Activities with Dependencies

```csharp
using DurableTask.Core;
using Moq;
using Xunit;

namespace Testing.Activities;

/// <summary>
/// Activity with external dependencies.
/// </summary>
public sealed class SendEmailActivity : TaskActivity<EmailRequest, bool>
{
    private readonly IEmailService _emailService;

    public SendEmailActivity(IEmailService emailService)
    {
        _emailService = emailService;
    }

    protected override bool Execute(TaskContext context, EmailRequest input)
    {
        return _emailService.SendEmail(input.To, input.Subject, input.Body);
    }
}

public interface IEmailService
{
    bool SendEmail(string to, string subject, string body);
}

/// <summary>
/// Unit tests with mocked dependencies.
/// </summary>
public sealed class SendEmailActivityTests
{
    [Fact]
    public void Execute_WithValidRequest_CallsEmailService()
    {
        // Arrange
        var emailServiceMock = new Mock<IEmailService>();
        emailServiceMock
            .Setup(x => x.SendEmail(
                It.IsAny<string>(), 
                It.IsAny<string>(), 
                It.IsAny<string>()))
            .Returns(true);

        var activity = new SendEmailActivity(emailServiceMock.Object);
        var context = new TaskContext(new OrchestrationInstance 
        { 
            InstanceId = "test", 
            ExecutionId = "exec" 
        });
        
        var request = new EmailRequest
        {
            To = "user@example.com",
            Subject = "Test",
            Body = "Test body"
        };

        // Act
        var result = activity.Execute(context, request);

        // Assert
        Assert.True(result);
        emailServiceMock.Verify(
            x => x.SendEmail("user@example.com", "Test", "Test body"),
            Times.Once);
    }

    [Fact]
    public void Execute_WhenEmailServiceFails_ReturnsFalse()
    {
        // Arrange
        var emailServiceMock = new Mock<IEmailService>();
        emailServiceMock
            .Setup(x => x.SendEmail(
                It.IsAny<string>(), 
                It.IsAny<string>(), 
                It.IsAny<string>()))
            .Returns(false);

        var activity = new SendEmailActivity(emailServiceMock.Object);
        var context = new TaskContext(new OrchestrationInstance 
        { 
            InstanceId = "test", 
            ExecutionId = "exec" 
        });
        
        var request = new EmailRequest
        {
            To = "user@example.com",
            Subject = "Test",
            Body = "Test body"
        };

        // Act
        var result = activity.Execute(context, request);

        // Assert
        Assert.False(result);
    }
}

public sealed record EmailRequest
{
    public required string To { get; init; }
    public required string Subject { get; init; }
    public required string Body { get; init; }
}
```

---

## Testing Orchestrations

### Testing with TestOrchestrationHost

```csharp
using DurableTask.Core;
using DurableTask.Core.Testing;
using Xunit;

namespace Testing.Orchestrations;

/// <summary>
/// Simple orchestration to test.
/// </summary>
public sealed class OrderProcessingOrchestration : TaskOrchestration<OrderResult, OrderRequest>
{
    public override async Task<OrderResult> RunTask(
        OrchestrationContext context, 
        OrderRequest input)
    {
        // Validate order
        var isValid = await context.ScheduleTask<bool>(
            typeof(ValidateOrderActivity),
            input);

        if (!isValid)
        {
            return OrderResult.ValidationFailed();
        }

        // Process payment
        var paymentId = await context.ScheduleTask<string>(
            typeof(ProcessPaymentActivity),
            input);

        // Ship order
        await context.ScheduleTask<bool>(
            typeof(ShipOrderActivity),
            new ShipmentRequest(input.OrderId, paymentId));

        return OrderResult.Success(input.OrderId, paymentId);
    }
}

/// <summary>
/// Tests using TestOrchestrationHost.
/// </summary>
public sealed class OrderProcessingOrchestrationTests
{
    [Fact]
    public async Task RunTask_WithValidOrder_ProcessesSuccessfully()
    {
        // Arrange
        var host = new TestOrchestrationHost();
        
        // Register orchestration
        host.AddTaskOrchestrations(typeof(OrderProcessingOrchestration));
        
        // Register activity implementations with fixed results
        host.AddTaskActivitiesFromInterface<IOrderActivities>(
            new MockOrderActivities
            {
                ValidateOrderResult = true,
                ProcessPaymentResult = "PAY-12345",
                ShipOrderResult = true
            });

        var request = new OrderRequest
        {
            OrderId = "ORDER-001",
            CustomerId = "CUST-001",
            Items = new[] { "ITEM-001" }
        };

        // Act
        var result = await host.ExecuteOrchestration<OrderResult>(
            typeof(OrderProcessingOrchestration),
            request);

        // Assert
        Assert.NotNull(result);
        Assert.Equal(OrderStatus.Success, result.Status);
        Assert.Equal("ORDER-001", result.OrderId);
        Assert.Equal("PAY-12345", result.PaymentId);
    }

    [Fact]
    public async Task RunTask_WithInvalidOrder_ReturnsValidationFailed()
    {
        // Arrange
        var host = new TestOrchestrationHost();
        host.AddTaskOrchestrations(typeof(OrderProcessingOrchestration));
        host.AddTaskActivitiesFromInterface<IOrderActivities>(
            new MockOrderActivities
            {
                ValidateOrderResult = false // Validation fails
            });

        var request = new OrderRequest
        {
            OrderId = "ORDER-002",
            CustomerId = "CUST-001",
            Items = Array.Empty<string>()
        };

        // Act
        var result = await host.ExecuteOrchestration<OrderResult>(
            typeof(OrderProcessingOrchestration),
            request);

        // Assert
        Assert.NotNull(result);
        Assert.Equal(OrderStatus.ValidationFailed, result.Status);
    }
}

// Mock activities interface
public interface IOrderActivities
{
    bool ValidateOrder(OrderRequest request);
    string ProcessPayment(OrderRequest request);
    bool ShipOrder(ShipmentRequest request);
}

// Mock implementation for testing
public sealed class MockOrderActivities : IOrderActivities
{
    public bool ValidateOrderResult { get; set; }
    public string ProcessPaymentResult { get; set; } = "PAY-00000";
    public bool ShipOrderResult { get; set; }

    public bool ValidateOrder(OrderRequest request) => ValidateOrderResult;
    public string ProcessPayment(OrderRequest request) => ProcessPaymentResult;
    public bool ShipOrder(ShipmentRequest request) => ShipOrderResult;
}

public sealed record OrderRequest
{
    public required string OrderId { get; init; }
    public required string CustomerId { get; init; }
    public required string[] Items { get; init; }
}

public sealed record ShipmentRequest(string OrderId, string PaymentId);

public sealed record OrderResult
{
    public required OrderStatus Status { get; init; }
    public string? OrderId { get; init; }
    public string? PaymentId { get; init; }

    public static OrderResult Success(string orderId, string paymentId) => new()
    {
        Status = OrderStatus.Success,
        OrderId = orderId,
        PaymentId = paymentId
    };

    public static OrderResult ValidationFailed() => new()
    {
        Status = OrderStatus.ValidationFailed
    };
}

public enum OrderStatus
{
    Success,
    ValidationFailed,
    PaymentFailed,
    ShippingFailed
}
```

### Testing with Manual Mocking

```csharp
using DurableTask.Core;
using Moq;
using Xunit;

namespace Testing.Orchestrations;

/// <summary>
/// Test orchestration by mocking OrchestrationContext.
/// </summary>
public sealed class PaymentOrchestrationTests
{
    [Fact]
    public async Task RunTask_WithSuccessfulPayment_ReturnsTransactionId()
    {
        // Arrange
        var contextMock = new Mock<OrchestrationContext>();
        
        // Mock ScheduleTask calls
        contextMock
            .Setup(x => x.ScheduleTask<bool>(
                typeof(ValidatePaymentActivity),
                It.IsAny<PaymentInfo>()))
            .ReturnsAsync(true);

        contextMock
            .Setup(x => x.ScheduleTask<string>(
                typeof(AuthorizePaymentActivity),
                It.IsAny<PaymentInfo>()))
            .ReturnsAsync("AUTH-123");

        contextMock
            .Setup(x => x.ScheduleTask<string>(
                typeof(CapturePaymentActivity),
                It.IsAny<CaptureRequest>()))
            .ReturnsAsync("TXN-456");

        var orchestration = new PaymentOrchestration();
        var paymentInfo = new PaymentInfo
        {
            CardNumber = "****1234",
            Amount = 100.00m
        };

        // Act
        var result = await orchestration.RunTask(contextMock.Object, paymentInfo);

        // Assert
        Assert.True(result.Success);
        Assert.Equal("TXN-456", result.TransactionId);
        
        // Verify all activities were called
        contextMock.Verify(
            x => x.ScheduleTask<bool>(typeof(ValidatePaymentActivity), paymentInfo),
            Times.Once);
        contextMock.Verify(
            x => x.ScheduleTask<string>(typeof(AuthorizePaymentActivity), paymentInfo),
            Times.Once);
        contextMock.Verify(
            x => x.ScheduleTask<string>(
                typeof(CapturePaymentActivity), 
                It.Is<CaptureRequest>(r => r.AuthCode == "AUTH-123")),
            Times.Once);
    }

    [Fact]
    public async Task RunTask_WithInvalidPayment_ReturnsFailure()
    {
        // Arrange
        var contextMock = new Mock<OrchestrationContext>();
        
        contextMock
            .Setup(x => x.ScheduleTask<bool>(
                typeof(ValidatePaymentActivity),
                It.IsAny<PaymentInfo>()))
            .ReturnsAsync(false); // Validation fails

        var orchestration = new PaymentOrchestration();
        var paymentInfo = new PaymentInfo
        {
            CardNumber = "****0000",
            Amount = 100.00m
        };

        // Act
        var result = await orchestration.RunTask(contextMock.Object, paymentInfo);

        // Assert
        Assert.False(result.Success);
        Assert.Null(result.TransactionId);
        
        // Verify only validation was called
        contextMock.Verify(
            x => x.ScheduleTask<bool>(typeof(ValidatePaymentActivity), paymentInfo),
            Times.Once);
        contextMock.Verify(
            x => x.ScheduleTask<string>(typeof(AuthorizePaymentActivity), It.IsAny<PaymentInfo>()),
            Times.Never);
    }
}

public sealed class PaymentOrchestration : TaskOrchestration<PaymentResult, PaymentInfo>
{
    public override async Task<PaymentResult> RunTask(
        OrchestrationContext context, 
        PaymentInfo input)
    {
        var isValid = await context.ScheduleTask<bool>(
            typeof(ValidatePaymentActivity),
            input);

        if (!isValid)
        {
            return PaymentResult.Invalid();
        }

        var authCode = await context.ScheduleTask<string>(
            typeof(AuthorizePaymentActivity),
            input);

        var transactionId = await context.ScheduleTask<string>(
            typeof(CapturePaymentActivity),
            new CaptureRequest(authCode, input.Amount));

        return PaymentResult.Successful(transactionId);
    }
}

public sealed record PaymentInfo
{
    public required string CardNumber { get; init; }
    public required decimal Amount { get; init; }
}

public sealed record CaptureRequest(string AuthCode, decimal Amount);

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

---

## Integration Testing

### Full Integration Test with SQL Server

```csharp
using DurableTask.Core;
using DurableTask.SqlServer;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Xunit;

namespace Testing.Integration;

/// <summary>
/// Integration tests using real SQL Server database.
/// </summary>
public sealed class OrderProcessingIntegrationTests : IAsyncLifetime
{
    private const string ConnectionString = 
        "Server=localhost;Database=DurableTaskTest;Integrated Security=true;TrustServerCertificate=true";
    
    private TaskHubWorker? _worker;
    private TaskHubClient? _client;
    private SqlOrchestrationService? _service;

    public async Task InitializeAsync()
    {
        // Setup database
        await CreateTestDatabase();

        // Create service
        var settings = new SqlOrchestrationServiceSettings
        {
            TaskOrchestrationLockTimeout = TimeSpan.FromMinutes(5),
            TaskActivityLockTimeout = TimeSpan.FromMinutes(5)
        };

        _service = new SqlOrchestrationService(settings);
        await _service.CreateIfNotExistsAsync();

        // Create worker
        var loggerFactory = LoggerFactory.Create(builder => builder.AddConsole());
        _worker = new TaskHubWorker(_service, loggerFactory)
        {
            ErrorPropagationMode = ErrorPropagationMode.UseFailureDetails
        };

        // Register orchestrations and activities
        _worker.AddTaskOrchestrations(typeof(OrderProcessingOrchestration));
        _worker.AddTaskActivities(
            typeof(ValidateOrderActivity),
            typeof(ProcessPaymentActivity),
            typeof(ShipOrderActivity));

        // Start worker
        await _worker.StartAsync();

        // Create client
        _client = new TaskHubClient(_service);
    }

    public async Task DisposeAsync()
    {
        if (_worker != null)
        {
            await _worker.StopAsync();
        }

        if (_service != null)
        {
            await _service.DeleteAsync();
        }

        await DropTestDatabase();
    }

    [Fact]
    public async Task OrderProcessing_EndToEnd_CompletesSuccessfully()
    {
        // Arrange
        var request = new OrderRequest
        {
            OrderId = "ORDER-INT-001",
            CustomerId = "CUST-001",
            Items = new[] { "ITEM-001", "ITEM-002" }
        };

        // Act
        var instance = await _client!.CreateOrchestrationInstanceAsync(
            typeof(OrderProcessingOrchestration),
            request);

        // Wait for completion (with timeout)
        var timeout = TimeSpan.FromSeconds(30);
        var result = await WaitForCompletion<OrderResult>(instance.InstanceId, timeout);

        // Assert
        Assert.NotNull(result);
        Assert.Equal(OrderStatus.Success, result.Status);
        Assert.Equal("ORDER-INT-001", result.OrderId);
        Assert.NotNull(result.PaymentId);
    }

    [Fact]
    public async Task OrderProcessing_WithInvalidOrder_FailsValidation()
    {
        // Arrange
        var request = new OrderRequest
        {
            OrderId = "ORDER-INT-002",
            CustomerId = "CUST-001",
            Items = Array.Empty<string>() // Invalid: no items
        };

        // Act
        var instance = await _client!.CreateOrchestrationInstanceAsync(
            typeof(OrderProcessingOrchestration),
            request);

        var timeout = TimeSpan.FromSeconds(30);
        var result = await WaitForCompletion<OrderResult>(instance.InstanceId, timeout);

        // Assert
        Assert.NotNull(result);
        Assert.Equal(OrderStatus.ValidationFailed, result.Status);
    }

    private async Task<T?> WaitForCompletion<T>(string instanceId, TimeSpan timeout)
    {
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();

        while (stopwatch.Elapsed < timeout)
        {
            var state = await _client!.GetOrchestrationStateAsync(instanceId);

            if (state?.OrchestrationStatus == OrchestrationStatus.Completed)
            {
                return Newtonsoft.Json.JsonConvert.DeserializeObject<T>(state.Output);
            }

            if (state?.OrchestrationStatus == OrchestrationStatus.Failed ||
                state?.OrchestrationStatus == OrchestrationStatus.Terminated)
            {
                throw new Exception($"Orchestration failed or terminated: {state.Output}");
            }

            await Task.Delay(500);
        }

        throw new TimeoutException($"Orchestration did not complete within {timeout}");
    }

    private static async Task CreateTestDatabase()
    {
        var masterConnectionString = 
            "Server=localhost;Database=master;Integrated Security=true;TrustServerCertificate=true";

        await using var connection = new SqlConnection(masterConnectionString);
        await connection.OpenAsync();

        var command = new SqlCommand(@"
            IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'DurableTaskTest')
            BEGIN
                CREATE DATABASE DurableTaskTest;
            END
        ", connection);

        await command.ExecuteNonQueryAsync();
    }

    private static async Task DropTestDatabase()
    {
        var masterConnectionString = 
            "Server=localhost;Database=master;Integrated Security=true;TrustServerCertificate=true";

        await using var connection = new SqlConnection(masterConnectionString);
        await connection.OpenAsync();

        var command = new SqlCommand(@"
            IF EXISTS (SELECT * FROM sys.databases WHERE name = 'DurableTaskTest')
            BEGIN
                ALTER DATABASE DurableTaskTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                DROP DATABASE DurableTaskTest;
            END
        ", connection);

        await command.ExecuteNonQueryAsync();
    }
}

// Activity implementations for integration tests
public sealed class ValidateOrderActivity : TaskActivity<OrderRequest, bool>
{
    protected override bool Execute(TaskContext context, OrderRequest input)
    {
        return input.Items.Length > 0;
    }
}

public sealed class ProcessPaymentActivity : TaskActivity<OrderRequest, string>
{
    protected override string Execute(TaskContext context, OrderRequest input)
    {
        return $"PAY-{Guid.NewGuid():N}";
    }
}

public sealed class ShipOrderActivity : TaskActivity<ShipmentRequest, bool>
{
    protected override bool Execute(TaskContext context, ShipmentRequest input)
    {
        return true;
    }
}
```

---

## Testing Retry Behavior

```csharp
using DurableTask.Core;
using Moq;
using Xunit;

namespace Testing.Retry;

/// <summary>
/// Test orchestration retry behavior.
/// </summary>
public sealed class RetryBehaviorTests
{
    [Fact]
    public async Task Orchestration_WithTransientFailure_RetriesSuccessfully()
    {
        // Arrange
        var contextMock = new Mock<OrchestrationContext>();
        var callCount = 0;

        contextMock
            .Setup(x => x.ScheduleWithRetry<string>(
                typeof(UnreliableActivity),
                It.IsAny<RetryOptions>(),
                It.IsAny<string>()))
            .ReturnsAsync(() =>
            {
                callCount++;
                if (callCount < 3)
                {
                    throw new HttpRequestException("Transient failure");
                }
                return "Success";
            });

        var orchestration = new RetryOrchestration();

        // Act
        var result = await orchestration.RunTask(contextMock.Object, "test-input");

        // Assert
        Assert.Equal("Success", result);
        Assert.Equal(3, callCount); // Failed twice, succeeded on third attempt
    }
}

public sealed class RetryOrchestration : TaskOrchestration<string, string>
{
    public override async Task<string> RunTask(OrchestrationContext context, string input)
    {
        var retryPolicy = new RetryOptions(
            firstRetryInterval: TimeSpan.FromSeconds(1),
            maxNumberOfAttempts: 5)
        {
            BackoffCoefficient = 2.0
        };

        return await context.ScheduleWithRetry<string>(
            typeof(UnreliableActivity),
            retryPolicy,
            input);
    }
}

public sealed class UnreliableActivity : TaskActivity<string, string>
{
    protected override string Execute(TaskContext context, string input)
    {
        throw new NotImplementedException("Mock implementation");
    }
}
```

---

## Testing Timeouts and Timers

```csharp
using DurableTask.Core;
using Moq;
using Xunit;

namespace Testing.Timers;

/// <summary>
/// Test timeout behavior.
/// </summary>
public sealed class TimeoutTests
{
    [Fact]
    public async Task Orchestration_WhenActivityTimesOut_ReturnsTimeoutResult()
    {
        // Arrange
        var contextMock = new Mock<OrchestrationContext>();
        var currentTime = DateTime.UtcNow;

        contextMock
            .Setup(x => x.CurrentUtcDateTime)
            .Returns(currentTime);

        var activityTask = new TaskCompletionSource<string>();
        contextMock
            .Setup(x => x.ScheduleTask<string>(
                typeof(SlowActivity),
                It.IsAny<string>()))
            .Returns(activityTask.Task);

        var timerTask = Task.Delay(100); // Simulate timer
        contextMock
            .Setup(x => x.CreateTimer(
                It.IsAny<DateTime>(),
                It.IsAny<CancellationToken>()))
            .Returns(timerTask);

        var orchestration = new TimeoutOrchestration();

        // Act
        var resultTask = orchestration.RunTask(contextMock.Object, "test-input");
        await timerTask; // Timer completes first
        var result = await resultTask;

        // Assert
        Assert.False(result.Success);
        Assert.Contains("timeout", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Orchestration_WhenActivityCompletesBeforeTimeout_ReturnsSuccess()
    {
        // Arrange
        var contextMock = new Mock<OrchestrationContext>();
        var currentTime = DateTime.UtcNow;

        contextMock
            .Setup(x => x.CurrentUtcDateTime)
            .Returns(currentTime);

        var activityTask = Task.FromResult("Activity result");
        contextMock
            .Setup(x => x.ScheduleTask<string>(
                typeof(SlowActivity),
                It.IsAny<string>()))
            .Returns(activityTask);

        var timerTask = new TaskCompletionSource<object>().Task; // Never completes
        contextMock
            .Setup(x => x.CreateTimer(
                It.IsAny<DateTime>(),
                It.IsAny<CancellationToken>()))
            .Returns(timerTask);

        var orchestration = new TimeoutOrchestration();

        // Act
        var result = await orchestration.RunTask(contextMock.Object, "test-input");

        // Assert
        Assert.True(result.Success);
        Assert.Equal("Activity result", result.Message);
    }
}

public sealed class TimeoutOrchestration : TaskOrchestration<TimeoutResult, string>
{
    public override async Task<TimeoutResult> RunTask(
        OrchestrationContext context, 
        string input)
    {
        using var cts = new CancellationTokenSource();

        var activityTask = context.ScheduleTask<string>(
            typeof(SlowActivity),
            input);

        var timeoutTask = context.CreateTimer(
            context.CurrentUtcDateTime.AddSeconds(10),
            cts.Token);

        var winner = await Task.WhenAny(activityTask, timeoutTask);

        if (winner == activityTask)
        {
            cts.Cancel();
            var result = await activityTask;
            return TimeoutResult.Success(result);
        }
        else
        {
            return TimeoutResult.Timeout();
        }
    }
}

public sealed record TimeoutResult
{
    public required bool Success { get; init; }
    public required string Message { get; init; }

    public static TimeoutResult Success(string message) => new()
    {
        Success = true,
        Message = message
    };

    public static TimeoutResult Timeout() => new()
    {
        Success = false,
        Message = "Operation timed out"
    };
}

public sealed class SlowActivity : TaskActivity<string, string>
{
    protected override string Execute(TaskContext context, string input)
    {
        Thread.Sleep(20000); // 20 seconds
        return "Completed";
    }
}
```

---

## Testing External Events

```csharp
using DurableTask.Core;
using Moq;
using Xunit;

namespace Testing.Events;

/// <summary>
/// Test external event handling.
/// </summary>
public sealed class ExternalEventTests
{
    [Fact]
    public async Task Orchestration_WhenEventReceived_ProcessesEvent()
    {
        // Arrange
        var contextMock = new Mock<OrchestrationContext>();
        
        var approvalEvent = Task.FromResult(new ApprovalDecision
        {
            Approved = true,
            ApprovedBy = "manager@company.com",
            Comments = "Looks good"
        });

        contextMock
            .Setup(x => x.WaitForExternalEvent<ApprovalDecision>("ApprovalDecision"))
            .Returns(approvalEvent);

        var timeoutTask = new TaskCompletionSource<object>().Task; // Never times out
        contextMock
            .Setup(x => x.CreateTimer(It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Returns(timeoutTask);

        contextMock
            .Setup(x => x.ScheduleTask<bool>(
                typeof(ProcessApprovedRequestActivity),
                It.IsAny<ApprovalRequest>()))
            .ReturnsAsync(true);

        var orchestration = new ApprovalOrchestration();
        var request = new ApprovalRequest { RequestId = "REQ-001", Amount = 1000m };

        // Act
        var result = await orchestration.RunTask(contextMock.Object, request);

        // Assert
        Assert.Equal(ApprovalStatus.Approved, result.Status);
        Assert.Equal("manager@company.com", result.ApprovedBy);
    }

    [Fact]
    public async Task Orchestration_WhenTimeout_ReturnsTimeoutStatus()
    {
        // Arrange
        var contextMock = new Mock<OrchestrationContext>();
        
        var approvalEvent = new TaskCompletionSource<ApprovalDecision>().Task; // Never receives event
        contextMock
            .Setup(x => x.WaitForExternalEvent<ApprovalDecision>("ApprovalDecision"))
            .Returns(approvalEvent);

        var timeoutTask = Task.CompletedTask; // Timeout occurs immediately
        contextMock
            .Setup(x => x.CreateTimer(It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Returns(timeoutTask);

        contextMock
            .Setup(x => x.ScheduleTask<bool>(
                typeof(NotifyTimeoutActivity),
                It.IsAny<ApprovalRequest>()))
            .ReturnsAsync(true);

        var orchestration = new ApprovalOrchestration();
        var request = new ApprovalRequest { RequestId = "REQ-002", Amount = 1000m };

        // Act
        var result = await orchestration.RunTask(contextMock.Object, request);

        // Assert
        Assert.Equal(ApprovalStatus.Timeout, result.Status);
    }
}

public sealed record ApprovalRequest
{
    public required string RequestId { get; init; }
    public required decimal Amount { get; init; }
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
}

public enum ApprovalStatus { Approved, Rejected, Timeout }
```

---

## Testing Sub-Orchestrations

```csharp
using DurableTask.Core;
using Moq;
using Xunit;

namespace Testing.SubOrchestrations;

/// <summary>
/// Test sub-orchestration behavior.
/// </summary>
public sealed class SubOrchestrationTests
{
    [Fact]
    public async Task ParentOrchestration_WithSuccessfulSubOrch_CompletesSuccessfully()
    {
        // Arrange
        var contextMock = new Mock<OrchestrationContext>();
        
        contextMock
            .Setup(x => x.CreateSubOrchestrationInstance<PaymentResult>(
                typeof(PaymentOrchestration),
                It.IsAny<PaymentInfo>()))
            .ReturnsAsync(PaymentResult.Successful("TXN-123"));

        contextMock
            .Setup(x => x.CreateSubOrchestrationInstance<ShipmentResult>(
                typeof(ShipmentOrchestration),
                It.IsAny<ShipmentRequest>()))
            .ReturnsAsync(ShipmentResult.Success("TRACK-456"));

        var orchestration = new OrderOrchestration();
        var request = new OrderRequest
        {
            OrderId = "ORDER-001",
            CustomerId = "CUST-001",
            Items = new[] { "ITEM-001" }
        };

        // Act
        var result = await orchestration.RunTask(contextMock.Object, request);

        // Assert
        Assert.Equal("ORDER-001", result.OrderId);
        Assert.Equal("TXN-123", result.PaymentId);
        Assert.Equal("TRACK-456", result.TrackingNumber);
    }

    [Fact]
    public async Task ParentOrchestration_WhenPaymentFails_DoesNotShip()
    {
        // Arrange
        var contextMock = new Mock<OrchestrationContext>();
        
        contextMock
            .Setup(x => x.CreateSubOrchestrationInstance<PaymentResult>(
                typeof(PaymentOrchestration),
                It.IsAny<PaymentInfo>()))
            .ReturnsAsync(PaymentResult.Invalid()); // Payment fails

        var orchestration = new OrderOrchestration();
        var request = new OrderRequest
        {
            OrderId = "ORDER-002",
            CustomerId = "CUST-001",
            Items = new[] { "ITEM-001" }
        };

        // Act
        var result = await orchestration.RunTask(contextMock.Object, request);

        // Assert
        Assert.Null(result.PaymentId);
        Assert.Null(result.TrackingNumber);
        
        // Verify shipment sub-orchestration was never called
        contextMock.Verify(
            x => x.CreateSubOrchestrationInstance<ShipmentResult>(
                typeof(ShipmentOrchestration),
                It.IsAny<ShipmentRequest>()),
            Times.Never);
    }
}

public sealed class OrderOrchestration : TaskOrchestration<OrderSummary, OrderRequest>
{
    public override async Task<OrderSummary> RunTask(
        OrchestrationContext context, 
        OrderRequest input)
    {
        var paymentResult = await context.CreateSubOrchestrationInstance<PaymentResult>(
            typeof(PaymentOrchestration),
            new PaymentInfo { CardNumber = "****1234", Amount = 100m });

        if (!paymentResult.Success)
        {
            return new OrderSummary { OrderId = input.OrderId };
        }

        var shipmentResult = await context.CreateSubOrchestrationInstance<ShipmentResult>(
            typeof(ShipmentOrchestration),
            new ShipmentRequest(input.OrderId, paymentResult.TransactionId!));

        return new OrderSummary
        {
            OrderId = input.OrderId,
            PaymentId = paymentResult.TransactionId,
            TrackingNumber = shipmentResult.TrackingNumber
        };
    }
}

public sealed record OrderSummary
{
    public required string OrderId { get; init; }
    public string? PaymentId { get; init; }
    public string? TrackingNumber { get; init; }
}

public sealed record ShipmentResult
{
    public required bool Success { get; init; }
    public string? TrackingNumber { get; init; }

    public static ShipmentResult Success(string trackingNumber) => new()
    {
        Success = true,
        TrackingNumber = trackingNumber
    };
}
```

---

## Determinism Validation

```csharp
using DurableTask.Core;
using Xunit;

namespace Testing.Determinism;

/// <summary>
/// Test that orchestrations are deterministic.
/// </summary>
public sealed class DeterminismTests
{
    [Fact]
    public async Task Orchestration_ExecutedTwiceWithSameInput_ProducesSameResults()
    {
        // Arrange
        var host1 = new TestOrchestrationHost();
        host1.AddTaskOrchestrations(typeof(DeterministicOrchestration));
        host1.AddTaskActivities(typeof(CalculateActivity));

        var host2 = new TestOrchestrationHost();
        host2.AddTaskOrchestrations(typeof(DeterministicOrchestration));
        host2.AddTaskActivities(typeof(CalculateActivity));

        var input = new CalculationInput { Value1 = 10, Value2 = 20 };

        // Act
        var result1 = await host1.ExecuteOrchestration<int>(
            typeof(DeterministicOrchestration),
            input);

        var result2 = await host2.ExecuteOrchestration<int>(
            typeof(DeterministicOrchestration),
            input);

        // Assert
        Assert.Equal(result1, result2);
    }

    [Fact]
    public void NonDeterministicCode_ShouldBeDetected()
    {
        // This test documents what NOT to do

        // ❌ WRONG: Using DateTime.UtcNow directly
        Assert.Throws<InvalidOperationException>(() =>
        {
            var now = DateTime.UtcNow; // Non-deterministic!
        });

        // ❌ WRONG: Using Guid.NewGuid directly
        Assert.Throws<InvalidOperationException>(() =>
        {
            var id = Guid.NewGuid(); // Non-deterministic!
        });

        // ❌ WRONG: Using Random
        Assert.Throws<InvalidOperationException>(() =>
        {
            var random = new Random();
            var value = random.Next(); // Non-deterministic!
        });
    }

    [Fact]
    public async Task DeterministicTimeUsage_UsesContextCurrentUtcDateTime()
    {
        // Arrange
        var contextMock = new Mock<OrchestrationContext>();
        var fixedTime = new DateTime(2026, 1, 30, 12, 0, 0, DateTimeKind.Utc);
        
        contextMock
            .Setup(x => x.CurrentUtcDateTime)
            .Returns(fixedTime);

        contextMock
            .Setup(x => x.CreateTimer(It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((DateTime fireAt, CancellationToken ct) => fireAt);

        var orchestration = new TimeBasedOrchestration();

        // Act
        var result = await orchestration.RunTask(contextMock.Object, null!);

        // Assert - result should be deterministic based on fixed time
        Assert.Contains("2026-01-30", result);
    }
}

public sealed class DeterministicOrchestration : TaskOrchestration<int, CalculationInput>
{
    public override async Task<int> RunTask(
        OrchestrationContext context, 
        CalculationInput input)
    {
        // ✅ CORRECT: All operations are deterministic
        var step1 = await context.ScheduleTask<int>(
            typeof(CalculateActivity),
            input.Value1);

        var step2 = await context.ScheduleTask<int>(
            typeof(CalculateActivity),
            input.Value2);

        return step1 + step2;
    }
}

public sealed class TimeBasedOrchestration : TaskOrchestration<string, object>
{
    public override async Task<string> RunTask(OrchestrationContext context, object input)
    {
        // ✅ CORRECT: Use context.CurrentUtcDateTime instead of DateTime.UtcNow
        var now = context.CurrentUtcDateTime;

        await context.CreateTimer(
            now.AddHours(1),
            CancellationToken.None);

        return $"Completed at {now:yyyy-MM-dd HH:mm:ss}";
    }
}

public sealed record CalculationInput
{
    public required int Value1 { get; init; }
    public required int Value2 { get; init; }
}

public sealed class CalculateActivity : TaskActivity<int, int>
{
    protected override int Execute(TaskContext context, int input)
    {
        return input * 2;
    }
}
```

---

## Test Helpers and Utilities

```csharp
using DurableTask.Core;
using Microsoft.Extensions.Logging;

namespace Testing.Helpers;

/// <summary>
/// Base class for orchestration tests with common setup.
/// </summary>
public abstract class OrchestrationTestBase
{
    protected ILoggerFactory LoggerFactory { get; }

    protected OrchestrationTestBase()
    {
        LoggerFactory = Microsoft.Extensions.Logging.LoggerFactory.Create(
            builder => builder.AddConsole().SetMinimumLevel(LogLevel.Debug));
    }

    protected TaskHubWorker CreateTestWorker(IOrchestrationService service)
    {
        var worker = new TaskHubWorker(service, LoggerFactory)
        {
            ErrorPropagationMode = ErrorPropagationMode.UseFailureDetails,
            MaxConcurrentTaskOrchestrations = 10,
            MaxConcurrentTaskActivities = 20
        };

        return worker;
    }

    protected async Task<T?> WaitForOrchestrationResult<T>(
        TaskHubClient client,
        string instanceId,
        TimeSpan timeout)
    {
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();

        while (stopwatch.Elapsed < timeout)
        {
            var state = await client.GetOrchestrationStateAsync(instanceId);

            if (state?.OrchestrationStatus == OrchestrationStatus.Completed)
            {
                return Newtonsoft.Json.JsonConvert.DeserializeObject<T>(state.Output);
            }

            if (state?.OrchestrationStatus == OrchestrationStatus.Failed)
            {
                throw new Exception($"Orchestration failed: {state.Output}");
            }

            await Task.Delay(500);
        }

        throw new TimeoutException($"Orchestration did not complete within {timeout}");
    }
}

/// <summary>
/// Helper to create mock activities.
/// </summary>
public static class MockActivityFactory
{
    public static TActivity CreateMockActivity<TActivity, TInput, TOutput>(
        Func<TInput, TOutput> implementation)
        where TActivity : TaskActivity<TInput, TOutput>, new()
    {
        var activity = new TActivity();
        // In real implementation, you'd use reflection or code generation
        // to replace Execute method
        return activity;
    }
}
```

---

## Testing Best Practices

### ✅ DO

1. **Test Activities Independently**
   - Unit test activities with mocks
   - Test edge cases and error conditions
   - Verify all code paths

2. **Test Orchestration Logic**
   - Mock OrchestrationContext
   - Test decision logic and branching
   - Verify correct activity sequencing

3. **Integration Tests for Happy Path**
   - Use real database for integration tests
   - Test complete end-to-end flows
   - Verify state persistence

4. **Test Error Handling**
   - Test retry behavior
   - Test compensation logic
   - Test failure propagation

5. **Validate Determinism**
   - Run orchestrations multiple times
   - Verify identical results with same input
   - Check for non-deterministic code

### ❌ DON'T

1. **Don't Test Framework Code**
   - Don't test DTFx internal behavior
   - Focus on your business logic

2. **Don't Over-Mock**
   - Use real implementations when simple
   - Mock only external dependencies

3. **Don't Skip Integration Tests**
   - Unit tests alone aren't enough
   - Always test with real database

4. **Don't Ignore Timing Issues**
   - Test timeout scenarios
   - Test race conditions
   - Use proper assertions for async code

5. **Don't Forget Cleanup**
   - Clean up test databases
   - Dispose resources properly
   - Use IAsyncLifetime for setup/teardown

---

## Summary

This module covered:

✅ **Activity Testing**: Unit tests with mocks and dependencies  
✅ **Orchestration Testing**: TestOrchestrationHost and manual mocking  
✅ **Integration Testing**: Full end-to-end tests with SQL Server  
✅ **Retry Testing**: Verify retry policies work correctly  
✅ **Timer Testing**: Test timeout and scheduling behavior  
✅ **Event Testing**: Test external event handling  
✅ **Sub-Orchestration Testing**: Test hierarchical workflows  
✅ **Determinism Validation**: Ensure reproducible results  
✅ **Test Helpers**: Reusable test utilities and base classes  
✅ **Best Practices**: Guidelines for effective testing  

**Next**: [06-SQL-SERVER.md](./06-SQL-SERVER.md) - Deep dive into SQL Server provider, schema, performance tuning, and deployment.
