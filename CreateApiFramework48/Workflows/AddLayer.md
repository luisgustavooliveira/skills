# AddLayer Workflow

Add a new layer (Infrastructure, Core, or Contracts) to an existing .NET Framework 4.8 solution.

## Step 1: Gather Parameters

Ask the user (if not already provided):
- **SolutionName** — existing solution prefix (e.g., `ERP.Vendas`)
- **LayerType** — `Infrastructure` | `Core` | `Contracts`
- **OutputPath** — root of the existing solution

## Step 2: Layer Definitions

### Infrastructure Layer

Creates `{SolutionName}.Infrastructure` with:
- `Data/Repository.cs` — generic repository pattern
- `Data/UnitOfWork.cs` — unit of work pattern
- `Reports/CrystalReportService.cs` — Crystal Reports integration stub
- `{SolutionName}.Infrastructure.csproj`

```xml
<!-- {SolutionName}.Infrastructure.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net48</TargetFramework>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
    <PackageReference Include="Polly" Version="7.2.4" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\Core\{SolutionName}.Core.Contracts\{SolutionName}.Core.Contracts.csproj" />
  </ItemGroup>
</Project>
```

### Core Layer

Creates `{SolutionName}.Core` with:
- `Services/ExampleService.cs` — example service implementation
- `Models/ExampleModel.cs` — example domain model
- `{SolutionName}.Core.csproj`

### Contracts Layer

Creates `{SolutionName}.Core.Contracts` with:
- `Services/IExampleService.cs` — service contract
- `Repositories/IRepository.cs` — generic repository contract
- `Repositories/IUnitOfWork.cs` — unit of work contract
- `{SolutionName}.Core.Contracts.csproj`

## Step 3: Generate IRepository Template

```csharp
// {SolutionName}.Core.Contracts/Repositories/IRepository.cs
using System.Collections.Generic;
using System.Threading.Tasks;

namespace {SolutionName}.Core.Contracts.Repositories
{
    public interface IRepository<T> where T : class
    {
        Task<T> GetByIdAsync(int id);
        Task<IEnumerable<T>> GetAllAsync();
        Task<T> AddAsync(T entity);
        Task UpdateAsync(T entity);
        Task DeleteAsync(int id);
    }
}
```

## Step 4: Generate IUnitOfWork Template

```csharp
// {SolutionName}.Core.Contracts/Repositories/IUnitOfWork.cs
using System;
using System.Threading.Tasks;

namespace {SolutionName}.Core.Contracts.Repositories
{
    public interface IUnitOfWork : IDisposable
    {
        Task<int> CommitAsync();
    }
}
```

## Step 5: Verify Project References

After generating, confirm that:
- [ ] `{SolutionName}.Api` references the new layer project
- [ ] `ServiceRegistryExtensions.cs` has the new registrations added
- [ ] Namespace substitution applied throughout

## Step 6: Summary

```
✅ Camada {LayerType} adicionada ao projeto {SolutionName}!

Arquivos criados:
  src/{LayerType}/{SolutionName}.{LayerType}/...

Lembre-se de:
  1. Adicionar referência do projeto no .sln do Visual Studio
  2. Registrar os serviços em ServiceRegistryExtensions.cs
```
