# Scaffold Workflow

Create a complete .NET Framework 4.8 Web API project from scratch.

## Step 1: Gather Parameters

Ask the user (if not already provided):
- **SolutionName** — e.g., `ERP.Vendas` (used as prefix for all projects)
- **OutputPath** — directory where the solution will be created (default: current directory)
- **CompanyName** — for Swagger contact info (default: "Sua Empresa")
- **ContactEmail** — for Swagger contact info (default: "contato@empresa.com")

## Step 2: Create Directory Structure

```bash
# Replace {SolutionName} and {OutputPath} with actual values
mkdir -p "{OutputPath}/{SolutionName}/src/Api/{SolutionName}.Api/Controllers"
mkdir -p "{OutputPath}/{SolutionName}/src/Api/{SolutionName}.Api/Infrastructure/DependencyInjection"
mkdir -p "{OutputPath}/{SolutionName}/src/Api/{SolutionName}.Api/Infrastructure/Filters"
mkdir -p "{OutputPath}/{SolutionName}/src/Core/{SolutionName}.Core/Models"
mkdir -p "{OutputPath}/{SolutionName}/src/Core/{SolutionName}.Core.Contracts/Services"
mkdir -p "{OutputPath}/{SolutionName}/src/Infrastructure/{SolutionName}.Infrastructure/Data"
mkdir -p "{OutputPath}/{SolutionName}/tests/{SolutionName}.Tests"
mkdir -p "{OutputPath}/{SolutionName}/logs"
```

## Step 3: Generate Files

For each file listed below, substitute `{SolutionName}`, `{CompanyName}`, and `{ContactEmail}` with actual values.

Use `FrameworkReference.md` as the authoritative source for all file contents.

### Files to Generate

| File | Template Source |
|------|----------------|
| `src/Api/{SolutionName}.Api/{SolutionName}.Api.csproj` | NuGet Packages section |
| `src/Api/{SolutionName}.Api/Startup.cs` | Startup.cs Template |
| `src/Api/{SolutionName}.Api/Infrastructure/DependencyInjection/LamarDependencyResolver.cs` | LamarDependencyResolver.cs Template |
| `src/Api/{SolutionName}.Api/Infrastructure/DependencyInjection/ServiceRegistryExtensions.cs` | ServiceRegistryExtensions.cs Template |
| `src/Api/{SolutionName}.Api/Infrastructure/Filters/GlobalExceptionFilterAttribute.cs` | GlobalExceptionFilterAttribute.cs Template |
| `src/Api/{SolutionName}.Api/Infrastructure/Filters/ValidateModelAttribute.cs` | ValidateModelAttribute.cs Template |
| `src/Api/{SolutionName}.Api/Infrastructure/GlobalExceptionHandler.cs` | GlobalExceptionHandler.cs Template |
| `src/Api/{SolutionName}.Api/Controllers/BaseApiController.cs` | BaseApiController.cs Template |
| `src/Api/{SolutionName}.Api/Controllers/ExampleController.cs` | Example Controller Template |
| `src/Api/{SolutionName}.Api/Web.config` | Web.config Template |

## Step 4: Namespace Substitution Rules

When generating each file, apply these replacements:

| Placeholder | Replace With |
|-------------|-------------|
| `YourApp` | `{SolutionName}` |
| `Sua Empresa` | `{CompanyName}` |
| `contato@empresa.com` | `{ContactEmail}` |
| `YourApp API` | `{SolutionName} API` |
| `API do ERP Adaptive` | `API {SolutionName}` |

## Step 5: Verify

After generating files, confirm:
- [ ] All files created with correct namespaces
- [ ] `[assembly: OwinStartup(typeof({SolutionName}.Api.Startup))]` present in Startup.cs
- [ ] csproj references all required NuGet packages
- [ ] Web.config has OWIN startup key

## Step 6: Summary

Output a summary:
```
✅ Projeto {SolutionName}.Api criado com sucesso!

Estrutura gerada:
  src/Api/{SolutionName}.Api/
  src/Core/{SolutionName}.Core/
  src/Core/{SolutionName}.Core.Contracts/
  src/Infrastructure/{SolutionName}.Infrastructure/
  tests/{SolutionName}.Tests/

Próximos passos:
  1. Abrir {SolutionName}.sln no Visual Studio
  2. Restaurar pacotes NuGet: dotnet restore
  3. Ajustar conexão com banco em Web.config (se necessário)
  4. Implementar interfaces em {SolutionName}.Core.Contracts/Services/
```
