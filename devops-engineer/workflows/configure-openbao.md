# Workflow: Configure OpenBao (HashiCorp Vault Fork)

**Objective**: Configure secure secret management using OpenBao for all environments

**Complexity**: High  
**Estimated Duration**: 15-20 minutes  7. Prerequisites: OpenBao CLI installed, Admin Token, Project initialized

---

## Overview

This workflow configures the complete secret infrastructure in OpenBao:
- ✅ Policies (permissions per environment)
- ✅ AppRoles (authentication for CI/CD)
- ✅ Secrets organized by environment
- ✅ Integration with Azure DevOps
- ✅ Audit and rotation configured

---

## Secret Architecture

```
OpenBao
└── secret/                           # KV v2 secrets engine
    └── {project}/                    # Ex: orderservice
        ├── development/              # Development secrets
        │   ├── database-connection-string
        │   ├── oauth-client-id
        │   └── oauth-client-secret
        ├── staging/                  # Staging secrets
        │   ├── database-connection-string
        │   ├── oauth-client-id
        │   └── oauth-client-secret
        ├── production/               # Production secrets
        │   ├── database-connection-string
        │   ├── oauth-client-id
        │   └── oauth-client-secret
        └── shared/                   # Shared secrets
            └── api-base-url
```

---

## Phase 1: Preparation (5 min)

### Step 1.1: Install Vault CLI

**Windows**:
```powershell
# Via Chocolatey
choco install openbao

# Or download manually
# https://github.com/openbao/openbao/releases
```

**Linux**:
```bash
# Ubuntu/Debian
wget https://github.com/openbao/openbao/releases/download/v2.0.0/openbao_2.0.0_linux_amd64.zip
unzip openbao_2.0.0_linux_amd64.zip
sudo mv bao /usr/local/bin/bao
sudo chmod +x /usr/local/bin/bao
```

**Validate Installation**:
```bash
bao version
# OpenBao v2.0.0
```

---

### Step 1.2: Configure Environment Variables

```powershell
# Windows PowerShell
$env:BAO_ADDR = "https://keyvault.snpsgroup.com:8200"
$env:BAO_NAMESPACE = "snpsgroup"
$env:BAO_TOKEN = "your-admin-token-here"

# Check connectivity
bao status -namespace=snpsgroup
```

**Expected Output**:
```
Key             Value
---             -----
Seal Type       shamir
Initialized     true
Sealed          false
Total Shares    5
Threshold       3
Version         2.0.0
```

---

### Step 1.3: Create Secret Inventory

Create `deployment/secrets-inventory.json`:

```json
{
  "project": "orderservice",
  "version": "1.0",
  "secrets": {
    "database": [
      {
        "name": "database-connection-string",
        "description": "SQL Server connection string",
        "required": true,
        "environments": ["development", "staging", "production"],
        "rotation_days": 90,
        "format": "Server={server};Database={db};User Id={user};Password={password};",
        "sample": "Server=localhost;Database=OrdersDB;User Id=app_user;Password=***;"
      }
    ],
    "authentication": [
      {
        "name": "oauth-client-id",
        "description": "OAuth 2.0 Client ID",
        "required": true,
        "environments": ["development", "staging", "production"],
        "rotation_days": 180,
        "format": "UUID",
        "sample": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      },
      {
        "name": "oauth-client-secret",
        "description": "OAuth 2.0 Client Secret",
        "required": true,
        "environments": ["development", "staging", "production"],
        "rotation_days": 90,
        "format": "Base64 string",
        "sample": "ABC123xyz789***"
      }
    ],
    "cache": [
      {
        "name": "redis-connection-string",
        "description": "Redis connection string",
        "required": false,
        "environments": ["development", "staging", "production"],
        "rotation_days": 90,
        "format": "{host}:{port},password={password}",
        "sample": "localhost:6379,password=***"
      }
    ],
    "external-apis": [
      {
        "name": "payment-api-key",
        "description": "Payment gateway API key",
        "required": true,
        "environments": ["staging", "production"],
        "rotation_days": 30,
        "format": "API key string",
        "sample": "sk_live_***"
      }
    ]
  }
}
```

---

## Phase 2: Create Policies (5 min)

### Step 2.1: Create Policy for Development

Create `deployment/policies/development.hcl`:

```hcl
# Policy: orderservice-development-policy
# Allows reading development and shared secrets

# Specific development secrets
path "secret/data/orderservice/development/*" {
  capabilities = ["read", "list"]
}

# Shared secrets
path "secret/data/orderservice/shared/*" {
  capabilities = ["read", "list"]
}

# Metadata (to check versions)
path "secret/metadata/orderservice/development/*" {
  capabilities = ["list", "read"]
}

path "secret/metadata/orderservice/shared/*" {
  capabilities = ["list", "read"]
}

# Token renewal
path "auth/token/renew-self" {
  capabilities = ["update"]
}
```

---

### Step 2.2: Create Policy for Staging

Create `deployment/policies/staging.hcl`:

```hcl
# Policy: orderservice-staging-policy
# Allows reading staging and shared secrets

path "secret/data/orderservice/staging/*" {
  capabilities = ["read", "list"]
}

path "secret/data/orderservice/shared/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/orderservice/staging/*" {
  capabilities = ["list", "read"]
}

path "secret/metadata/orderservice/shared/*" {
  capabilities = ["list", "read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
```

---

### Step 2.3: Create Policy for Production

Create `deployment/policies/production.hcl`:

```hcl
# Policy: orderservice-production-policy
# Allows ONLY reading production and shared secrets
# MORE RESTRICTIVE - no list in metadata

path "secret/data/orderservice/production/*" {
  capabilities = ["read"]
}

path "secret/data/orderservice/shared/*" {
  capabilities = ["read"]
}

# Additional audit for production
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Mandatory logging
path "sys/audit" {
  capabilities = ["read"]
}
```

---

### Step 2.4: Apply Policies in OpenBao

```bash
# Development
bao policy write -namespace=snpsgroup orderservice-development-policy ./deployment/policies/development.hcl

# Staging
bao policy write -namespace=snpsgroup orderservice-staging-policy ./deployment/policies/staging.hcl

# Production
bao policy write -namespace=snpsgroup orderservice-production-policy ./deployment/policies/production.hcl

# List created policies
bao policy list -namespace=snpsgroup | grep orderservice
```

**Expected Output**:
```
orderservice-development-policy
orderservice-production-policy
orderservice-staging-policy
```

---

## Phase 3: Create AppRoles (5 min)

### Step 3.1: Enable AppRole Auth Method (if necessary)

```bash
# Check if AppRole is already enabled
bao auth list -namespace=snpsgroup

# If not, enable
bao auth enable -namespace=snpsgroup approle
```

---

### Step 3.2: Create AppRole for Development

```bash
bao write -namespace=snpsgroup auth/approle/role/orderservice-development \
  token_policies="orderservice-development-policy" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_ttl=0 \
  secret_id_num_uses=0 \
  bind_secret_id=true
```

**Explained Parameters**:
- `token_policies`: Associated Policy
- `token_ttl=1h`: Token expires in 1 hour
- `token_max_ttl=4h`: Max renewal time
- `secret_id_ttl=0`: SecretID never expires (ideal for CI/CD)
- `secret_id_num_uses=0`: SecretID can be used infinitely
- `bind_secret_id=true`: Requires SecretID (more secure)

---

### Step 3.3: Create AppRole for Staging

```bash
bao write -namespace=snpsgroup auth/approle/role/orderservice-staging \
  token_policies="orderservice-staging-policy" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_ttl=0 \
  secret_id_num_uses=0 \
  bind_secret_id=true
```

---

### Step 3.4: Create AppRole for Production

```bash
bao write -namespace=snpsgroup auth/approle/role/orderservice-production \
  token_policies="orderservice-production-policy" \
  token_ttl=30m \
  token_max_ttl=2h \
  secret_id_ttl=0 \
  secret_id_num_uses=0 \
  bind_secret_id=true
```

> 💡 **Note**: Production uses shorter TTL (30min) for security

---

### Step 3.5: Get RoleID and SecretID

```bash
# === DEVELOPMENT ===
# RoleID (fixed, can be public)
bao read -namespace=snpsgroup auth/approle/role/orderservice-development/role-id

# Output:
# Key        Value
# role_id    a1b2c3d4-e5f6-7890-abcd-ef1234567890

# SecretID (SECRET, keep safe)
bao write -namespace=snpsgroup -f auth/approle/role/orderservice-development/secret-id

# Output:
# Key                   Value
# secret_id             xyz789abc123-def456-ghi789
# secret_id_accessor    accessor-id-here
# secret_id_ttl         0s


# === STAGING ===
bao read -namespace=snpsgroup auth/approle/role/orderservice-staging/role-id
bao write -namespace=snpsgroup -f auth/approle/role/orderservice-staging/secret-id


# === PRODUCTION ===
bao read -namespace=snpsgroup auth/approle/role/orderservice-production/role-id
bao write -namespace=snpsgroup -f auth/approle/role/orderservice-production/secret-id
```

**🔒 IMPORTANT**: Store SecretIDs in a secure location (e.g., Azure Key Vault) before adding to Azure DevOps

---

## Phase 4: Add Secrets (5 min)

### Step 4.1: Add Development Secrets

```bash
bao kv put -namespace=snpsgroup secret/orderservice/development \
  database-connection-string="Server=dev-sql.snpsgroup.com;Database=OrdersDB_Dev;User Id=dev_user;Password=DevPass123!;" \
  oauth-client-id="dev-client-a1b2c3d4" \
  oauth-client-secret="dev-secret-xyz789" \
  redis-connection-string="dev-redis.snpsgroup.com:6379,password=DevRedis123!" \
  payment-api-key="sk_test_dev123456789"
```

---

### Step 4.2: Add Staging Secrets

```bash
bao kv put -namespace=snpsgroup secret/orderservice/staging \
  database-connection-string="Server=stg-sql.snpsgroup.com;Database=OrdersDB_Stg;User Id=stg_user;Password=StgPass456!;" \
  oauth-client-id="stg-client-e5f6g7h8" \
  oauth-client-secret="stg-secret-abc123" \
  redis-connection-string="stg-redis.snpsgroup.com:6379,password=StgRedis456!" \
  payment-api-key="sk_test_stg987654321"
```

---

### Step 4.3: Add Production Secrets

```bash
bao kv put -namespace=snpsgroup secret/orderservice/production \
  database-connection-string="Server=prod-sql.snpsgroup.com;Database=OrdersDB_Prod;User Id=prod_user;Password=$(pwgen -s 32 1);" \
  oauth-client-id="prod-client-i9j0k1l2" \
  oauth-client-secret="$(openssl rand -base64 32)" \
  redis-connection-string="prod-redis.snpsgroup.com:6379,password=$(pwgen -s 32 1)" \
  payment-api-key="sk_live_REAL_API_KEY_HERE"
```

> 💡 **Tip**: Use strong password generators for production (`pwgen`, `openssl rand`)

---

### Step 4.4: Add Shared Secrets

```bash
bao kv put -namespace=snpsgroup secret/orderservice/shared \
  api-base-url="https://api.snpsgroup.com" \
  cdn-url="https://cdn.snpsgroup.com" \
  support-email="support@snpsgroup.com"
```

---

### Step 4.5: Validate Added Secrets

```bash
# List secrets (does not show values)
bao kv list -namespace=snpsgroup secret/orderservice/development
bao kv list -namespace=snpsgroup secret/orderservice/staging
bao kv list -namespace=snpsgroup secret/orderservice/production
bao kv list -namespace=snpsgroup secret/orderservice/shared

# Read specific secret (shows values - CAREFUL!)
bao kv get -namespace=snpsgroup secret/orderservice/development

# Read only one field
bao kv get -namespace=snpsgroup -field=database-connection-string secret/orderservice/development
```

---

## Phase 5: Azure DevOps Integration (5 min)

### Step 5.1: Create Variable Groups

```powershell
# Ensure Azure CLI is logged in
az login
az devops configure --defaults organization=https://dev.azure.com/snpsgroup project=OrderService

# === Development ===
az pipelines variable-group create `
  --name "OrderService-Development-Secrets" `
  --variables `
    OpenBao.Url="https://keyvault.snpsgroup.com:8200" `
    OpenBao.RoleId="<role-id-development>" `
    OpenBao.SecretId="<secret-id-development>" `
  --authorize true

# === Staging ===
az pipelines variable-group create `
  --name "OrderService-Staging-Secrets" `
  --variables `
    OpenBao.Url="https://keyvault.snpsgroup.com:8200" `
    OpenBao.RoleId="<role-id-staging>" `
    OpenBao.SecretId="<secret-id-staging>" `
  --authorize true

# === Production ===
az pipelines variable-group create `
  --name "OrderService-Production-Secrets" `
  --variables `
    OpenBao.Url="https://keyvault.snpsgroup.com:8200" `
    OpenBao.RoleId="<role-id-production>" `
    OpenBao.SecretId="<secret-id-production>" `
  --authorize true
```

---

### Step 5.2: Mark SecretId as Secret

**Via Azure DevOps UI**:
1. Pipelines → Library → Variable Groups
2. Select each group (Development, Staging, Production)
3. Edit
4. Click the **lock** icon 🔒 next to `OpenBao.SecretId`
5. Save

**Or via Azure CLI** (requires API call):
```powershell
# Example for Development
$groupId = (az pipelines variable-group list --query "[?name=='OrderService-Development-Secrets'].id" -o tsv)

az devops invoke `
  --area distributedtask `
  --resource variablegroups `
  --route-parameters project=OrderService groupId=$groupId `
  --http-method PUT `
  --in-file - <<EOF
{
  "variables": {
    "OpenBao.SecretId": {
      "value": "<secret-id>",
      "isSecret": true
    }
  }
}
EOF
```

---

### Step 5.3: Test Authentication

Create file `test-bao-auth.ps1`:

```powershell
param(
    [string]$Environment = "development"
)

$roleName = "orderservice-$($Environment.ToLower())"

# Get credentials from Variable Group (local simulation)
$roleId = Read-Host "RoleID"
$secretId = Read-Host "SecretID" -AsSecureString
$secretIdPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secretId)
)

# Authenticate
$env:BAO_ADDR = "https://keyvault.snpsgroup.com:8200"
$env:BAO_NAMESPACE = "snpsgroup"
$authResponse = bao write -namespace=snpsgroup auth/approle/login "role_id=$roleId" "secret_id=$secretIdPlain" -format=json | ConvertFrom-Json

if ($null -ne $authResponse.auth.client_token) {
    Write-Host "✅ Authentication successful!" -ForegroundColor Green
    Write-Host "Token: $($authResponse.auth.client_token.Substring(0, 10))..." -ForegroundColor Gray
    
    # Test secret reading
    $env:BAO_TOKEN = $authResponse.auth.client_token
    $secret = bao kv get -namespace=snpsgroup -format=json "secret/orderservice/$Environment" | ConvertFrom-Json
    
    Write-Host "✅ Secret read successful!" -ForegroundColor Green
    Write-Host "Available keys: $($secret.data.data.Keys -join ', ')" -ForegroundColor Gray
} else {
    Write-Host "❌ Authentication failed!" -ForegroundColor Red
    exit 1
}
```

Execute:
```powershell
.\test-bao-auth.ps1 -Environment "development"
```

---

## Phase 6: Documentation (5 min)

### Step 6.1: Update secrets-inventory.json

Add metadata:

```json
{
  "project": "orderservice",
  "version": "1.0",
  "openbao": {
    "url": "https://keyvault.snpsgroup.com:8200",
    "base_path": "secret/orderservice",
    "policies": [
      "orderservice-development-policy",
      "orderservice-staging-policy",
      "orderservice-production-policy"
    ],
    "approles": [
      "orderservice-development",
      "orderservice-staging",
      "orderservice-production"
    ]
  },
  "rotation_schedule": {
    "database-connection-string": "90 days",
    "oauth-client-secret": "90 days",
    "payment-api-key": "30 days"
  },
  "last_rotation": {
    "database-connection-string": "2026-01-19",
    "oauth-client-secret": "2026-01-19",
    "payment-api-key": "2026-01-19"
  },
  "secrets": { /* ... your previous inventory ... */ }
}
```

---

### Step 6.2: Create Rotation Runbook

Create `deployment/SECRET_ROTATION.md`:

```markdown
# Secret Rotation Procedures

## Schedule

| Secret | Rotation Frequency | Last Rotated | Next Rotation |
|--------|-------------------|--------------|---------------|
| database-connection-string | 90 days | 2026-01-19 | 2026-04-19 |
| oauth-client-secret | 90 days | 2026-01-19 | 2026-04-19 |
| payment-api-key | 30 days | 2026-01-19 | 2026-02-18 |

## Rotation Process

### Automated (Recommended)
```bash
../deployment-docs/DevOpsAgent/scripts/secret-rotator.ps1 \
  -ProjectName "OrderService" \
  -Environment "Production" \
  -RotateType "AppRoleSecretID"
```

### Manual
1. Generate new SecretID: `bao write -namespace=snpsgroup -f auth/approle/role/orderservice-production/secret-id`
2. Update Azure DevOps Variable Group
3. Test authentication
4. Update rotation history

## Emergency Rotation

If credentials compromised:
1. Immediately rotate all secrets
2. Revoke old SecretID: `bao write -namespace=snpsgroup auth/approle/role/{role}/secret-id-accessor/destroy secret_id_accessor={accessor}`
3. Update pipelines
4. Create incident report
```

---

## Completion Checklist

- [ ] Vault CLI installed and configured
- [ ] Connectivity with OpenBao validated
- [ ] Secret inventory created (`secrets-inventory.json`)
- [ ] Policies created (development, staging, production)
- [ ] AppRoles created for the 3 environments
- [ ] RoleIDs obtained and documented
- [ ] SecretIDs generated and stored securely
- [ ] Secrets added to all environments
- [ ] Shared secrets added
- [ ] Variable Groups created in Azure DevOps
- [ ] SecretIds marked as secret in UI
- [ ] Authentication tested in all environments
- [ ] Secret reading tested
- [ ] Documentation updated
- [ ] Rotation runbook created

---

## Troubleshooting

### Problem: "permission denied"

**Symptoms**:
```
Error making API request.
Code: 403. Errors:
* permission denied
```

**Diagnosis**:
```bash
# Check policy
bao policy read -namespace=snpsgroup orderservice-development-policy

# Check AppRole
bao read -namespace=snpsgroup auth/approle/role/orderservice-development

# Check current token
bao token lookup -namespace=snpsgroup
```

**Fix**:
1. Check if policy was created correctly
2. Check if AppRole is associated with the right policy
3. Check if token has admin permissions

---

### Problem: "authentication failed"

**Symptoms**:
```
Error authenticating with AppRole
Code: 400. Errors:
* invalid role_id or secret_id
```

**Diagnosis**:
```bash
# Check RoleID
bao read -namespace=snpsgroup auth/approle/role/orderservice-development/role-id

# List SecretID accessors
bao list -namespace=snpsgroup auth/approle/role/orderservice-development/secret-id
```

**Fix**:
1. Regenerate SecretID: `bao write -namespace=snpsgroup -f auth/approle/role/{role}/secret-id`
2. Update Variable Group in Azure DevOps
3. Test authentication again

---

### Problem: "secret not found"

**Symptoms**:
```
No value found at secret/orderservice/development
```

**Diagnosis**:
```bash
# List secrets
bao kv list -namespace=snpsgroup secret/orderservice

# Check if KV v2 is enabled
bao secrets list -namespace=snpsgroup
```

**Fix**:
```bash
# Add secret
bao kv put -namespace=snpsgroup secret/orderservice/development key=value

# Or enable KV v2 if necessary
bao secrets enable -namespace=snpsgroup -path=secret -version=2 kv
```

---

### Problem: "token expired"

**Symptoms**:
```
Error making API request.
Code: 403. Errors:
* permission denied (token expired)
```

**Fix**:
```bash
# Re-authenticate with admin token
$env:BAO_TOKEN = "new-admin-token"

# Or use AppRole
bao write -namespace=snpsgroup auth/approle/login role_id={role_id} secret_id={secret_id}
```

---

## Security - Best Practices

### ✅ ALWAYS DO

1. **SecretID never in code**
   - Store in Azure Key Vault or Variable Groups
   - Never commit to Git

2. **Principle of Least Privilege**
   - Policies with minimum necessary permissions
   - Production more restrictive than Development

3. **Regular Rotation**
   - Development: 90 days
   - Staging: 60 days
   - Production: 30 days

4. **Auditing**
   - Enable audit logging in OpenBao
   - Review logs monthly

5. **Environment Separation**
   - Different paths for each environment
   - Different AppRoles
   - Independent policies

### ❌ NEVER DO

1. **Share SecretIDs between environments**
2. **Use TTL=0 for tokens in Production**
3. **Give write permission to CI/CD AppRoles**
4. **Log secret values in pipelines**
5. **Use Production secrets in Development**

---

## Next Steps

1. **Enable Audit Logging**
   ```bash
   bao audit enable -namespace=snpsgroup file file_path=/var/log/bao/audit.log
   ```

2. **Configure Automatic Secret Rotation**
   - Use `secret-rotator.ps1`
   - Schedule via Azure DevOps Pipeline

3. **Implement Dynamic Secrets** (advanced)
   - Dynamic database credentials
   - Temporary AWS credentials

4. **Configure Monitoring**
   - Alertas para secrets expirados
   - Dashboard de uso de secrets

---

## Referências

- OpenBao Documentation: https://openbao.org/docs/
- AppRole Auth Method: https://openbao.org/docs/auth/approle/
- KV Secrets Engine: https://openbao.org/docs/secrets/kv/kv-v2/
- Azure DevOps Variable Groups: https://docs.microsoft.com/azure/devops/pipelines/library/variable-groups

---

**✅ OpenBao configurado! Seus secrets estão seguros e organizados.**
