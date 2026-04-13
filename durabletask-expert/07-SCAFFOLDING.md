# 07 - PROJECT SCAFFOLDING & TEMPLATES

**Complete project templates, folder structure, dependency injection setup, and code generation for .NET 9+ DurableTask applications.**

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Core Project Template](#core-project-template)
3. [Worker Service Template](#worker-service-template)
4. [API Client Template](#api-client-template)
5. [Dependency Injection Setup](#dependency-injection-setup)
6. [Configuration Patterns](#configuration-patterns)
7. [Logging Setup](#logging-setup)
8. [Code Generators](#code-generators)
9. [Development Environment](#development-environment)
10. [Complete Example Project](#complete-example-project)

---

## Project Structure

### Recommended Folder Structure

```
MyDurableTaskApp/
├── src/
│   ├── MyApp.Orchestrations/          # Orchestration definitions
│   │   ├── Orchestrations/
│   │   │   ├── OrderProcessingOrchestration.cs
│   │   │   ├── PaymentOrchestration.cs
│   │   │   └── ShipmentOrchestration.cs
│   │   ├── Activities/
│   │   │   ├── ValidateOrderActivity.cs
│   │   │   ├── ProcessPaymentActivity.cs
│   │   │   └── ShipOrderActivity.cs
│   │   ├── Models/
│   │   │   ├── OrderRequest.cs
│   │   │   ├── OrderResult.cs
│   │   │   └── PaymentInfo.cs
│   │   └── MyApp.Orchestrations.csproj
│   │
│   ├── MyApp.Worker/                   # Worker host
│   │   ├── Program.cs
│   │   ├── DurableTaskWorkerService.cs
│   │   ├── appsettings.json
│   │   ├── appsettings.Development.json
│   │   ├── appsettings.Production.json
│   │   └── MyApp.Worker.csproj
│   │
│   ├── MyApp.Client/                   # Client API
│   │   ├── IDurableTaskClient.cs
│   │   ├── DurableTaskClient.cs
│   │   ├── Models/
│   │   │   └── OrchestrationStatus.cs
│   │   └── MyApp.Client.csproj
│   │
│   ├── MyApp.Infrastructure/           # Shared infrastructure
│   │   ├── SqlServer/
│   │   │   ├── ConnectionStringFactory.cs
│   │   │   ├── SqlOrchestrationServiceFactory.cs
│   │   │   └── DatabaseMaintenance.cs
│   │   ├── Monitoring/
│   │   │   ├── MetricsCollector.cs
│   │   │   └── HealthChecks.cs
│   │   └── MyApp.Infrastructure.csproj
│   │
│   └── MyApp.Api/                      # REST API (optional)
│       ├── Controllers/
│       │   └── OrchestrationController.cs
│       ├── Program.cs
│       ├── appsettings.json
│       └── MyApp.Api.csproj
│
├── tests/
│   ├── MyApp.Orchestrations.Tests/
│   │   ├── OrchestrationTests/
│   │   ├── ActivityTests/
│   │   └── MyApp.Orchestrations.Tests.csproj
│   │
│   └── MyApp.Integration.Tests/
│       ├── EndToEndTests/
│       └── MyApp.Integration.Tests.csproj
│
├── scripts/
│   ├── sql/
│   │   ├── 01-create-schema.sql
│   │   ├── 02-create-indexes.sql
│   │   └── 03-maintenance.sql
│   └── deploy/
│       ├── deploy-windows-service.ps1
│       └── deploy-docker.sh
│
├── MyDurableTaskApp.sln
├── Directory.Build.props
├── Directory.Packages.props              # Central Package Management
├── .editorconfig
├── .gitignore
└── README.md
```

---

## Core Project Template

### MyApp.Orchestrations.csproj

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <LangVersion>latest</LangVersion>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.DurableTask.Core" />
    <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" />
  </ItemGroup>

</Project>
```

### Directory.Packages.props (Central Package Management)

```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
    <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
  </PropertyGroup>

  <ItemGroup>
    <!-- DurableTask -->
    <PackageVersion Include="Microsoft.DurableTask.Core" Version="2.16.3" />
    <PackageVersion Include="Microsoft.DurableTask.SqlServer" Version="2.16.3" />
    
    <!-- Microsoft Extensions -->
    <PackageVersion Include="Microsoft.Extensions.Hosting" Version="9.0.0" />
    <PackageVersion Include="Microsoft.Extensions.Hosting.WindowsServices" Version="9.0.0" />
    <PackageVersion Include="Microsoft.Extensions.Configuration" Version="9.0.0" />
    <PackageVersion Include="Microsoft.Extensions.Configuration.Json" Version="9.0.0" />
    <PackageVersion Include="Microsoft.Extensions.Configuration.EnvironmentVariables" Version="9.0.0" />
    <PackageVersion Include="Microsoft.Extensions.Logging" Version="9.0.0" />
    <PackageVersion Include="Microsoft.Extensions.Logging.Console" Version="9.0.0" />
    <PackageVersion Include="Microsoft.Extensions.Logging.Debug" Version="9.0.0" />
    
    <!-- SQL Server -->
    <PackageVersion Include="Microsoft.Data.SqlClient" Version="5.2.0" />
    
    <!-- Monitoring -->
    <PackageVersion Include="System.Diagnostics.DiagnosticSource" Version="9.0.0" />
    <PackageVersion Include="OpenTelemetry" Version="1.7.0" />
    <PackageVersion Include="OpenTelemetry.Extensions.Hosting" Version="1.7.0" />
    <PackageVersion Include="OpenTelemetry.Instrumentation.SqlClient" Version="1.7.0-beta.1" />
    
    <!-- Testing -->
    <PackageVersion Include="xunit" Version="2.6.6" />
    <PackageVersion Include="xunit.runner.visualstudio" Version="2.5.6" />
    <PackageVersion Include="Moq" Version="4.20.70" />
    <PackageVersion Include="FluentAssertions" Version="6.12.0" />
    <PackageVersion Include="Microsoft.NET.Test.Sdk" Version="17.9.0" />
  </ItemGroup>
</Project>
```

### Directory.Build.props

```xml
<Project>
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <LangVersion>latest</LangVersion>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
    <EnableNETAnalyzers>true</EnableNETAnalyzers>
    <AnalysisLevel>latest</AnalysisLevel>
  </PropertyGroup>

  <PropertyGroup>
    <Authors>Your Company</Authors>
    <Company>Your Company</Company>
    <Copyright>Copyright © Your Company 2026</Copyright>
    <Product>MyDurableTaskApp</Product>
    <Version>1.0.0</Version>
  </PropertyGroup>
</Project>
```

---

## Worker Service Template

### MyApp.Worker/Program.cs

```csharp
using MyApp.Infrastructure.SqlServer;
using MyApp.Infrastructure.Monitoring;
using MyApp.Orchestrations.Orchestrations;
using MyApp.Orchestrations.Activities;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using DurableTask.Core;
using DurableTask.SqlServer;

namespace MyApp.Worker;

public sealed class Program
{
    public static async Task<int> Main(string[] args)
    {
        try
        {
            await CreateHostBuilder(args).Build().RunAsync();
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Fatal error: {ex}");
            return 1;
        }
    }

    private static IHostBuilder CreateHostBuilder(string[] args) =>
        Host.CreateDefaultBuilder(args)
            .UseWindowsService(options =>
            {
                options.ServiceName = "MyApp DurableTask Worker";
            })
            .ConfigureAppConfiguration((context, config) =>
            {
                config
                    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
                    .AddJsonFile($"appsettings.{context.HostingEnvironment.EnvironmentName}.json", 
                        optional: true, reloadOnChange: true)
                    .AddEnvironmentVariables(prefix: "MYAPP_")
                    .AddCommandLine(args);
            })
            .ConfigureLogging((context, logging) =>
            {
                logging
                    .ClearProviders()
                    .AddConfiguration(context.Configuration.GetSection("Logging"))
                    .AddConsole()
                    .AddDebug()
                    .AddEventLog(settings =>
                    {
                        settings.SourceName = "MyApp.Worker";
                    });
            })
            .ConfigureServices((context, services) =>
            {
                // Configuration
                services.Configure<DurableTaskOptions>(
                    context.Configuration.GetSection("DurableTask"));

                // SQL Server service
                var connectionString = context.Configuration
                    .GetConnectionString("DurableTask")
                    ?? throw new InvalidOperationException("Connection string not configured");

                var sqlService = SqlOrchestrationServiceFactory.CreateService(
                    connectionString,
                    context.Configuration["DurableTask:SchemaName"] ?? "dt",
                    context.Configuration["DurableTask:TaskHubName"] ?? "DefaultHub");

                services.AddSingleton<IOrchestrationService>(sqlService);

                // Worker service
                services.AddHostedService<DurableTaskWorkerService>();

                // Monitoring
                services.AddSingleton(connectionString);
                services.AddHostedService<DurableTaskMetricsCollector>();

                // Maintenance
                services.AddHostedService<OrchestrationArchivalService>();

                // Health checks
                services.AddHealthChecks()
                    .AddCheck<DurableTaskHealthCheck>("durabletask");

                // Application services (for dependency injection into activities)
                services.AddScoped<IEmailService, EmailService>();
                services.AddScoped<IPaymentGateway, PaymentGateway>();
                services.AddHttpClient();
            });
}

/// <summary>
/// Configuration options for DurableTask.
/// </summary>
public sealed class DurableTaskOptions
{
    public string SchemaName { get; set; } = "dt";
    public string TaskHubName { get; set; } = "DefaultHub";
    public int MaxConcurrentOrchestrations { get; set; } = 50;
    public int MaxConcurrentActivities { get; set; } = 100;
    public int WorkItemBatchSize { get; set; } = 50;
}
```

### MyApp.Worker/DurableTaskWorkerService.cs

```csharp
using DurableTask.Core;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using MyApp.Orchestrations.Orchestrations;
using MyApp.Orchestrations.Activities;

namespace MyApp.Worker;

/// <summary>
/// Hosted service that runs the DurableTask worker.
/// </summary>
public sealed class DurableTaskWorkerService : BackgroundService
{
    private readonly IOrchestrationService _orchestrationService;
    private readonly ILogger<DurableTaskWorkerService> _logger;
    private readonly ILoggerFactory _loggerFactory;
    private readonly IServiceProvider _serviceProvider;
    private readonly DurableTaskOptions _options;
    private TaskHubWorker? _worker;

    public DurableTaskWorkerService(
        IOrchestrationService orchestrationService,
        ILogger<DurableTaskWorkerService> logger,
        ILoggerFactory loggerFactory,
        IServiceProvider serviceProvider,
        IOptions<DurableTaskOptions> options)
    {
        _orchestrationService = orchestrationService;
        _logger = logger;
        _loggerFactory = loggerFactory;
        _serviceProvider = serviceProvider;
        _options = options.Value;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("DurableTask worker starting");

        try
        {
            // Create database schema if not exists
            await _orchestrationService.CreateIfNotExistsAsync();
            _logger.LogInformation("Database schema verified");

            // Create worker
            _worker = new TaskHubWorker(_orchestrationService, _loggerFactory)
            {
                ErrorPropagationMode = ErrorPropagationMode.UseFailureDetails,
                MaxConcurrentTaskOrchestrations = _options.MaxConcurrentOrchestrations,
                MaxConcurrentTaskActivities = _options.MaxConcurrentActivities
            };

            // Register orchestrations
            RegisterOrchestrations(_worker);

            // Register activities with DI support
            RegisterActivities(_worker);

            // Start worker
            await _worker.StartAsync();
            _logger.LogInformation(
                "DurableTask worker started - MaxOrch: {MaxOrch}, MaxAct: {MaxAct}",
                _options.MaxConcurrentOrchestrations,
                _options.MaxConcurrentActivities);

            // Keep running until cancellation
            await Task.Delay(Timeout.Infinite, stoppingToken);
        }
        catch (OperationCanceledException)
        {
            _logger.LogInformation("DurableTask worker shutdown requested");
        }
        catch (Exception ex)
        {
            _logger.LogCritical(ex, "DurableTask worker failed to start");
            throw;
        }
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("DurableTask worker stopping");

        if (_worker != null)
        {
            await _worker.StopAsync();
            _logger.LogInformation("DurableTask worker stopped");
        }

        await base.StopAsync(cancellationToken);
    }

    private void RegisterOrchestrations(TaskHubWorker worker)
    {
        worker.AddTaskOrchestrations(
            typeof(OrderProcessingOrchestration),
            typeof(PaymentOrchestration),
            typeof(ShipmentOrchestration)
        );

        _logger.LogInformation("Registered {Count} orchestrations", 3);
    }

    private void RegisterActivities(TaskHubWorker worker)
    {
        // Register activities with dependency injection support
        worker.AddTaskActivities(
            new ValidateOrderActivity(_serviceProvider),
            new ProcessPaymentActivity(_serviceProvider),
            new ShipOrderActivity(_serviceProvider),
            new SendNotificationActivity(_serviceProvider)
        );

        _logger.LogInformation("Registered {Count} activities", 4);
    }
}
```

### MyApp.Worker/appsettings.json

```json
{
  "ConnectionStrings": {
    "DurableTask": "Server=localhost;Database=DurableTask;Integrated Security=true;TrustServerCertificate=true;MultipleActiveResultSets=true;Min Pool Size=10;Max Pool Size=200;Application Name=MyApp.Worker;"
  },
  "DurableTask": {
    "SchemaName": "dt",
    "TaskHubName": "MyAppHub",
    "MaxConcurrentOrchestrations": 50,
    "MaxConcurrentActivities": 100,
    "WorkItemBatchSize": 50
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft": "Warning",
      "Microsoft.Hosting.Lifetime": "Information",
      "DurableTask": "Information"
    }
  }
}
```

### MyApp.Worker/appsettings.Production.json

```json
{
  "ConnectionStrings": {
    "DurableTask": "Server=prod-sql-server;Database=DurableTask;User Id=durabletask_user;Password=${SQL_PASSWORD};Encrypt=true;TrustServerCertificate=false;MultipleActiveResultSets=true;Min Pool Size=20;Max Pool Size=500;Application Name=MyApp.Worker.Production;"
  },
  "DurableTask": {
    "MaxConcurrentOrchestrations": 200,
    "MaxConcurrentActivities": 500,
    "WorkItemBatchSize": 100
  },
  "Logging": {
    "LogLevel": {
      "Default": "Warning",
      "Microsoft": "Error",
      "DurableTask": "Information"
    }
  }
}
```

---

## API Client Template

### MyApp.Client/IDurableTaskClient.cs

```csharp
using MyApp.Client.Models;

namespace MyApp.Client;

/// <summary>
/// Client interface for interacting with DurableTask orchestrations.
/// </summary>
public interface IDurableTaskClient
{
    /// <summary>
    /// Start a new orchestration instance.
    /// </summary>
    Task<OrchestrationInstance> StartOrchestrationAsync<TInput>(
        string orchestrationName,
        TInput input,
        string? instanceId = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Get the status of an orchestration instance.
    /// </summary>
    Task<OrchestrationStatus?> GetOrchestrationStatusAsync(
        string instanceId,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Wait for an orchestration to complete.
    /// </summary>
    Task<TOutput?> WaitForOrchestrationCompletionAsync<TOutput>(
        string instanceId,
        TimeSpan timeout,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Raise an event to an orchestration.
    /// </summary>
    Task RaiseEventAsync<TEventData>(
        string instanceId,
        string eventName,
        TEventData eventData,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Terminate an orchestration.
    /// </summary>
    Task TerminateOrchestrationAsync(
        string instanceId,
        string reason,
        CancellationToken cancellationToken = default);
}

public sealed record OrchestrationInstance(string InstanceId, string ExecutionId);
```

### MyApp.Client/DurableTaskClient.cs

```csharp
using DurableTask.Core;
using Microsoft.Extensions.Logging;
using MyApp.Client.Models;
using System.Text.Json;

namespace MyApp.Client;

/// <summary>
/// Client implementation for DurableTask orchestrations.
/// </summary>
public sealed class DurableTaskClient : IDurableTaskClient
{
    private readonly TaskHubClient _taskHubClient;
    private readonly ILogger<DurableTaskClient> _logger;

    public DurableTaskClient(
        TaskHubClient taskHubClient,
        ILogger<DurableTaskClient> logger)
    {
        _taskHubClient = taskHubClient;
        _logger = logger;
    }

    public async Task<OrchestrationInstance> StartOrchestrationAsync<TInput>(
        string orchestrationName,
        TInput input,
        string? instanceId = null,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "Starting orchestration {OrchestrationName} with instance ID {InstanceId}",
            orchestrationName,
            instanceId ?? "(auto-generated)");

        var instance = await _taskHubClient.CreateOrchestrationInstanceAsync(
            orchestrationName,
            version: string.Empty,
            instanceId: instanceId,
            input: input);

        _logger.LogInformation(
            "Orchestration started - InstanceId: {InstanceId}, ExecutionId: {ExecutionId}",
            instance.InstanceId,
            instance.ExecutionId);

        return new OrchestrationInstance(instance.InstanceId, instance.ExecutionId);
    }

    public async Task<OrchestrationStatus?> GetOrchestrationStatusAsync(
        string instanceId,
        CancellationToken cancellationToken = default)
    {
        var state = await _taskHubClient.GetOrchestrationStateAsync(instanceId);

        if (state == null)
        {
            return null;
        }

        return new OrchestrationStatus
        {
            InstanceId = state.OrchestrationInstance.InstanceId,
            ExecutionId = state.OrchestrationInstance.ExecutionId,
            Name = state.Name,
            Status = state.OrchestrationStatus.ToString(),
            Input = state.Input,
            Output = state.Output,
            CreatedTime = state.CreatedTime,
            CompletedTime = state.CompletedTime,
            LastUpdatedTime = state.LastUpdatedTime
        };
    }

    public async Task<TOutput?> WaitForOrchestrationCompletionAsync<TOutput>(
        string instanceId,
        TimeSpan timeout,
        CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "Waiting for orchestration {InstanceId} to complete (timeout: {Timeout})",
            instanceId,
            timeout);

        var stopwatch = System.Diagnostics.Stopwatch.StartNew();

        while (stopwatch.Elapsed < timeout)
        {
            if (cancellationToken.IsCancellationRequested)
            {
                throw new OperationCanceledException();
            }

            var state = await _taskHubClient.GetOrchestrationStateAsync(instanceId);

            if (state?.OrchestrationStatus == DurableTask.Core.OrchestrationStatus.Completed)
            {
                _logger.LogInformation(
                    "Orchestration {InstanceId} completed successfully",
                    instanceId);

                return JsonSerializer.Deserialize<TOutput>(state.Output);
            }

            if (state?.OrchestrationStatus == DurableTask.Core.OrchestrationStatus.Failed ||
                state?.OrchestrationStatus == DurableTask.Core.OrchestrationStatus.Terminated)
            {
                _logger.LogError(
                    "Orchestration {InstanceId} failed or terminated: {Output}",
                    instanceId,
                    state.Output);

                throw new InvalidOperationException(
                    $"Orchestration {instanceId} failed or terminated: {state.Output}");
            }

            await Task.Delay(500, cancellationToken);
        }

        throw new TimeoutException(
            $"Orchestration {instanceId} did not complete within {timeout}");
    }

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

        await _taskHubClient.RaiseEventAsync(instanceId, eventName, eventData);

        _logger.LogInformation(
            "Event {EventName} raised to orchestration {InstanceId}",
            eventName,
            instanceId);
    }

    public async Task TerminateOrchestrationAsync(
        string instanceId,
        string reason,
        CancellationToken cancellationToken = default)
    {
        _logger.LogWarning(
            "Terminating orchestration {InstanceId} - Reason: {Reason}",
            instanceId,
            reason);

        await _taskHubClient.TerminateInstanceAsync(instanceId, reason);

        _logger.LogWarning(
            "Orchestration {InstanceId} terminated",
            instanceId);
    }
}
```

### MyApp.Client/Models/OrchestrationStatus.cs

```csharp
namespace MyApp.Client.Models;

/// <summary>
/// Represents the status of an orchestration instance.
/// </summary>
public sealed record OrchestrationStatus
{
    public required string InstanceId { get; init; }
    public required string ExecutionId { get; init; }
    public required string Name { get; init; }
    public required string Status { get; init; }
    public string? Input { get; init; }
    public string? Output { get; init; }
    public DateTime CreatedTime { get; init; }
    public DateTime? CompletedTime { get; init; }
    public DateTime LastUpdatedTime { get; init; }
}
```

---

## Dependency Injection Setup

### Activity with DI

```csharp
using DurableTask.Core;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace MyApp.Orchestrations.Activities;

/// <summary>
/// Base class for activities with dependency injection support.
/// </summary>
public abstract class ServiceProviderActivity<TInput, TOutput> : TaskActivity<TInput, TOutput>
{
    protected IServiceProvider ServiceProvider { get; }

    protected ServiceProviderActivity(IServiceProvider serviceProvider)
    {
        ServiceProvider = serviceProvider;
    }

    protected override TOutput Execute(TaskContext context, TInput input)
    {
        // Create scope for scoped services
        using var scope = ServiceProvider.CreateScope();
        return ExecuteWithServices(context, input, scope.ServiceProvider);
    }

    protected abstract TOutput ExecuteWithServices(
        TaskContext context,
        TInput input,
        IServiceProvider serviceProvider);
}

/// <summary>
/// Example activity using dependency injection.
/// </summary>
public sealed class ProcessPaymentActivity : ServiceProviderActivity<PaymentRequest, PaymentResult>
{
    public ProcessPaymentActivity(IServiceProvider serviceProvider) 
        : base(serviceProvider)
    {
    }

    protected override PaymentResult ExecuteWithServices(
        TaskContext context,
        PaymentRequest input,
        IServiceProvider serviceProvider)
    {
        var logger = serviceProvider.GetRequiredService<ILogger<ProcessPaymentActivity>>();
        var paymentGateway = serviceProvider.GetRequiredService<IPaymentGateway>();

        logger.LogInformation(
            "Processing payment for order {OrderId}, amount {Amount}",
            input.OrderId,
            input.Amount);

        try
        {
            var transactionId = paymentGateway.ProcessPayment(
                input.CardNumber,
                input.Amount,
                input.Currency);

            logger.LogInformation(
                "Payment processed successfully - TransactionId: {TransactionId}",
                transactionId);

            return PaymentResult.Success(transactionId);
        }
        catch (PaymentDeclinedException ex)
        {
            logger.LogWarning(
                ex,
                "Payment declined for order {OrderId}",
                input.OrderId);

            throw; // Re-throw to mark activity as failed
        }
    }
}

public sealed record PaymentRequest
{
    public required string OrderId { get; init; }
    public required string CardNumber { get; init; }
    public required decimal Amount { get; init; }
    public required string Currency { get; init; }
}

public sealed record PaymentResult
{
    public required bool Success { get; init; }
    public string? TransactionId { get; init; }

    public static PaymentResult Success(string transactionId) => new()
    {
        Success = true,
        TransactionId = transactionId
    };
}

public interface IPaymentGateway
{
    string ProcessPayment(string cardNumber, decimal amount, string currency);
}

public sealed class PaymentDeclinedException : Exception
{
    public PaymentDeclinedException(string reason) : base(reason) { }
}
```

---

## Configuration Patterns

### Strongly-Typed Configuration

```csharp
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace MyApp.Infrastructure;

/// <summary>
/// Extension methods for configuration.
/// </summary>
public static class ConfigurationExtensions
{
    public static IServiceCollection AddDurableTaskConfiguration(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // Bind configuration sections
        services.Configure<DurableTaskOptions>(
            configuration.GetSection("DurableTask"));

        services.Configure<SqlServerOptions>(
            configuration.GetSection("SqlServer"));

        services.Configure<MonitoringOptions>(
            configuration.GetSection("Monitoring"));

        return services;
    }
}

public sealed class DurableTaskOptions
{
    public string SchemaName { get; set; } = "dt";
    public string TaskHubName { get; set; } = "DefaultHub";
    public int MaxConcurrentOrchestrations { get; set; } = 50;
    public int MaxConcurrentActivities { get; set; } = 100;
    public int WorkItemBatchSize { get; set; } = 50;
}

public sealed class SqlServerOptions
{
    public string ConnectionString { get; set; } = string.Empty;
    public int MinPoolSize { get; set; } = 10;
    public int MaxPoolSize { get; set; } = 200;
    public int CommandTimeout { get; set; } = 300;
}

public sealed class MonitoringOptions
{
    public bool EnableMetrics { get; set; } = true;
    public bool EnableHealthChecks { get; set; } = true;
    public TimeSpan MetricsCollectionInterval { get; set; } = TimeSpan.FromSeconds(30);
}
```

---

## Logging Setup

### Structured Logging

```csharp
using Microsoft.Extensions.Logging;
using DurableTask.Core;

namespace MyApp.Orchestrations.Orchestrations;

/// <summary>
/// Orchestration with structured logging.
/// </summary>
public sealed partial class OrderProcessingOrchestration : TaskOrchestration<OrderResult, OrderRequest>
{
    public override async Task<OrderResult> RunTask(
        OrchestrationContext context,
        OrderRequest input)
    {
        LogOrchestrationStarted(input.OrderId, input.CustomerId);

        try
        {
            // Validate order
            var isValid = await context.ScheduleTask<bool>(
                typeof(ValidateOrderActivity),
                input);

            if (!isValid)
            {
                LogOrderValidationFailed(input.OrderId);
                return OrderResult.ValidationFailed();
            }

            LogOrderValidationSucceeded(input.OrderId);

            // Process payment
            var paymentId = await context.ScheduleTask<string>(
                typeof(ProcessPaymentActivity),
                input);

            LogPaymentProcessed(input.OrderId, paymentId);

            // Ship order
            await context.ScheduleTask<bool>(
                typeof(ShipOrderActivity),
                new ShipmentRequest(input.OrderId, paymentId));

            LogOrderCompleted(input.OrderId, paymentId);

            return OrderResult.Success(input.OrderId, paymentId);
        }
        catch (Exception ex)
        {
            LogOrchestrationFailed(input.OrderId, ex);
            throw;
        }
    }

    // Source-generated logging methods (high performance)
    [LoggerMessage(
        EventId = 1000,
        Level = LogLevel.Information,
        Message = "Order processing started - OrderId: {OrderId}, CustomerId: {CustomerId}")]
    private static partial void LogOrchestrationStarted(string orderId, string customerId);

    [LoggerMessage(
        EventId = 1001,
        Level = LogLevel.Information,
        Message = "Order validation succeeded - OrderId: {OrderId}")]
    private static partial void LogOrderValidationSucceeded(string orderId);

    [LoggerMessage(
        EventId = 1002,
        Level = LogLevel.Warning,
        Message = "Order validation failed - OrderId: {OrderId}")]
    private static partial void LogOrderValidationFailed(string orderId);

    [LoggerMessage(
        EventId = 1003,
        Level = LogLevel.Information,
        Message = "Payment processed - OrderId: {OrderId}, PaymentId: {PaymentId}")]
    private static partial void LogPaymentProcessed(string orderId, string paymentId);

    [LoggerMessage(
        EventId = 1004,
        Level = LogLevel.Information,
        Message = "Order completed successfully - OrderId: {OrderId}, PaymentId: {PaymentId}")]
    private static partial void LogOrderCompleted(string orderId, string paymentId);

    [LoggerMessage(
        EventId = 1005,
        Level = LogLevel.Error,
        Message = "Order processing failed - OrderId: {OrderId}")]
    private static partial void LogOrchestrationFailed(string orderId, Exception ex);
}
```

---

## Code Generators

### T4 Template for Orchestrations

```xml
<!-- OrchestrationTemplate.tt -->
<#@ template language="C#" #>
<#@ output extension=".cs" #>
<#@ parameter name="OrchestrationName" type="System.String" #>
<#@ parameter name="InputType" type="System.String" #>
<#@ parameter name="OutputType" type="System.String" #>
using DurableTask.Core;
using Microsoft.Extensions.Logging;

namespace MyApp.Orchestrations.Orchestrations;

/// <summary>
/// Orchestration: <#= OrchestrationName #>
/// </summary>
public sealed class <#= OrchestrationName #> : TaskOrchestration<<#= OutputType #>, <#= InputType #>>
{
    private readonly ILogger<<#= OrchestrationName #>> _logger;

    public <#= OrchestrationName #>(ILogger<<#= OrchestrationName #>> logger)
    {
        _logger = logger;
    }

    public override async Task<<#= OutputType #>> RunTask(
        OrchestrationContext context,
        <#= InputType #> input)
    {
        _logger.LogInformation("Starting <#= OrchestrationName #>");

        try
        {
            // TODO: Implement orchestration logic

            _logger.LogInformation("<#= OrchestrationName #> completed successfully");
            return default!;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "<#= OrchestrationName #> failed");
            throw;
        }
    }
}
```

---

## Development Environment

### .editorconfig

```ini
root = true

[*]
charset = utf-8
insert_final_newline = true
trim_trailing_whitespace = true

[*.cs]
indent_style = space
indent_size = 4

# Code style rules
csharp_prefer_braces = true:warning
csharp_prefer_simple_using_statement = true:suggestion
csharp_style_namespace_declarations = file_scoped:warning
csharp_style_prefer_method_group_conversion = true:silent
csharp_style_expression_bodied_methods = false:silent
csharp_style_expression_bodied_constructors = false:silent
csharp_style_expression_bodied_operators = false:silent
csharp_style_expression_bodied_properties = true:silent
csharp_style_expression_bodied_indexers = true:silent
csharp_style_expression_bodied_accessors = true:silent

# Naming conventions
dotnet_naming_rule.interface_should_be_begins_with_i.severity = warning
dotnet_naming_rule.interface_should_be_begins_with_i.symbols = interface
dotnet_naming_rule.interface_should_be_begins_with_i.style = begins_with_i

dotnet_naming_style.begins_with_i.required_prefix = I
dotnet_naming_style.begins_with_i.capitalization = pascal_case

# Nullable reference types
dotnet_diagnostic.CS8618.severity = error # Non-nullable field must contain non-null value
dotnet_diagnostic.CS8625.severity = error # Cannot convert null literal to non-nullable reference

[*.{json,yml,yaml}]
indent_style = space
indent_size = 2
```

---

## Complete Example Project

See the attached complete project structure with all files in the solution directory.

Key files generated:
- ✅ 4 project files (.csproj)
- ✅ Program.cs with full DI setup
- ✅ Configuration files (appsettings.json)
- ✅ Client library
- ✅ Activity base class with DI
- ✅ SQL scripts
- ✅ Deployment scripts

---

## Summary

This module covered:

✅ **Project Structure**: Recommended organization  
✅ **Core Templates**: .csproj files with .NET 9+  
✅ **Worker Service**: Complete hosted service implementation  
✅ **API Client**: Type-safe client library  
✅ **Dependency Injection**: DI-enabled activities  
✅ **Configuration**: Strongly-typed configuration  
✅ **Logging**: Source-generated structured logging  
✅ **Code Generators**: T4 templates  
✅ **Development Setup**: .editorconfig, Directory.Build.props  

**Next**: [08-TROUBLESHOOTING.md](./08-TROUBLESHOOTING.md) - Common issues, diagnostics, and solutions.
