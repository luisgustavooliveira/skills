# .NET Framework 4.8 API — Framework Reference

Complete reference for scaffolding a modern .NET Framework 4.8 Web API project.

---

## Solution Structure

```
{SolutionName}/
├── src/
│   ├── Api/
│   │   └── {SolutionName}.Api/
│   ├── Core/
│   │   ├── {SolutionName}.Core/
│   │   └── {SolutionName}.Core.Contracts/
│   └── Infrastructure/
│       └── {SolutionName}.Infrastructure/
└── tests/
    └── {SolutionName}.Tests/
```

---

## NuGet Packages (YourApp.Api.csproj)

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net48</TargetFramework>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.AspNet.WebApi.Owin" Version="5.3.0" />
    <PackageReference Include="Microsoft.Owin.Host.SystemWeb" Version="4.2.2" />
    <PackageReference Include="Microsoft.Owin.Cors" Version="4.2.2" />
    <PackageReference Include="Lamar" Version="12.1.0" />
    <PackageReference Include="Lamar.Microsoft.DependencyInjection" Version="12.1.0" />
    <PackageReference Include="Microsoft.Bcl.Async" Version="1.0.168" />
    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
    <PackageReference Include="Serilog" Version="3.1.1" />
    <PackageReference Include="Serilog.Sinks.Console" Version="5.0.1" />
    <PackageReference Include="Serilog.Sinks.File" Version="5.0.0" />
    <PackageReference Include="Serilog.Extensions.Logging" Version="8.0.0" />
    <PackageReference Include="Swashbuckle.Core" Version="5.6.0" />
    <PackageReference Include="Polly" Version="7.2.4" />
  </ItemGroup>

  <ItemGroup>
    <Reference Include="System.Net.Http" />
    <Reference Include="System.Web" />
  </ItemGroup>
</Project>
```

---

## Key Files and Locations

| File | Path |
|------|------|
| OWIN Startup | `{App}.Api/Startup.cs` |
| Lamar DI Resolver | `{App}.Api/Infrastructure/DependencyInjection/LamarDependencyResolver.cs` |
| Service Registry Extensions | `{App}.Api/Infrastructure/DependencyInjection/ServiceRegistryExtensions.cs` |
| Global Exception Filter | `{App}.Api/Infrastructure/Filters/GlobalExceptionFilterAttribute.cs` |
| Model Validation Filter | `{App}.Api/Infrastructure/Filters/ValidateModelAttribute.cs` |
| Global Exception Handler | `{App}.Api/Infrastructure/GlobalExceptionHandler.cs` |
| Base Controller | `{App}.Api/Controllers/BaseApiController.cs` |
| Web.config | `{App}.Api/Web.config` |

---

## Startup.cs Template

```csharp
[assembly: OwinStartup(typeof({App}.Api.Startup))]

namespace {App}.Api
{
    public class Startup
    {
        public void Configuration(IAppBuilder app)
        {
            ConfigureLogging();
            var config = new HttpConfiguration();
            var container = ConfigureDependencyInjection(config);
            ConfigureRoutes(config);
            ConfigureFormatters(config);
            ConfigureFilters(config);
            ConfigureSwagger(config);
            app.UseCors(CorsOptions.AllowAll);
            app.UseWebApi(config);
            Log.Information("API iniciada com sucesso");
        }

        private void ConfigureLogging()
        {
            Log.Logger = new LoggerConfiguration()
                .MinimumLevel.Information()
                .WriteTo.Console()
                .WriteTo.File(path: "logs/api-.log", rollingInterval: RollingInterval.Day, retainedFileCountLimit: 30)
                .Enrich.FromLogContext()
                .Enrich.WithProperty("Application", "{App}.Api")
                .CreateLogger();
        }

        private Container ConfigureDependencyInjection(HttpConfiguration config)
        {
            var container = new Container(services =>
            {
                services.AddApplicationServices();
                services.AddInfrastructureServices();
                services.Scan(scanner =>
                {
                    scanner.AssemblyContainingType<Startup>();
                    scanner.AddAllTypesOf<ApiController>();
                    scanner.WithDefaultConventions();
                });
            });
            config.DependencyResolver = new LamarDependencyResolver(container);
            return container;
        }

        private void ConfigureRoutes(HttpConfiguration config)
        {
            config.MapHttpAttributeRoutes();
            config.Routes.MapHttpRoute(
                name: "DefaultApi",
                routeTemplate: "api/{controller}/{id}",
                defaults: new { id = RouteParameter.Optional });
        }

        private void ConfigureFormatters(HttpConfiguration config)
        {
            config.Formatters.Remove(config.Formatters.XmlFormatter);
            config.Formatters.JsonFormatter.SerializerSettings = new JsonSerializerSettings
            {
                ContractResolver = new CamelCasePropertyNamesContractResolver(),
                NullValueHandling = NullValueHandling.Ignore,
                DateTimeZoneHandling = DateTimeZoneHandling.Utc,
                Formatting = Formatting.Indented,
                ReferenceLoopHandling = ReferenceLoopHandling.Ignore
            };
        }

        private void ConfigureFilters(HttpConfiguration config)
        {
            config.Filters.Add(new GlobalExceptionFilterAttribute());
            config.Filters.Add(new ValidateModelAttribute());
            config.Services.Replace(typeof(IExceptionHandler), new GlobalExceptionHandler());
        }

        private void ConfigureSwagger(HttpConfiguration config)
        {
            config.EnableSwagger(c =>
            {
                c.SingleApiVersion("v1", "{App} API")
                    .Description("API {App}")
                    .Contact(cc => cc.Name("Sua Empresa").Email("contato@empresa.com"));
                c.IncludeXmlComments(System.IO.Path.Combine(
                    AppDomain.CurrentDomain.BaseDirectory, "bin",
                    typeof(Startup).Assembly.GetName().Name + ".xml"));
                c.DescribeAllEnumsAsStrings();
                c.UseFullTypeNameInSchemaIds();
            })
            .EnableSwaggerUi(c =>
            {
                c.DocumentTitle("{App} API Documentation");
                c.DocExpansion(DocExpansion.List);
            });
        }
    }
}
```

---

## LamarDependencyResolver.cs Template

```csharp
public class LamarDependencyResolver : IDependencyResolver
{
    private readonly IContainer _container;
    public LamarDependencyResolver(IContainer container) =>
        _container = container ?? throw new ArgumentNullException(nameof(container));

    public IDependencyScope BeginScope() =>
        new LamarDependencyScope(_container.GetNestedContainer());

    public object GetService(Type serviceType)
    {
        try { return _container.TryGetInstance(serviceType); } catch { return null; }
    }

    public IEnumerable<object> GetServices(Type serviceType) =>
        _container.GetAllInstances(serviceType).Cast<object>();

    public void Dispose() => _container?.Dispose();
}

public class LamarDependencyScope : IDependencyScope
{
    private readonly INestedContainer _nestedContainer;
    public LamarDependencyScope(INestedContainer nestedContainer) =>
        _nestedContainer = nestedContainer ?? throw new ArgumentNullException(nameof(nestedContainer));

    public object GetService(Type serviceType)
    {
        try { return _nestedContainer.TryGetInstance(serviceType); } catch { return null; }
    }

    public IEnumerable<object> GetServices(Type serviceType) =>
        _nestedContainer.GetAllInstances(serviceType).Cast<object>();

    public void Dispose() => _nestedContainer?.Dispose();
}
```

---

## ServiceRegistryExtensions.cs Template

```csharp
public static class ServiceRegistryExtensions
{
    public static void AddApplicationServices(this ServiceRegistry services)
    {
        services.For<IExampleService>().Use<ExampleService>().Scoped();
        services.Scan(scanner =>
        {
            scanner.AssemblyContainingType<IExampleService>();
            scanner.WithDefaultConventions();
            scanner.LookForRegistries();
        });
    }

    public static void AddInfrastructureServices(this ServiceRegistry services)
    {
        services.For(typeof(IRepository<>)).Use(typeof(Repository<>)).Scoped();
        services.For<ICrystalReportService>().Use<CrystalReportService>().Scoped();
        services.For<IUnitOfWork>().Use<UnitOfWork>().Scoped();
        services.For<IAppSettings>().Use<AppSettings>().Singleton();
    }
}
```

---

## GlobalExceptionFilterAttribute.cs Template

```csharp
public class GlobalExceptionFilterAttribute : ExceptionFilterAttribute
{
    public override void OnException(HttpActionExecutedContext context)
    {
        Log.Error(context.Exception,
            "Erro não tratado em {Controller}.{Action}",
            context.ActionContext.ControllerContext.ControllerDescriptor.ControllerName,
            context.ActionContext.ActionDescriptor.ActionName);

        var response = new
        {
            Message = "Ocorreu um erro ao processar sua solicitação",
            Error = context.Exception.Message,
#if DEBUG
            StackTrace = context.Exception.StackTrace
#endif
        };

        context.Response = context.Request.CreateResponse(
            HttpStatusCode.InternalServerError, response);
    }
}
```

---

## ValidateModelAttribute.cs Template

```csharp
public class ValidateModelAttribute : ActionFilterAttribute
{
    public override void OnActionExecuting(HttpActionContext actionContext)
    {
        if (!actionContext.ModelState.IsValid)
        {
            var errors = actionContext.ModelState
                .Where(e => e.Value.Errors.Count > 0)
                .Select(e => new
                {
                    Field = e.Key,
                    Errors = e.Value.Errors.Select(x => x.ErrorMessage).ToArray()
                }).ToArray();

            actionContext.Response = actionContext.Request.CreateResponse(
                HttpStatusCode.BadRequest,
                new { Message = "Dados inválidos", ValidationErrors = errors });
        }
    }
}
```

---

## GlobalExceptionHandler.cs Template

```csharp
public class GlobalExceptionHandler : ExceptionHandler
{
    public override void Handle(ExceptionHandlerContext context)
    {
        Log.Error(context.Exception, "Erro não tratado na API");
        context.Result = new ResponseMessageResult(
            context.Request.CreateResponse(
                HttpStatusCode.InternalServerError,
                new { Message = "Erro interno do servidor", Error = context.Exception.Message }));
    }
}
```

---

## BaseApiController.cs Template

```csharp
public abstract class BaseApiController : ApiController
{
    protected IHttpActionResult Ok<T>(T data, string message = null) =>
        Ok(new ApiResponse<T> { Success = true, Data = data, Message = message });

    protected IHttpActionResult Created<T>(T data, string message = null) =>
        Content(HttpStatusCode.Created, new ApiResponse<T> { Success = true, Data = data, Message = message });

    protected new IHttpActionResult BadRequest(string message) =>
        Content(HttpStatusCode.BadRequest, new ApiResponse { Success = false, Message = message });

    protected IHttpActionResult NotFound(string message = "Recurso não encontrado") =>
        Content(HttpStatusCode.NotFound, new ApiResponse { Success = false, Message = message });

    protected async Task<IHttpActionResult> ExecuteAsync<T>(Func<Task<T>> action, string successMessage = null)
    {
        try
        {
            var result = await action();
            return Ok(result, successMessage);
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Erro ao executar ação");
            return InternalServerError(ex);
        }
    }
}

public class ApiResponse
{
    public bool Success { get; set; }
    public string Message { get; set; }
}

public class ApiResponse<T> : ApiResponse
{
    public T Data { get; set; }
}
```

---

## Example Controller Template

```csharp
[RoutePrefix("api/example")]
public class ExampleController : BaseApiController
{
    private readonly IExampleService _exampleService;

    public ExampleController(IExampleService exampleService) =>
        _exampleService = exampleService;

    [HttpGet, Route("")]
    public async Task<IHttpActionResult> GetAll() =>
        await ExecuteAsync(async () => await _exampleService.GetAllAsync(), "Itens recuperados com sucesso");

    [HttpGet, Route("{id:int}")]
    public async Task<IHttpActionResult> GetById(int id)
    {
        var item = await _exampleService.GetByIdAsync(id);
        if (item == null) return NotFound($"Item com ID {id} não encontrado");
        return Ok(item);
    }

    [HttpPost, Route("")]
    public async Task<IHttpActionResult> Create([FromBody] ExampleDto dto) =>
        await ExecuteAsync(async () => await _exampleService.CreateAsync(dto), "Item criado com sucesso");
}
```

---

## Web.config Template

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <appSettings>
    <add key="owin:AutomaticAppStartup" value="true" />
  </appSettings>
  <system.web>
    <compilation debug="true" targetFramework="4.8" />
    <httpRuntime targetFramework="4.8" />
  </system.web>
  <system.webServer>
    <handlers>
      <remove name="ExtensionlessUrlHandler-Integrated-4.0" />
      <remove name="OPTIONSVerbHandler" />
      <remove name="TRACEVerbHandler" />
      <add name="ExtensionlessUrlHandler-Integrated-4.0"
           path="*." verb="*"
           type="System.Web.Handlers.TransferRequestHandler"
           preCondition="integratedMode,runtimeVersionv4.0" />
    </handlers>
  </system.webServer>
  <runtime>
    <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
      <dependentAssembly>
        <assemblyIdentity name="Newtonsoft.Json" publicKeyToken="30ad4fe6b2a6aeed" />
        <bindingRedirect oldVersion="0.0.0.0-13.0.0.0" newVersion="13.0.0.0" />
      </dependentAssembly>
    </assemblyBinding>
  </runtime>
</configuration>
```

---

## Design Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| DI Container | Lamar | Modern, fast, StructureMap successor |
| Hosting | OWIN | Decoupled from IIS, enables self-hosting |
| Serializer | Newtonsoft.Json | Standard for .NET Framework |
| Logging | Serilog | Structured logging with sinks |
| Docs | Swashbuckle 5 | Swagger 2.0 compatible with WebAPI |
| Resilience | Polly | Industry standard retry/circuit-breaker |
| XML Formatter | Removed | JSON-only API |
| Async | async/await | Modern patterns even on net48 |
