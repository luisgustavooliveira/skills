---
name: create-api-framework48
description: Scaffolds a modern .NET Framework 4.8 Web API project with OWIN, Lamar DI, Serilog, Swagger, and best-practice patterns. USE WHEN create api net48, scaffold dotnet framework 4.8 api, new api project net framework, initialize net48 api, criar api net framework 4.8, criar projeto api dotnet 48.
---

# CreateApiFramework48

Initializes a complete .NET Framework 4.8 Web API project following modern patterns: OWIN hosting, Lamar IoC, Serilog structured logging, Swashbuckle Swagger, global exception handling, and layered architecture.

## Workflow Routing

**When executing a workflow, output this notification:**

```
Running the **WorkflowName** workflow from the **CreateApiFramework48** skill...
```

| Workflow | Trigger | File |
|----------|---------|------|
| **Scaffold** | "create api", "scaffold project", "initialize", "criar api", "novo projeto" | `Workflows/Scaffold.md` |
| **AddLayer** | "add layer", "add infrastructure", "add core", "adicionar camada" | `Workflows/AddLayer.md` |

## Examples

**Example 1: Scaffold a new project from scratch**
```
User: "Create a .NET Framework 4.8 API project called ERP.Vendas"
→ Invokes Scaffold workflow
→ Creates solution/project folder structure
→ Generates all scaffolding files (csproj, Startup.cs, controllers, filters, DI wiring)
→ User gets a ready-to-build project
```

**Example 2: Add a new layer to an existing project**
```
User: "Add an Infrastructure layer to my existing YourApp solution"
→ Invokes AddLayer workflow
→ Creates YourApp.Infrastructure project with correct references
→ Wires repository/unit-of-work patterns
```

## Reference

Full scaffolding details: `FrameworkReference.md`
