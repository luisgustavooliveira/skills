# Workflow: Docker Deployment

**Objective**: Deploy .NET Core 9+ applications in Docker containers with zero-downtime

**Complexity**: Medium-High  
**Estimated Duration**: 30-40 minutes (first time), 10 min (subsequent)  
**Prerequisites**: Docker installed, project configured, secrets in OpenBao

---

## Overview

This workflow covers complete deployment using Docker:
- ✅ .NET application containerization
- ✅ Optimized multi-stage builds
- ✅ Secure secret injection
- ✅ Health checks and readiness probes
- ✅ Blue-Green deployment (zero downtime)
- ✅ Automatic rollback

### Docker Advantages

| Aspect | Docker | IIS | Kubernetes |
|--------|--------|-----|------------|
| Portability | ✅ High | ❌ Windows only | ✅ High |
| Isolation | ✅ Container | ⚠️ AppPool | ✅ Pod |
| Deploy Speed | ✅ <1 min | ⚠️ 2-5 min | ⚠️ 1-3 min |
| Rollback | ✅ Instant | ⚠️ Manual | ✅ Automatic |
| Complexity | ⚠️ Medium | ✅ Low | ❌ High |
| Scale | ⚠️ Manual | ❌ Limited | ✅ Automatic |

**Recommendation**: Docker is ideal for microservices and cloud-native applications

---

## Deployment Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Docker Host                        │
│                                                     │
│  ┌────────────────────┐  ┌────────────────────┐     │
│  │   Blue (Current)   │  │   Green (New)      │     │
│  │  OrderService:v1.0 │  │  OrderService:v1.1 │     │
│  │  Port: 8080        │  │  Port: 8081        │     │
│  │  Status: Running   │  │  Status: Starting  │     │
│  └────────────────────┘  └────────────────────┘     │
│           │                       │                 │
│           └───────┬───────────────┘                 │
│                   │                                 │
│         ┌─────────▼──────────┐                      │
│         │   Nginx Proxy      │                      │
│         │   Port: 80/443     │                      │
│         └────────────────────┘                      │
└─────────────────────────────────────────────────────┘
                    │
                    ▼
              Internet / LB
```

---

## Phase 1: Preparation - Dockerfile (10 min)

### Step 1.1: Create Optimized Dockerfile

Create `Dockerfile` in the project root:

```dockerfile
# Multi-stage build for size optimization and security

# ============================================================================
# Stage 1: Build
# ============================================================================
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Copy only csproj first (for restore cache)
COPY ["OrderService/OrderService.csproj", "OrderService/"]
RUN dotnet restore "OrderService/OrderService.csproj"

# Copy source code
COPY . .
WORKDIR "/src/OrderService"

# Build Release
RUN dotnet build "OrderService.csproj" \
    -c Release \
    -o /app/build \
    --no-restore

# ============================================================================
# Stage 2: Publish
# ============================================================================
FROM build AS publish
RUN dotnet publish "OrderService.csproj" \
    -c Release \
    -o /app/publish \
    --no-restore \
    --no-build \
    /p:UseAppHost=false \
    /p:PublishTrimmed=false \
    /p:PublishReadyToRun=true

# ============================================================================
# Stage 3: Runtime (final image)
# ============================================================================
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final

# Metadata
LABEL maintainer="SnpsGroup DevOps <devops@snpsgroup.com>"
LABEL project="OrderService"
LABEL version="1.0"

# Create non-root user (security)
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Working directory
WORKDIR /app

# Copy artifacts from publish stage
COPY --from=publish /app/publish .

# Change ownership to appuser
RUN chown -R appuser:appuser /app

# Use non-root user
USER appuser

# Default port (can be overridden)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Entrypoint
ENTRYPOINT ["dotnet", "OrderService.dll"]
```

**Implemented Optimizations**:
- ✅ Multi-stage build (final image ~200MB vs ~1GB)
- ✅ Layer caching (separate restore)
- ✅ Ready-to-Run compilation (startup 50% faster)
- ✅ Non-root user (security)
- ✅ Integrated health check

---

### Step 1.2: Create .dockerignore

Create `.dockerignore`:

```
# Build artifacts
**/bin/
**/obj/
**/out/
**/publish/
**/artifacts/

# IDE
**/.vs/
**/.vscode/
**/.idea/
*.user
*.suo

# Git
.git/
.gitignore
.gitattributes

# Documentation
**/*.md
!README.md

# Logs
**/*.log

# Temp
**/temp/
**/tmp/

# Tests
**/*Tests/
**/TestResults/

# Deployment
**/deployment/
**/azure-pipelines.yml

# Secrets (DO NOT include in images!)
**/*.pfx
**/*.p12
**/secrets.json
**/.env
```

---

### Step 1.3: Create docker-compose.yml (for local development)

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  orderservice:
    build:
      context: .
      dockerfile: Dockerfile
    image: orderservice:dev
    container_name: orderservice-dev
    ports:
      - "5000:8080"
    environment:
      - ASPNETCORE_ENVIRONMENT=Development
      - ASPNETCORE_URLS=http://+:8080
      # OpenBao connection
      - OPENBAO_URL=https://keyvault.snpsgroup.com:8200
      - OPENBAO_ROLE_ID=${OPENBAO_ROLE_ID}
      - OPENBAO_SECRET_ID=${OPENBAO_SECRET_ID}
    volumes:
      # Persistent logs
      - ./logs:/app/logs
    networks:
      - orderservice-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 10s
    restart: unless-stopped

  # Redis (optional - dependency)
  redis:
    image: redis:7-alpine
    container_name: orderservice-redis-dev
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    networks:
      - orderservice-network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3
    restart: unless-stopped

networks:
  orderservice-network:
    driver: bridge

volumes:
  redis-data:
```

---

## Phase 2: Build and Local Test (10 min)

### Step 2.1: Docker Image Build

```powershell
# Build image
docker build -t orderservice:latest .

# Build with specific tag
docker build -t orderservice:1.0.0 -t orderservice:latest .

# Build with build args
docker build \
  --build-arg BUILD_VERSION=1.0.0 \
  --build-arg BUILD_DATE=$(Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") \
  -t orderservice:1.0.0 \
  .
```

**Expected Output**:
```
[+] Building 45.3s (18/18) FINISHED
 => [internal] load .dockerignore
 => [internal] load build definition from Dockerfile
 => [internal] load metadata for mcr.microsoft.com/dotnet/aspnet:9.0
 => [internal] load metadata for mcr.microsoft.com/dotnet/sdk:9.0
 => [build 1/6] FROM mcr.microsoft.com/dotnet/sdk:9.0
 => [final 1/6] FROM mcr.microsoft.com/dotnet/aspnet:9.0
 => CACHED [build 2/6] WORKDIR /src
 => [build 3/6] COPY [OrderService/OrderService.csproj, OrderService/]
 => [build 4/6] RUN dotnet restore OrderService/OrderService.csproj
 => [build 5/6] COPY . .
 => [build 6/6] RUN dotnet build OrderService.csproj -c Release
 => [publish 1/1] RUN dotnet publish OrderService.csproj -c Release
 => [final 2/6] RUN groupadd -r appuser && useradd -r -g appuser appuser
 => [final 3/6] WORKDIR /app
 => [final 4/6] COPY --from=publish /app/publish .
 => [final 5/6] RUN chown -R appuser:appuser /app
 => exporting to image
 => => naming to docker.io/library/orderservice:1.0.0
 => => naming to docker.io/library/orderservice:latest
```

**Verify Image**:
```powershell
# List images
docker images orderservice

# Output:
# REPOSITORY      TAG       IMAGE ID       CREATED          SIZE
# orderservice    1.0.0     a1b2c3d4e5f6   2 minutes ago    214MB
# orderservice    latest    a1b2c3d4e5f6   2 minutes ago    214MB
```

**Size Optimization**:
```powershell
# Analyze layers
docker history orderservice:latest

# Check detailed size
docker image inspect orderservice:latest --format='{{.Size}}' | 
  ForEach-Object { [math]::Round($_ / 1MB, 2) }
```

---

### Step 2.2: Run Container Locally

```powershell
# Run in interactive mode (development)
docker run -it --rm `
  -p 5000:8080 `
  -e ASPNETCORE_ENVIRONMENT=Development `
  -e OPENBAO_URL=https://keyvault.snpsgroup.com:8200 `
  -e OPENBAO_ROLE_ID="dev-role-id" `
  -e OPENBAO_SECRET_ID="dev-secret-id" `
  --name orderservice-test `
  orderservice:latest

# Run in background (daemon)
docker run -d `
  -p 5000:8080 `
  -e ASPNETCORE_ENVIRONMENT=Development `
  --name orderservice-test `
  --restart unless-stopped `
  orderservice:latest

# Or using docker-compose
docker-compose up -d
```

**Verify Container Running**:
```powershell
docker ps

# Output:
# CONTAINER ID   IMAGE                  STATUS          PORTS                    NAMES
# a1b2c3d4e5f6   orderservice:latest    Up 2 minutes    0.0.0.0:5000->8080/tcp   orderservice-test
```

---

### Step 2.3: Test Health Check

```powershell
# Test health endpoint
curl http://localhost:5000/health

# Or using PowerShell
Invoke-WebRequest -Uri "http://localhost:5000/health" | Select-Object StatusCode, Content

# Check container logs
docker logs orderservice-test

# Follow logs in real-time
docker logs -f orderservice-test

# Check Docker health check
docker inspect orderservice-test --format='{{.State.Health.Status}}'
# Output: healthy
```

**Detailed Health Check**:
```powershell
docker inspect orderservice-test --format='{{json .State.Health}}' | ConvertFrom-Json
```

---

### Step 2.4: Execute Commands Inside Container

```powershell
# Interactive shell
docker exec -it orderservice-test /bin/bash

# Single command
docker exec orderservice-test ls -la /app

# View environment variables
docker exec orderservice-test env | grep ASPNETCORE

# Test internal connectivity
docker exec orderservice-test curl http://localhost:8080/health
```

---

## Phase 3: Registry and Versioning (5 min)

### Step 3.1: Configure Azure Container Registry

```powershell
# Variables
$registryName = "snpsgroupacr"
$resourceGroup = "SnpsGroup-Infrastructure"
$location = "brazilsouth"

# Create ACR (if not exists)
az acr create `
  --name $registryName `
  --resource-group $resourceGroup `
  --location $location `
  --sku Standard `
  --admin-enabled false

# Login to ACR
az acr login --name $registryName

# Or using Docker directly
$acrUsername = az acr credential show --name $registryName --query username -o tsv
$acrPassword = az acr credential show --name $registryName --query passwords[0].value -o tsv

docker login "$registryName.azurecr.io" -u $acrUsername -p $acrPassword
```

---

### Step 3.2: Tag and Push to Registry

```powershell
# Tag for registry
$imageName = "orderservice"
$version = "1.0.0"
$registry = "$registryName.azurecr.io"

docker tag orderservice:$version "$registry/$imageName:$version"
docker tag orderservice:$version "$registry/$imageName:latest"

# Push to registry
docker push "$registry/$imageName:$version"
docker push "$registry/$imageName:latest"

# List images in registry
az acr repository list --name $registryName --output table

# List tags
az acr repository show-tags --name $registryName --repository $imageName --output table
```

**Tag Convention**:
```
snpsgroupacr.azurecr.io/orderservice:1.0.0          # Specific version
snpsgroupacr.azurecr.io/orderservice:1.0            # Major.Minor
snpsgroupacr.azurecr.io/orderservice:1              # Major
snpsgroupacr.azurecr.io/orderservice:latest         # Latest version
snpsgroupacr.azurecr.io/orderservice:develop        # develop branch
snpsgroupacr.azurecr.io/orderservice:main           # main branch
snpsgroupacr.azurecr.io/orderservice:pr-123         # Pull request
```

---

## Phase 4: Zero-Downtime Deployment (10 min)

### Step 4.1: Create Deployment Script (deploy-docker.ps1)

> 📖 **See**: `scripts/deploy-docker.ps1` (will be created next)

**Blue-Green Strategy Summary**:

```
1. Blue (current) is running on port 8080
2. Deploy Green (new) on port 8081
3. Green health check until healthy
4. Switch proxy (Nginx/Traefik) to point to Green
5. Wait for Blue connection draining
6. Stop Blue (becomes backup for rollback)
7. Green becomes the new Blue
```

---

### Step 4.2: Manual Deployment (Example)

```powershell
# Configurations
$project = "orderservice"
$version = "1.0.1"
$registry = "snpsgroupacr.azurecr.io"
$env = "production"

# 1. Pull new image
docker pull "$registry/$project:$version"

# 2. Identify current container (Blue)
$blueContainer = docker ps --filter "name=$project-blue" --format "{{.ID}}"
$bluePort = 8080

# 3. Start new container (Green)
$greenPort = 8081
docker run -d `
  --name "$project-green" `
  -p "$greenPort:8080" `
  -e ASPNETCORE_ENVIRONMENT=Production `
  -e OPENBAO_URL=https://keyvault.snpsgroup.com:8200 `
  -e OPENBAO_ROLE_ID=$env:PROD_ROLE_ID `
  -e OPENBAO_SECRET_ID=$env:PROD_SECRET_ID `
  --restart unless-stopped `
  "$registry/$project:$version"

Write-Host "Green container started on port $greenPort" -ForegroundColor Green

# 4. Wait for health check
$maxAttempts = 20
$attempt = 0
$healthy = $false

while ($attempt -lt $maxAttempts -and !$healthy) {
    $attempt++
    Write-Host "Health check attempt $attempt/$maxAttempts..." -ForegroundColor Cyan
    
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$greenPort/health" -TimeoutSec 3
        if ($response.StatusCode -eq 200) {
            $healthy = $true
            Write-Host "✅ Green container is healthy!" -ForegroundColor Green
        }
    } catch {
        Write-Host "⏳ Waiting..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
}

if (!$healthy) {
    Write-Host "❌ Green container failed health check. Rolling back..." -ForegroundColor Red
    docker stop "$project-green"
    docker rm "$project-green"
    exit 1
}

# 5. Switch proxy (Nginx example - adapt to your proxy)
# Update Nginx upstream from port 8080 -> 8081
# nginx -s reload

Write-Host "Switch proxy from Blue (port $bluePort) to Green (port $greenPort)" -ForegroundColor Cyan

# 6. Wait for connection draining (30 seconds)
Write-Host "Waiting for connection draining..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# 7. Stop Blue (keep as backup)
if ($blueContainer) {
    Write-Host "Stopping Blue container (keeping as backup)..." -ForegroundColor Yellow
    docker stop "$project-blue"
    docker rename "$project-blue" "$project-backup"
}

# 8. Green becomes the new Blue
docker stop "$project-green"
docker rename "$project-green" "$project-blue"
docker start "$project-blue"

Write-Host "`n✅ Deployment completed successfully!" -ForegroundColor Green
Write-Host "Blue container (port $bluePort) is now running version $version" -ForegroundColor Cyan
```

---

### Step 4.3: Rollback (if necessary)

```powershell
# Rollback to previous version (backup)
$backupContainer = docker ps -a --filter "name=$project-backup" --format "{{.ID}}"

if ($backupContainer) {
    Write-Host "Rolling back to previous version..." -ForegroundColor Yellow
    
    # Stop current
    docker stop "$project-blue"
    docker rm "$project-blue"
    
    # Restore backup
    docker rename "$project-backup" "$project-blue"
    docker start "$project-blue"
    
    # Update proxy
    # nginx -s reload
    
    Write-Host "✅ Rollback completed!" -ForegroundColor Green
} else {
    Write-Host "❌ No backup container found!" -ForegroundColor Red
}
```

---

## Phase 5: Automation via Azure DevOps (5 min)

### Step 5.1: Add Docker Stage to Pipeline

Edit `azure-pipelines.yml`:

```yaml
# Add after existing stages

- stage: BuildDocker
  displayName: 'Build Docker Image'
  dependsOn: Build
  jobs:
  - job: DockerBuild
    displayName: 'Build and Push Docker Image'
    pool:
      vmImage: 'ubuntu-latest'
    steps:
    - task: Docker@2
      displayName: 'Build Docker Image'
      inputs:
        command: build
        dockerfile: '$(Build.SourcesDirectory)/Dockerfile'
        tags: |
          $(Build.BuildNumber)
          latest
        arguments: '--build-arg BUILD_VERSION=$(Build.BuildNumber)'
    
    - task: Docker@2
      displayName: 'Push to ACR'
      inputs:
        command: push
        containerRegistry: 'SnpsGroupACR'  # Service Connection
        repository: 'orderservice'
        tags: |
          $(Build.BuildNumber)
          latest

- stage: DeployDockerDevelopment
  displayName: 'Deploy Docker - Development'
  dependsOn: BuildDocker
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/develop'))
  jobs:
  - deployment: DeployDev
    displayName: 'Deploy to Development'
    environment: 'OrderService-Development'
    strategy:
      runOnce:
        deploy:
          steps:
          - task: PowerShell@2
            displayName: 'Deploy Docker Container'
            inputs:
              filePath: '$(Pipeline.Workspace)/deployment-scripts/deploy-docker.ps1'
              arguments: >
                -ProjectName "OrderService"
                -Environment "Development"
                -Version "$(Build.BuildNumber)"
                -RegistryUrl "snpsgroupacr.azurecr.io"
              workingDirectory: '$(Pipeline.Workspace)'

- stage: DeployDockerProduction
  displayName: 'Deploy Docker - Production'
  dependsOn: BuildDocker
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
  - deployment: DeployProd
    displayName: 'Deploy to Production'
    environment: 'OrderService-Production'  # With manual approval
    strategy:
      runOnce:
        deploy:
          steps:
          - task: PowerShell@2
            displayName: 'Pre-Deployment Validation'
            inputs:
              filePath: '$(Pipeline.Workspace)/deployment-scripts/deploy-check.ps1'
              arguments: >
                -Environment "Production"
                -ProjectName "OrderService"
          
          - task: PowerShell@2
            displayName: 'Deploy Docker Container (Blue-Green)'
            inputs:
              filePath: '$(Pipeline.Workspace)/deployment-scripts/deploy-docker.ps1'
              arguments: >
                -ProjectName "OrderService"
                -Environment "Production"
                -Version "$(Build.BuildNumber)"
                -RegistryUrl "snpsgroupacr.azurecr.io"
                -Strategy "BlueGreen"
          
          - task: PowerShell@2
            displayName: 'Post-Deployment Health Check'
            inputs:
              targetType: 'inline'
              script: |
                $response = Invoke-WebRequest -Uri "https://www.snpsgroup.com/OrderService/health"
                if ($response.StatusCode -ne 200) {
                  Write-Error "Health check failed!"
                  exit 1
                }
                Write-Host "✅ Deployment healthy!"
```

---

### Step 5.2: Configure Service Connection for ACR

```powershell
# Via Azure DevOps UI:
# 1. Project Settings → Service connections
# 2. New service connection → Docker Registry
# 3. Registry type: Azure Container Registry
# 4. Select ACR: snpsgroupacr
# 5. Service connection name: SnpsGroupACR
# 6. Grant access to all pipelines

# Or via CLI
az devops service-endpoint create `
  --service-endpoint-type dockerregistry `
  --name "SnpsGroupACR" `
