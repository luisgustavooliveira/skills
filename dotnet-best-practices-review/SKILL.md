---
name: dotnet-best-practices-review
description: Review, refactor, and improve .NET/C# source code using a systematic workflow for modern .NET 9+ applications, applying .NET 10 and C# 14 practices only when they provide clear gains in correctness, performance, quality, security, observability, or maintainability. Use this skill when asked to analyze selected C# code, identify gaps, plan changes, assess impacts, verify or add tests, run build/test loops, modernize APIs, improve dependency injection, async flows, configuration, logging, localization, architecture, data access, AI/agent integration, or code quality in .NET projects.
---

# .NET/C# Best Practices

Use this skill to analyze, refactor, and improve .NET/C# code in `${selection}` through a disciplined workflow.

The goal is not merely to suggest improvements. The goal is to operate like a careful senior engineer: understand the current behavior, identify gaps, plan safe changes, protect behavior with tests, implement the smallest useful change, run build and tests, fix failures, and only then move to the next code block.

Prefer simple, explicit, maintainable solutions. Do not modernize code just to use new language or framework features. Use .NET 10 and C# 14 features only when they provide a practical benefit.

---

## Operating Principles

Follow these principles throughout the review:

1. Correctness and safety come first.
2. Preserve observable behavior unless an intentional behavior change is requested.
3. Make small, reversible changes.
4. Prefer domain clarity over technical cleverness.
5. Add or adjust tests before risky behavior changes whenever possible.
6. Execute build and tests when repository/tool access is available.
7. Do not hide failures by weakening tests, suppressing warnings, or broadening exception handling.
8. Use modern .NET/C# features only when they improve clarity, correctness, performance, or maintainability.
9. Avoid speculative abstractions.
10. Document assumptions, risks, and trade-offs clearly.

---

# Core Workflow

Analyze and improve code block by block.

A block may be:

- A method
- A class
- An endpoint
- A handler
- A service
- A domain entity
- A value object
- A repository/query object
- A cohesive set of files
- A small vertical flow such as request → handler → repository

Do not modify many unrelated blocks at once. Large changes make failures harder to diagnose and increase review risk.

For each block, execute this workflow:

1. Delimit the block.
2. Understand current behavior.
3. Identify gaps.
4. Plan changes.
5. Identify impacts.
6. Verify test coverage.
7. Add or adjust tests when appropriate.
8. Run relevant tests before implementation when possible.
9. Implement changes.
10. Run a clean build.
11. Run tests again.
12. Enter a correction loop if build or tests fail.
13. Close the block.
14. Move to the next block.

---

## 1. Delimit the Block

Before changing code, define the exact scope of analysis.

Identify:

- Files involved
- Main responsibility
- Public surface area
- Dependencies
- External effects
- Risk level
- Related tests, if any

Prefer small cohesive units. If the selected code is large, split it into smaller blocks and process them sequentially.

Expected output:

```markdown
## Current block

- Files analyzed:
- Main responsibility:
- Public surface area:
- Relevant dependencies:
- Risk level:
```

---

## 2. Understand Current Behavior

Explain what the code currently does before proposing changes.

Identify:

- Inputs
- Outputs
- Side effects
- Domain rules
- Validation rules
- Error behavior
- Async behavior
- Cancellation behavior
- External calls
- Database access
- File access
- Queue/message interactions
- AI/model/tool calls
- Disposable resources
- State changes

Do not refactor code that is not yet understood.

If behavior is ambiguous, state the assumption explicitly.

Expected output:

```markdown
## Current behavior

- Input:
- Output:
- Side effects:
- Domain rules:
- Error behavior:
- Assumptions:
```

---

## 3. Identify Gaps

Analyze the block against this skill's technical criteria.

Classify each gap by severity:

- **Critical**: bug, security issue, data loss risk, deadlock, race condition, incorrect behavior, broken contract.
- **High**: weak validation, poor testability, unsafe dependency lifetime, missing observability, likely production failure.
- **Medium**: duplication, unclear naming, excessive coupling, missing useful tests, maintainability issue.
- **Low**: style, minor documentation issue, minor modernization opportunity, small readability improvement.

Do not label stylistic preferences as critical issues.

Check at least these categories:

- Functional correctness
- Security
- Input validation
- Error handling
- Logging and observability
- Async/await and cancellation
- Dependency injection and service lifetimes
- Configuration/options
- Testability
- Existing test coverage
- Performance
- Data access
- Resource management
- Localization
- Public documentation
- Architecture consistency
- Modern .NET/C# usage

Expected output:

```markdown
## Gaps found

| Severity | Category | Problem | Evidence | Risk |
|---|---|---|---|---|
| High | Validation | ... | ... | ... |
```

---

## 4. Plan Changes

Before editing code, create a minimal plan.

The plan must describe:

- What will change
- What will not change
- Why the change is needed
- Which behavior must remain the same
- Which tests should protect the change
- Risks and trade-offs

Avoid full rewrites when a local change solves the problem.

Expected output:

```markdown
## Change plan

1. ...
2. ...
3. ...

## Out of scope

- ...

## Behavior to preserve

- ...
```

---

## 5. Identify Impacts

Before implementation, assess impact on:

- Callers
- Public APIs
- HTTP contracts
- DTOs
- Serialization
- Database schema
- Migrations
- Queries
- Message contracts
- Background jobs
- Configuration
- Dependency injection registrations
- Logs, metrics, and dashboards
- Tests
- Deployment
- Performance
- Security
- Backward compatibility

Highlight breaking changes clearly.

Expected output:

```markdown
## Expected impacts

- Affected callers:
- Changed contracts:
- Configuration impact:
- Test impact:
- Compatibility risks:
```

---

## 6. Verify Test Coverage

Before changing implementation, search for existing tests related to the block.

Look for:

- Unit tests
- Integration tests
- Endpoint/API tests
- Persistence tests
- Validation tests
- Error-path tests
- Cancellation tests
- Authorization/authentication tests
- Serialization tests
- Regression tests

If no tests exist, decide whether the change requires tests before implementation.

Rule: if a change can alter observable behavior, add or adjust tests before modifying implementation whenever repository/tool access allows it.

Expected output:

```markdown
## Test coverage

- Existing tests found:
- Covered scenarios:
- Missing scenarios:
- Tests to add before the change:
```

---

## 7. Add or Adjust Tests

Add tests before implementation when the change involves:

- Bug fixes
- Domain rules
- Validation behavior
- Serialization contracts
- Data access behavior
- Error handling
- Authorization behavior
- Async/cancellation behavior
- External integration behavior
- Refactoring critical code

Use:

- xUnit
- FluentAssertions
- NSubstitute
- coverlet.collector

Follow AAA:

```csharp
// Arrange

// Act

// Assert
```

Avoid brittle tests that assert unnecessary implementation details.

Prefer behavior-focused tests.

Expected output:

```markdown
## Tests added or changed

- ...
```

---

## 8. Run Relevant Tests Before Implementation

When execution is available, run the tests related to the current block before changing implementation.

Common commands:

```bash
dotnet test
```

For a specific project:

```bash
dotnet test path/to/Project.Tests.csproj
```

With a reliable filter:

```bash
dotnet test --filter FullyQualifiedName~BillingService
```

If tests fail before the change, record the failure as pre-existing. Do not attribute pre-existing failures to the refactoring.

Expected output:

```markdown
## Test result before implementation

- Command executed:
- Result:
- Pre-existing failures:
```

---

## 9. Implement Changes

Implement the planned changes in the smallest useful set of files.

During implementation:

- Preserve behavior protected by tests.
- Avoid opportunistic changes outside the current block.
- Keep names aligned with domain concepts.
- Use modern C# only when it improves the solution.
- Update XML documentation for relevant public APIs.
- Update DI, configuration, resources, or documentation when required.
- Avoid speculative abstractions.
- Avoid broad catch-all error handling.
- Avoid weakening validation.

Expected output:

```markdown
## Changes implemented

- ...
```

---

## 10. Run a Clean Build

After implementation, run a clean build when execution is available.

Preferred commands:

```bash
dotnet clean
dotnet restore
dotnet build --no-restore
```

For a solution:

```bash
dotnet build path/to/Solution.sln --no-restore
```

Preserve the project's warning policy. If warnings are treated as errors, do not bypass that rule.

Do not suppress warnings without a clear technical reason.

Expected output:

```markdown
## Build result

- Command executed:
- Result:
- Errors:
- Relevant warnings:
```

---

## 11. Run Tests Again

After a successful build, run relevant tests again.

Common command:

```bash
dotnet test --no-build
```

For a specific test project:

```bash
dotnet test path/to/Project.Tests.csproj --no-build
```

If the change affects multiple modules, run a broader test suite before closing the block.

Expected output:

```markdown
## Test result after implementation

- Command executed:
- Result:
- Failures:
```

---

## 12. Correction Loop

If build or tests fail, enter a controlled correction loop.

Loop steps:

1. Read the full failure.
2. Identify the likely root cause.
3. Apply the smallest targeted fix.
4. Re-run the failed build or test command.
5. Repeat until build and relevant tests pass.
6. After the targeted command passes, run the relevant test suite again.
7. Exit the loop only when there are no relevant build or test failures.

Correction loop rules:

- Do not make random changes.
- Do not weaken tests to hide bugs.
- Do not remove assertions without justification.
- Do not reduce test scope merely to pass.
- Do not add `#pragma warning disable` without a strong reason.
- Do not mask exceptions.
- Do not comment out broken code without explanation.
- If a failure is clearly pre-existing and outside scope, document it.

Expected output:

```markdown
## Correction loop

### Iteration 1

- Failure:
- Root cause:
- Fix:
- Result:

### Iteration 2

- ...
```

---

## 13. Close the Block

Close a block only when:

- Expected behavior is preserved or intentionally changed.
- Build passes, if execution is available.
- Relevant tests pass, if execution is available.
- Impacts are documented.
- Remaining risks are documented.
- No unrelated change was introduced.
- Test coverage is adequate for the risk level.

Expected output:

```markdown
## Block closure

- Build: passed / failed / not executed
- Tests: passed / failed / not executed
- Remaining risks:
- Recommended next block:
```

---

## 14. Move to the Next Block

After closing the current block, move to the next cohesive block.

Prioritize blocks in this order:

1. Code with functional or security defects.
2. High-risk code without tests.
3. Highly coupled code.
4. Frequently executed code.
5. Code with unclear behavior.
6. Minor modernization opportunities.

Do not move to the next block if the current block is broken, unless the failure is clearly pre-existing and outside the current scope.

---

# Workflow Summary

```text
For each block:
  Delimit the block
  Understand current behavior
  Identify gaps
  Plan changes
  Identify impacts
  Verify existing tests

  If the change can alter observable behavior:
    Add or adjust tests first, when possible
    Run relevant tests

  Implement changes

  Repeat:
    Run clean build
    If build fails:
      Fix the smallest likely cause
      Continue

    Run relevant tests
    If tests fail:
      Fix the smallest likely cause
      Continue

    Exit loop

  Record outcome
  Move to the next block
```

---

# Execution Policy

When repository and command execution are available:

- Inspect related files before editing.
- Use real `dotnet build` and `dotnet test` commands.
- Prefer filtered tests during fast iteration.
- Run a broader suite before final closure when risk justifies it.
- Report commands executed and results.

When repository or command execution is not available:

- Perform static analysis of the provided code.
- Provide the commands that should be executed by the user.
- Provide suggested tests.
- Clearly state that build and tests were not executed.

Use this statement when applicable:

```markdown
Build and tests were not executed because repository/tool access is not available in this conversation. The analysis is static and should be validated with `dotnet build` and `dotnet test`.
```

---

# Stop Conditions

Stop and ask for guidance when:

- The change requires a product or business-rule decision that cannot be inferred.
- A public API breaking change is required.
- There is risk of data loss.
- A destructive migration is required.
- Existing tests contradict the expected behavior.
- The fix requires architecture changes beyond the current block.
- Build fails because an external dependency is unavailable.
- The test suite reveals pre-existing failures outside the current scope.
- Security implications are unclear.
- The requested change conflicts with project conventions.

If stopping, explain:

- What was discovered
- Why the workflow cannot safely continue
- What decision or input is needed
- What can still be done safely

---

# Technical Criteria

Use the following criteria while executing the workflow.

---

## Documentation and Structure

- Add XML documentation to public APIs that are part of an external contract, shared library, SDK, domain-critical component, or cross-team surface.
- Avoid redundant XML comments that only repeat member names.
- Include `<summary>`, `<param>`, `<returns>`, and `<exception>` when relevant.
- Document invariants, side effects, domain rules, and edge cases.
- Follow the namespace structure used by the project. When no stronger convention exists, prefer:

```text
{Core|Console|App|Service}.{Feature}
```

- Prefer namespaces, folders, and assemblies aligned with business capabilities rather than only technical layers.
- Avoid vague class names such as `Helper`, `Manager`, `Processor`, or `Service` when a domain-specific name is possible.

Example:

```csharp
namespace Core.Billing;

/// <summary>
/// Calculates billing cycles for customer contracts.
/// </summary>
public sealed class BillingCycleCalculator
{
    /// <summary>
    /// Calculates the next billing date according to the contract recurrence rule.
    /// </summary>
    /// <param name="contract">The contract used as the billing source.</param>
    /// <returns>The next billing date.</returns>
    /// <exception cref="ArgumentNullException">Thrown when <paramref name="contract"/> is null.</exception>
    public DateOnly CalculateNextBillingDate(Contract contract)
    {
        ArgumentNullException.ThrowIfNull(contract);

        // ...
    }
}
```

---

## .NET 9+, .NET 10, and C# Version Guidance

- Treat .NET 9+ as the modern baseline for APIs, performance, and maintainability.
- Apply .NET 10 practices when they provide a concrete gain in the specific code under review.
- Consider .NET 10 especially for:
  - Runtime and JIT improvements in hot paths.
  - NativeAOT scenarios with clear startup or footprint goals.
  - Improved diagnostics and observability.
  - Stronger JSON serialization options.
  - Cryptography APIs when applicable.
  - ASP.NET Core behavior improvements for APIs.
- Use C# 14 features when the project supports them and they improve clarity or reduce ceremony.
- Do not use preview features in production code without explicit project approval.
- Do not replace clear code with newer syntax if it reduces readability.

Prefer modern C# features when useful:

- `required` members for mandatory initialization.
- `record` and `record struct` for immutable values.
- Pattern matching for clear branching.
- Primary constructors for simple dependency injection scenarios.
- Collection expressions when clearer.
- `TimeProvider` for testable time-dependent code.
- `DateOnly` and `TimeOnly` for date/time modeling without unnecessary timezone semantics.
- `FrozenDictionary` and `FrozenSet` for immutable high-read lookup data.
- `Span<T>` and `ReadOnlySpan<T>` only for justified hot paths or parsing scenarios.

---

## Design Patterns and Architecture

- Apply SOLID pragmatically.
- Prefer composition over inheritance.
- Use interfaces for real contracts, extension points, testing seams, external integrations, or architectural boundaries.
- Do not create an interface for every class by default.
- Prefix interfaces with `I`.
- Use primary constructor syntax for dependency injection when:
  - The class is small or medium-sized.
  - Dependencies are used directly.
  - Readability remains good.
- Use a traditional constructor when:
  - Initialization logic is complex.
  - Validation is expressive.
  - The dependency list is long enough to indicate possible responsibility overload.
- Use the Factory pattern only for complex, conditional, or rule-based object creation.
- Prefer static factory methods, options, or builders when simpler than a dedicated factory type.
- Keep boundaries clear between:
  - Domain
  - Application/use cases
  - Infrastructure
  - APIs/adapters
  - External integrations

---

## Dependency Injection and Services

- Use constructor dependency injection.
- Validate required dependencies with `ArgumentNullException.ThrowIfNull` when using traditional constructors.
- Choose DI lifetimes deliberately:
  - `Singleton`: stateless services, thread-safe caches, immutable providers.
  - `Scoped`: request/unit-of-work services, DbContext/session-like components, transactional application services.
  - `Transient`: lightweight stateless services.
- Do not inject `IServiceProvider` except for legitimate factories, framework integration, or dynamic composition.
- Avoid Service Locator.
- Do not capture scoped services inside singletons.
- Use `IHttpClientFactory` for HTTP clients.
- Prefer typed HTTP clients for external services with clear contracts.
- Use extension methods to register cohesive modules.

Example:

```csharp
public static class BillingServiceCollectionExtensions
{
    public static IServiceCollection AddBilling(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services
            .AddOptions<BillingOptions>()
            .Bind(configuration.GetSection(BillingOptions.SectionName))
            .ValidateDataAnnotations()
            .ValidateOnStart();

        services.AddScoped<IBillingService, BillingService>();

        return services;
    }
}
```

---

## Configuration and Settings

- Use strongly typed options classes.
- Bind configuration at application composition boundaries.
- Validate options on startup with `ValidateOnStart`.
- Use `DataAnnotations` and custom validation where needed.
- Use `required` properties for mandatory options.
- Avoid scattered direct access to `IConfiguration` throughout application logic.
- Never commit secrets to `appsettings.json`.
- Use Secret Manager, environment variables, Azure Key Vault, or equivalent secret providers.
- Validate URLs, timeouts, limits, queue names, feature flags, and provider identifiers.

Example:

```csharp
public sealed class BillingOptions
{
    public const string SectionName = "Billing";

    [Required]
    public required string ApiBaseUrl { get; init; }

    [Range(1, 300)]
    public int TimeoutSeconds { get; init; } = 30;
}
```

---

## Resource Management and Localization

- Use `ResourceManager`, `.resx`, or project-approved localization abstractions for user-facing localized messages.
- Separate resources by intent when useful:
  - `LogMessages`
  - `ErrorMessages`
  - `ValidationMessages`
  - `UserMessages`
- Do not localize internal technical logs when it harms search, support, or correlation.
- Localize messages shown to end users.
- Use stable semantic keys.

Example:

```csharp
_resourceManager.GetString("Billing_InvalidCycle")
```

- Ensure fallback behavior when a resource key is missing.
- Avoid fragile concatenation of localized messages. Prefer format placeholders.

---

## Async/Await Patterns

- Use `async`/`await` for I/O, database access, HTTP calls, queues, files, and remote operations.
- Return `Task` or `Task<T>` from asynchronous methods.
- Use `ValueTask<T>` only with a clear performance reason and correct consumption semantics.
- Propagate `CancellationToken` through async APIs.
- Do not ignore cancellation tokens in database, HTTP, queue, file, or long-running operations.
- Avoid `.Result`, `.Wait()`, and sync-over-async.
- Use `ConfigureAwait(false)` in reusable libraries when no synchronization context is required.
- Do not require `ConfigureAwait(false)` universally in modern ASP.NET Core application code.
- Handle expected exceptions at appropriate boundaries:
  - Endpoint/controller
  - Message handler
  - Worker
  - Integration adapter
- Do not catch `Exception` only to rethrow without context.
- Use `await using` for asynchronous disposable resources.

Example:

```csharp
public async Task<Customer?> GetCustomerAsync(
    CustomerId customerId,
    CancellationToken cancellationToken)
{
    ArgumentNullException.ThrowIfNull(customerId);

    return await repository
        .FindByIdAsync(customerId, cancellationToken)
        .ConfigureAwait(false);
}
```

---

## Error Handling and Logging

- Throw specific exceptions with descriptive messages.
- Validate public method arguments at the boundary.
- Use `ArgumentNullException.ThrowIfNull` and `ArgumentException.ThrowIfNullOrWhiteSpace` when appropriate.
- Do not use exceptions for frequent expected domain flow.
- Use a Result pattern for normal, expected domain failures when appropriate.
- Use structured logging with `ILogger<T>`.
- Do not interpolate log messages.
- Use named log properties.

Example:

```csharp
logger.LogInformation(
    "Invoice {InvoiceId} was generated for customer {CustomerId}",
    invoice.Id,
    invoice.CustomerId);
```

- Use logging scopes for correlation context.

Example:

```csharp
using var scope = logger.BeginScope(new Dictionary<string, object?>
{
    ["CorrelationId"] = correlationId,
    ["TenantId"] = tenantId
});
```

- Do not log sensitive data, tokens, passwords, full fiscal documents, private prompts, or confidential payloads without masking and policy approval.
- Preserve stack traces by using `throw;` when rethrowing.

---

## Minimal APIs, Controllers, and HTTP

- Prefer Minimal APIs for small, cohesive endpoints and vertical slices.
- Prefer Controllers when project conventions, filters, complex versioning, or larger HTTP surfaces justify them.
- Use `TypedResults` in Minimal APIs when explicit response types improve clarity and OpenAPI output.
- Use dedicated request and response contracts.
- Validate input before invoking domain logic.
- Do not expose domain entities directly as external DTOs when the API contract evolves independently.
- Use Problem Details for standardized HTTP errors.
- Map known errors to appropriate HTTP status codes:
  - `400` for invalid input.
  - `401` for unauthenticated access.
  - `403` for unauthorized access.
  - `404` for missing resources.
  - `409` for state conflicts.
  - `422` for semantic validation errors if the project uses it.
  - `500` only for unexpected failures.

---

## Data Access and Persistence

- Always use parameterized queries.
- Never concatenate external input into SQL.
- Keep transactions short and explicit.
- Avoid N+1 queries.
- Use pagination for potentially large lists.
- Ensure indexes match real query patterns.
- Separate persistence models from API contracts when they evolve independently.
- Use optimistic concurrency when concurrent edits are possible.
- Do not hide expensive I/O behind properties or deceptively cheap methods.

For NHibernate:

- Configure lazy/eager loading deliberately.
- Avoid long-lived sessions.
- Prefer explicit queries for critical screens, reports, or integrations.
- Test important mappings against a real or containerized database when possible.
- Watch for accidental N+1 behavior caused by lazy navigation access.

---

## Performance

- Measure before optimizing when the change increases complexity.
- Use BenchmarkDotNet for microbenchmarks.
- Use tracing, metrics, and profiling for production-like bottlenecks.
- Reduce allocations in hot paths with appropriate tools:
  - `ArrayPool<T>`
  - `Memory<T>`
  - `Span<T>`
  - `ReadOnlySpan<T>`
  - `StringBuilder`
  - Allocation-free parsing techniques
- Use `FrozenDictionary` and `FrozenSet` for immutable, frequently-read lookup data.
- Avoid LINQ in proven hot paths when explicit loops are significantly better.
- Cache reflection metadata when reflection is required in repeated paths.
- Consider NativeAOT for CLIs, small workers, or services with strong startup/footprint requirements, only when dependencies are compatible.
- Do not sacrifice clarity for hypothetical micro-optimizations.

---

## Security

- Validate and sanitize external input.
- Prefer allowlists over denylists when feasible.
- Do not log secrets, tokens, passwords, API keys, personal data, or confidential payloads without masking.
- Use explicit authentication and authorization for endpoints.
- Apply least privilege.
- Use HTTPS.
- Configure CORS restrictively.
- Protect internal and diagnostic endpoints.
- Guard against SSRF when user input influences outbound URLs.
- Validate uploads by size, type, and content.
- Use official framework cryptography APIs.
- Avoid custom crypto.

For AI-enabled code:

- Treat prompts, retrieved documents, model outputs, and tool arguments as untrusted data.
- Do not execute model-generated commands, SQL, or code without validation.
- Protect tool-calling and RAG flows against prompt injection.
- Minimize sensitive data exposure to models.
- Log operational metadata rather than full sensitive prompts/responses unless policy allows it.

---

## Testing Standards

- Use xUnit as the default test framework.
- Use FluentAssertions for readable assertions.
- Use NSubstitute for mocks/substitutes.
- Use coverlet.collector for coverage.
- Follow AAA:
  - Arrange
  - Act
  - Assert
- Test:
  - Happy path
  - Expected failures
  - Null/invalid argument validation
  - Cancellation behavior
  - Idempotency when applicable
  - Concurrency when risky
  - Authorization when relevant
  - Serialization contracts when relevant
- Prefer unit tests for domain rules.
- Prefer integration tests for persistence, DI, endpoints, queues, and external adapters.
- Do not mock everything by default.
- Use builders, object mothers, or fixtures to reduce test setup noise.
- Test critical options validation.

Example:

```csharp
public sealed class BillingServiceTests
{
    [Fact]
    public async Task GenerateAsync_ShouldThrow_WhenCustomerIdIsNull()
    {
        // Arrange
        var service = CreateService();

        // Act
        var act = () => service.GenerateAsync(null!, CancellationToken.None);

        // Assert
        await act.Should().ThrowAsync<ArgumentNullException>();
    }
}
```

---

## Microsoft Agent Framework, Semantic Kernel, and AI Integration

- Prefer Microsoft Agent Framework for new agentic flows when the project accepts its maturity level and dependency model.
- Use Semantic Kernel when the project already depends on it or when current ecosystem stability is more important than early adoption.
- Isolate AI SDK usage behind application interfaces.
- Do not couple domain logic directly to AI SDKs.
- Model AI settings with strongly typed options:
  - Chat model
  - Embedding model
  - Temperature
  - Timeout
  - Token limits
  - Retry policy
  - Provider
- Use structured output when model responses feed automation, persistence, decisions, integrations, or workflows.
- Validate structured output with schemas or strong types.
- Provide fallbacks for model failure, timeout, throttling, invalid response, or provider outage.
- Add observability for:
  - Latency
  - Provider/model
  - Token usage or estimated cost when available
  - Error rate
  - Fallback reason
- For agents with tools:
  - Define small, explicit, auditable tools.
  - Validate tool arguments before execution.
  - Require authorization for destructive actions.
  - Log executed actions.
  - Avoid generic tools such as `ExecuteSql`, `RunCommand`, or `CallAnyApi` unless sandboxed and governed.

---

## Code Quality

- Keep methods focused and cohesive.
- Use names that express domain behavior.
- Remove duplication by extracting real concepts, not merely similar lines.
- Prefer early returns to reduce nesting.
- Avoid boolean parameters that drastically change behavior. Prefer explicit methods or types.
- Use guard clauses for preconditions.
- Make invalid states difficult or impossible to represent.
- Prefer immutability for value objects and input DTOs.
- Use `sealed` for classes not designed for inheritance.
- Avoid mutable global static state.
- Use analyzers and `.editorconfig` for consistency.
- Fix relevant warnings instead of suppressing them.
- Do not use `#pragma warning disable` without justification.

---

## Disposal and Resource Management

- Implement `IDisposable` or `IAsyncDisposable` only when the type owns disposable resources.
- Use `using` and `await using` appropriately.
- Do not dispose dependencies received from DI unless the class explicitly owns them.
- Avoid finalizers except for unmanaged resources.
- For streams, define ownership clearly.
- Do not close a stream received from a caller unless the contract says ownership was transferred.
- Dispose timers, subscriptions, event handlers, and background resources.
- Avoid memory leaks from captured closures and event subscriptions.

---

# Review Checklist

Before closing the response, verify:

- Is the current behavior understood?
- Are assumptions explicit?
- Are gaps classified by severity?
- Is the change plan minimal and safe?
- Are impacts identified?
- Are tests present or recommended for risky behavior?
- Was build executed when possible?
- Were tests executed when possible?
- Were failures handled through a controlled correction loop?
- Is async cancellation propagated where appropriate?
- Are logs structured and safe?
- Are options strongly typed and validated?
- Are DI lifetimes correct?
- Are exceptions specific and useful?
- Is there any N+1, deadlock, race condition, or resource leak risk?
- Does any .NET 10/C# 14 feature provide real value here?
- Is the final solution simpler for the next developer to maintain?

---

# Output Style

When executing this skill, use this structure by default:

```markdown
## Block 1: <block name>

### Current behavior

...

### Gaps found

...

### Change plan

...

### Expected impacts

...

### Test coverage

...

### Tests added or changed

...

### Changes implemented

...

### Build and test results

...

### Correction loop

...

### Block closure

...

---

## Block 2: <block name>

...
```

If no specific .NET 10 or C# 14 feature provides meaningful benefit, state:

```markdown
No specific .NET 10 or C# 14 feature provides a clear benefit for this block. The main improvements are in design, validation, tests, observability, or maintainability.
```

If build and tests could not be executed, state:

```markdown
Build and tests were not executed because repository/tool access is not available in this conversation. The analysis is static and should be validated with `dotnet build` and `dotnet test`.
```

Keep explanations concise, specific, and actionable. Avoid generic best-practice lectures unless they directly explain a change.
