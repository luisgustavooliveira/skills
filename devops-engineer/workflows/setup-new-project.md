# Workflow: Setup New Project

**Objective**: Configure a new .NET Core 9+ project with full deployment in <30 minutes

**Complexity**: High  
**Estimated Duration**: 20-30 minutes  
**Prerequisites**: .NET SDK 9.0+, Git, PowerShell 7.0+, NUKE GlobalTool

---

## Overview

This workflow automates the complete configuration of a new project, including:
- ✅ Standardized directory structure
- ✅ Build system (NUKE)
- ✅ Customized corporate templates
- ✅ Secret configuration (OpenBao)
- ✅ CI/CD Pipeline (Azure DevOps)
- ✅ Automatically generated documentation

---

## Phase 1: Preparation (5 min)

### Step 1.1: Validate Prerequisites

Execute the validation script:

```powershell
cd deployment-docs/DevOpsAgent
.\scripts\validate-setup.ps1
```

**Checks Performed**:
- ✅ .NET SDK 9.0+ installed
- ✅ Git configured (`user.name` and `user.email`)
- ✅ NUKE GlobalTool available
- ✅ PowerShell 7.0+
- ✅ Access to deployment-docs (templates available)

**Actions if Failed**:
- .NET SDK missing: Download from https://dotnet.microsoft.com/download/dotnet/9.0
- Git not configured: `git config --global user.name "Your Name"`
- NUKE missing: `dotnet tool install Nuke.GlobalTool --global`

---

### Step 1.2: Collect Project Information

Prepare the following information:

| Field | Description | Example |
|-------|-------------|---------|
| **ProjectName** | Project name (PascalCase) | `OrderService` |
| **SolutionPath** | Path to .sln | `.\OrderService.sln` |
| **Namespace** | Root namespace | `SnpsGroup.OrderService` |
| **RepositoryUrl** | Git repository URL | `https://dev.azure.com/snpsgroup/OrderService` |
| **Description** | Brief description | `Order management service` |

**Naming Conventions**:
- ProjectName: PascalCase, no spaces (e.g., `OrderService`, `CustomerPortal`)
- Namespace: Prefix `SnpsGroup.` followed by ProjectName
- Avoid: Numbers at start, special characters, reserved words

---

### Step 1.3: Decide Deployment Type

Choose deployment type:

| Type | When to Use | Complexity |
|------|-------------|------------|
| **IIS (Windows)** | Legacy applications, Windows Server | Low |
| **Docker** | Microservices, portability | Medium |
| **Kubernetes** | High scale, complex orchestration | High |

> 💡 **Recommendation**: New projects should use **Docker** for flexibility

---

## Phase 2: Project Initialization (10 min)

### Step 2.1: Execute Initialization Script

```powershell
# Navigate to your project directory
cd C:\Projects\OrderService

# Execute initialization script
..\deployment-docs\DevOpsAgent\scripts\init-project.ps1 `
  -ProjectName "OrderService" `
  -SolutionPath ".\OrderService.sln" `
  -Namespace "SnpsGroup.OrderService" `
  -CreateGit $true `
  -DryRun $false
```

**Optional Parameters**:
- `-DryRun $true`: Simulates without creating files (recommended for first time)
- `-CreateGit $false`: Does not initialize Git (if already exists)
- `-TemplatesPath`: Custom path for templates

**What the Script Does**:

1. **Validates Prerequisites**
   ```
   ▶ Validating: .NET SDK 9.0+
     ✅ PASS
     Version: 9.0.100
   
   ▶ Validating: Git
     ✅ PASS
     Configured for: John Doe
   ```

2. **Creates Directory Structure**
   ```
   OrderService/
   ├── build/
   │   ├── Build.cs
   │   ├── Helpers/
   │   │   ├── OpenBaoHelper.cs
   │   │   ├── ConfigHelper.cs
   │   │   ├── DeploymentHelper.cs
   │   │   └── HealthCheckHelper.cs
   │   └── _build.csproj
   ├── config/
   │   ├── appsettings.json
   │   ├── appsettings.Development.json
   │   ├── appsettings.Staging.json
   │   └── appsettings.Production.json
   ├── deployment/
   │   ├── scripts/
   │   │   └── migrate-secrets.ps1
   │   └── backups/
   ├── .gitignore
   ├── global.json
   └── azure-pipelines.yml (template)
   ```

3. **Copies Templates and Replaces Placeholders**
   - `{ProjectName}` → `OrderService`
   - `{SolutionName}` → `OrderService`
   - `{Namespace}` → `SnpsGroup.OrderService`
   
   Processed files:
   - `build/Build.cs`
   - `build/Helpers/*.cs`
   - `config/appsettings*.json`
   - `azure-pipelines.yml`

4. **Initializes Git** (if `-CreateGit $true`)
   ```bash
   git init
   git add .
   git commit -m "Initial commit: Project structure with NUKE build system"
   ```

5. **Initializes NUKE**
   ```bash
   nuke :setup
   ```

**Expected Output**:
```
================================================================
 PROJECT INITIALIZATION COMPLETED
================================================================

✅ Directory structure created
✅ Templates copied and customized
✅ Placeholders replaced (12 occurrences)
✅ Git initialized with initial commit
✅ NUKE build system configured

Next Steps:
  1. Configure OpenBao secrets
  2. Create Azure DevOps pipeline
  3. Test local build: nuke Compile
```

---

### Step 2.2: Validate Created Structure

```powershell
# Execute complete validation
..\deployment-docs\DevOpsAgent\scripts\validate-setup.ps1 `
  -ProjectName "OrderService"
```

**Checks Performed**:
- ✅ All directories created
- ✅ Mandatory files present
- ✅ Placeholders replaced (no remaining `{...}`)
- ✅ Build.cs compiles without errors
- ✅ Git initialized

---

### Step 2.3: Test Local Build

```powershell
# Test NUKE build
nuke --help

# Available targets:
# - Clean
# - Restore
# - Compile
# - Test
# - Publish
# - FetchSecrets
# - ApplyConfiguration
# - Deploy
# - ValidateDeployment

# Execute basic build
nuke Compile
```

**Expected Output**:
```
╬══════════════════════════════════════
║ Clean
╬══════════════════════════════════════
Cleaning directory: ./artifacts
Cleaning directory: ./bin
Cleaning directory: ./obj

╬══════════════════════════════════════
║ Restore
╬══════════════════════════════════════
Restoring OrderService.sln...
  Restored 15 packages

╬══════════════════════════════════════
║ Compile
╬══════════════════════════════════════
Building OrderService.sln (Release)...
  Build succeeded.
    0 Warning(s)
    0 Error(s)

Build succeeded.
```

---

## Phase 3: Configure Secrets (OpenBao) (10 min)

### Step 3.1: Identify Needed Secrets

Create a secrets inventory for the project:

```json
// deployment/secrets-inventory.json
{
  "project": "OrderService",
  "secrets": [
    {
      "name": "database-connection-string",
      "category": "database",
      "description": "Connection string for SQL Server",
      "required": true,
      "rotation_days": 90
    },
    {
      "name": "oauth-client-id",
      "category": "authentication",
      "description": "OAuth Client ID",
      "required": true,
      "rotation_days": 180
    },
    {
      "name": "oauth-client-secret",
      "category": "authentication",
      "description": "OAuth Client Secret",
      "required": true,
      "rotation_days": 90
    },
    {
      "name": "redis-connection-string",
      "category": "cache",
      "description": "Redis connection string",
      "required": false,
      "rotation_days": 90
    },
    {
      "name": "payment-api-key",
      "category": "external-api",
      "description": "Payment gateway API key",
      "required": true,
      "rotation_days": 30
    }
  ]
}
```

---

### Step 3.2: Configure Tokens in appsettings.json

Edit `config/appsettings.json` and add tokens:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "#{database-connection-string}"
  },
  "Authentication": {
    "OAuth": {
      "ClientId": "#{oauth-client-id}",
      "ClientSecret": "#{oauth-client-secret}",
      "Authority": "https://auth.snpsgroup.com"
    }
  },
  "Redis": {
    "Configuration": "#{redis-connection-string}"
  },
  "ExternalApis": {
    "PaymentGateway": {
      "ApiKey": "#{payment-api-key}",
      "BaseUrl": "https://payments.example.com"
    }
  }
}
```

**Token Pattern**:
- Format: `#{kebab-case}`
- Conversion to env var: `SECRET_{SCREAMING_SNAKE_CASE}`
- Example: `#{database-connection-string}` → `SECRET_DATABASE_CONNECTION_STRING`

---

### Step 3.3: Execute OpenBao Configuration Workflow

> 📖 **See**: `configure-openbao.md` for full workflow

**Quick Summary**:

```powershell
# 1. Configure environment variables
$env:BAO_ADDR = "https://keyvault.snpsgroup.com:8200"
$env:BAO_NAMESPACE = "snpsgroup"
$env:BAO_TOKEN = "your-admin-token"

# 2. Create policies for each environment
bao policy write -namespace=snpsgroup orderservice-development ./deployment/policies/development.hcl
bao policy write -namespace=snpsgroup orderservice-staging ./deployment/policies/staging.hcl
bao policy write -namespace=snpsgroup orderservice-production ./deployment/policies/production.hcl

# 3. Create AppRoles
bao write -namespace=snpsgroup auth/approle/role/orderservice-development \
  token_policies="orderservice-development-policy" \
  token_ttl=1h

bao write -namespace=snpsgroup auth/approle/role/orderservice-staging \
  token_policies="orderservice-staging-policy" \
  token_ttl=1h

bao write -namespace=snpsgroup auth/approle/role/orderservice-production \
  token_policies="orderservice-production-policy" \
  token_ttl=1h

# 4. Obtain RoleID and SecretID
bao read -namespace=snpsgroup auth/approle/role/orderservice-production/role-id
bao write -namespace=snpsgroup -f auth/approle/role/orderservice-production/secret-id

# 5. Add secrets
bao kv put -namespace=snpsgroup secret/orderservice/production \
  database-connection-string="Server=prod-db;Database=Orders;..." \
  oauth-client-id="prod-client-id" \
  oauth-client-secret="prod-secret" \
  redis-connection-string="prod-redis:6379" \
  payment-api-key="prod-payment-key"
```

---

## Phase 4: Configure Azure DevOps Pipeline (5 min)

### Step 4.1: Create Variable Groups

```powershell
# Install Azure CLI DevOps extension (if necessary)
az extension add --name azure-devops

# Login
az login
az devops configure --defaults organization=https://dev.azure.com/snpsgroup project=OrderService

# Create Variable Groups for each environment
az pipelines variable-group create \
  --name "OrderService-Development-Secrets" \
  --variables \
    OpenBao.RoleId="<role-id-dev>" \
    OpenBao.SecretId="<secret-id-dev>" \
  --authorize true

az pipelines variable-group create \
  --name "OrderService-Staging-Secrets" \
  --variables \
    OpenBao.RoleId="<role-id-staging>" \
    OpenBao.SecretId="<secret-id-staging>" \
  --authorize true

az pipelines variable-group create \
  --name "OrderService-Production-Secrets" \
  --variables \
    OpenBao.RoleId="<role-id-prod>" \
    OpenBao.SecretId="<secret-id-prod>" \
  --authorize true
```

**Mark SecretId as Secret**:
- Azure DevOps UI → Pipelines → Library
- Edit each Variable Group
- Click the lock icon next to `OpenBao.SecretId`

---

### Step 4.2: Create Environments with Approvals

```powershell
# Development (no approval)
az devops invoke \
  --area distributedtask \
  --resource environments \
  --route-parameters project=OrderService \
  --http-method POST \
  --in-file - <<EOF
{
  "name": "OrderService-Development",
  "description": "Development environment"
}
EOF

# Staging (no approval)
az devops invoke \
  --area distributedtask \
  --resource environments \
  --route-parameters project=OrderService \
  --http-method POST \
  --in-file - <<EOF
{
  "name": "OrderService-Staging",
  "description": "Staging environment"
}
EOF

# Production (WITH approval - configure manually in UI)
# 1. Azure DevOps → Pipelines → Environments
# 2. Create "OrderService-Production"
# 3. Menu (⋮) → Approvals and checks
# 4. Add "Approvals"
# 5. Add approvers: Tech Lead, Product Owner
# 6. Timeout: 7 days
```

---

### Step 4.3: Create Pipeline

```powershell
# Commit azure-pipelines.yml (already created by init-project.ps1)
git add azure-pipelines.yml
git commit -m "Add Azure DevOps pipeline configuration"
git push origin main

# Create pipeline in Azure DevOps
az pipelines create \
  --name "OrderService-CI-CD" \
  --repository OrderService \
  --repository-type tfsgit \
  --branch main \
  --yml-path azure-pipelines.yml
```

---

## Phase 5: Final Validation (5 min)

### Step 5.1: Pre-Deployment Check

```powershell
# Build for Development
nuke Publish --environment Development

# Execute deploy-check
..\deployment-docs\DevOpsAgent\scripts\deploy-check.ps1 `
  -Environment "Development" `
  -ProjectName "OrderService" `
  -PublishDirectory "./publish"
```

**Expectation**: All checks should pass except "Current deployment is healthy" (first time)

---

### Step 5.2: First Deployment (Development)

```powershell
# Complete deployment
nuke Deploy --environment Development

# Or via pipeline
git push origin develop  # Automatic trigger for Development
```

**Monitor**:
```powershell
# Open health dashboard
..\deployment-docs\DevOpsAgent\scripts\health-dashboard.ps1 `
  -ProjectName "OrderService" `
  -Environment "Development"
```

---

### Step 5.3: Validate Health Check

```powershell
# Test health endpoint
curl http://localhost:5000/OrderService/health

# Expected response:
# {
#   "status": "Healthy",
#   "dependencies": {
#     "database": { "status": "Healthy" },
#     "redis": { "status": "Healthy" }
#   }
# }
```

---

## Phase 6: Documentation (5 min)

### Step 6.1: Generate DEPLOYMENT.md

The `init-project.ps1` script already created a template. Complete with specific information:

```markdown
# OrderService - Deployment Guide

## Project Information
- **Name**: OrderService
- **Namespace**: SnpsGroup.OrderService
- **Repository**: https://dev.azure.com/snpsgroup/OrderService
- **Owner**: [Your Name]
- **Created**: 2026-01-19

## Environments

### Development
- **URL**: http://localhost:5000/OrderService
- **Auto-deploy**: Yes (branch: develop)
- **OpenBao Path**: secret/orderservice/development

### Staging
- **URL**: https://staging.snpsgroup.com/OrderService
- **Auto-deploy**: Yes (branch: main)
- **OpenBao Path**: secret/orderservice/staging

### Production
- **URL**: https://www.snpsgroup.com/OrderService
- **Auto-deploy**: No (requires approval)
- **OpenBao Path**: secret/orderservice/production

## Secrets Inventory

| Secret Name | Category | Rotation Schedule |
|-------------|----------|-------------------|
| database-connection-string | Database | 90 days |
| oauth-client-id | Authentication | 180 days |
| oauth-client-secret | Authentication | 90 days |
| redis-connection-string | Cache | 90 days |
| payment-api-key | External API | 30 days |

## Build Commands

```bash
# Local development
nuke Compile
nuke Test
nuke Publish --environment Development

# Deployment
nuke Deploy --environment Development
nuke Deploy --environment Staging
nuke Deploy --environment Production
```

## Health Check

Endpoint: `/health`

## Troubleshooting

See: ../deployment-docs/DevOpsAgent/knowledge/troubleshooting.json
```

---

### Step 6.2: Commit Documentation

```bash
git add DEPLOYMENT.md deployment/secrets-inventory.json
git commit -m "docs: Add deployment documentation and secrets inventory"
git push origin main
```

---

## Completion Checklist

Mark each item upon completion:

### Structure and Build
- [ ] Directory structure created (build/, config/, deployment/)
- [ ] Templates copied and placeholders replaced
- [ ] Git initialized with initial commit
- [ ] NUKE configured (`nuke :setup`)
- [ ] Local build works (`nuke Compile`)
- [ ] Tests pass (`nuke Test`)

### Secrets (OpenBao)
- [ ] Secrets inventory created
- [ ] Tokens added in appsettings.json
- [ ] Policies created (development, staging, production)
- [ ] AppRoles created for each environment
- [ ] RoleID and SecretID obtained
- [ ] Secrets added to OpenBao

### CI/CD (Azure DevOps)
- [ ] Variable Groups created (3 environments)
- [ ] SecretIds marked as secret
- [ ] Environments created (3 environments)
- [ ] Approvals configured (Production)
- [ ] Pipeline created and working
- [ ] Trigger configured (develop → Dev, main → Staging/Prod)

### Deployment
- [ ] Pre-deployment check passes
- [ ] First deployment successful (Development)
- [ ] Health check responding
- [ ] Monitoring dashboard works
- [ ] Rollback tested

### Documentation
- [ ] DEPLOYMENT.md complete
- [ ] secrets-inventory.json updated
- [ ] Project README.md updated
- [ ] Troubleshooting runbook created

---

## Troubleshooting

### Problem: "Template not found"
**Cause**: Script cannot find `deployment-docs`  
**Fix**: 
```powershell
# Verify relative path
ls ..\deployment-docs\DevOpsAgent

# Or specify absolute path
.\init-project.ps1 -TemplatesPath "C:\Path\To\deployment-docs"
```

---

### Problem: "Placeholder not replaced"
**Cause**: Script did not replace all `{ProjectName}`  
**Fix**:
```powershell
# Search remaining placeholders
grep -r "{ProjectName}" .

# Re-execute substitution
.\init-project.ps1 -ProjectName "OrderService" -Force
```

---

### Problem: "OpenBao authentication failed"
**Cause**: Incorrect RoleID or SecretID  
**Fix**: See `configure-openbao.md` → Troubleshooting Section

---

### Problem: "Pipeline not triggering"
**Cause**: Branch trigger not configured  
**Fix**:
1. Azure DevOps → Pipelines → Edit
2. Triggers → Enable continuous integration
3. Branch filters: `develop`, `main`

---

## Support Scripts

### Clean and Restart

```powershell
# If need to start from scratch
git clean -fdx  # Remove all untracked files
rm -rf build/ config/ deployment/  # Remove created structure

# Re-execute init-project.ps1
```

---

### Quick Validation

```bash
# One-liner to validate everything
.\validate-setup.ps1 && nuke Compile && nuke Test
```

---

## Next Steps

After completing this workflow:

1. **Configure Monitoring**
   - Application Insights
   - Log aggregation
   - Custom alerts

2. **Configure Automated Tests**
   - Unit tests
   - Integration tests
   - E2E tests

3. **Configure Scaling** (if Docker/Kubernetes)
   - HPA (Horizontal Pod Autoscaler)
   - Resource limits
   - Health probes

4. **Configure Backup and DR**
   - Database backups
   - Disaster recovery plan
   - Defined RTO/RPO

---

## Total Estimated Time

| Phase | Duration |
|-------|----------|
| 1. Preparation | 5 min |
| 2. Initialization | 10 min |
| 3. OpenBao | 10 min |
| 4. Azure DevOps | 5 min |
| 5. Validation | 5 min |
| 6. Documentation | 5 min |
| **TOTAL** | **40 min** |

> With practice and automation, can be reduced to **20-25 minutes**.

---

## Support

**Questions**: #devops on Teams  
**Incidents**: Azure DevOps Boards (tag: `deployment`)  
**Skill Documentation**: ../SKILL.md

---

**✅ Setup complete! Your project is ready for continuous deployment.**
