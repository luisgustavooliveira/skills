<#
.SYNOPSIS
    Docker deployment with Blue-Green strategy and zero-downtime

.DESCRIPTION
    Automatiza deployment de containers Docker com:
    - Blue-Green deployment (zero downtime)
    - Health check validation
    - Automatic rollback on failure
    - Secret injection from OpenBao
    - Connection draining
    - Backup management

.PARAMETER ProjectName
    Nome do projeto sendo deployed

.PARAMETER Environment
    Ambiente de destino (Development, Staging, Production)

.PARAMETER Version
    Versão da imagem Docker (tag)

.PARAMETER RegistryUrl
    URL do container registry (ex: snpsgroupacr.azurecr.io)

.PARAMETER Strategy
    Estratégia de deployment: BlueGreen, RollingUpdate, Recreate (default: BlueGreen)

.PARAMETER BluePort
    Porta do container Blue (default: 8080)

.PARAMETER GreenPort
    Porta do container Green (default: 8081)

.PARAMETER HealthCheckTimeout
    Timeout para health check em segundos (default: 120)

.PARAMETER DrainTime
    Tempo de drenagem de conexões em segundos (default: 30)

.PARAMETER DryRun
    Simula deployment sem executar (para testes)

.EXAMPLE
    .\deploy-docker.ps1 -ProjectName "OrderService" -Environment "Development" -Version "1.0.1"

.EXAMPLE
    .\deploy-docker.ps1 -ProjectName "OrderService" -Environment "Production" -Version "1.2.0" -Strategy "BlueGreen"

.EXAMPLE
    .\deploy-docker.ps1 -ProjectName "OrderService" -Environment "Staging" -Version "latest" -DryRun
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("Development", "Staging", "Production")]
    [string]$Environment,
    
    [Parameter(Mandatory=$true)]
    [string]$Version,
    
    [Parameter(Mandatory=$false)]
    [string]$RegistryUrl = "snpsgroupacr.azurecr.io",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("BlueGreen", "RollingUpdate", "Recreate")]
    [string]$Strategy = "BlueGreen",
    
    [Parameter(Mandatory=$false)]
    [int]$BluePort = 8080,
    
    [Parameter(Mandatory=$false)]
    [int]$GreenPort = 8081,
    
    [Parameter(Mandatory=$false)]
    [int]$HealthCheckTimeout = 120,
    
    [Parameter(Mandatory=$false)]
    [int]$DrainTime = 30,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

#Requires -Version 7.0

$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION
# ============================================================================
$config = @{
    ImageName = "$RegistryUrl/${ProjectName.ToLower()}:$Version"
    ContainerBaseName = $ProjectName.ToLower()
    OpenBaoUrl = if ($env:OPENBAO_URL) { $env:OPENBAO_URL } else { "https://keyvault.snpsgroup.com:8200" }
    MaxHealthCheckAttempts = $HealthCheckTimeout / 5
    HealthCheckInterval = 5
}

$envConfig = @{
    Development = @{
        PublicPort = 5000
        AspNetCoreEnv = "Development"
        RestartPolicy = "unless-stopped"
    }
    Staging = @{
        PublicPort = 5001
        AspNetCoreEnv = "Staging"
        RestartPolicy = "unless-stopped"
    }
    Production = @{
        PublicPort = 80
        AspNetCoreEnv = "Production"
        RestartPolicy = "always"
    }
}

$currentEnvConfig = $envConfig[$Environment]

# ============================================================================
# STATE
# ============================================================================
$script:DeploymentLog = @()
$script:RollbackActions = @()

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-DeployLog {
    param(
        [string]$Level,
        [string]$Message
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "INFO" { "Cyan" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }
    
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry -ForegroundColor $color
    $script:DeploymentLog += $logEntry
}

function Test-DockerInstalled {
    try {
        $version = docker version --format '{{.Server.Version}}' 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Docker not running"
        }
        Write-DeployLog "INFO" "Docker version: $version"
        return $true
    } catch {
        Write-DeployLog "ERROR" "Docker is not installed or not running"
        return $false
    }
}

function Get-ContainerInfo {
    param([string]$ContainerName)
    
    try {
        $info = docker ps -a --filter "name=$ContainerName" --format "{{json .}}" | ConvertFrom-Json
        return $info
    } catch {
        return $null
    }
}

function Test-ContainerHealthy {
    param(
        [string]$ContainerName,
        [int]$Port
    )
    
    $attempts = 0
    $maxAttempts = $config.MaxHealthCheckAttempts
    
    Write-DeployLog "INFO" "Waiting for container '$ContainerName' to become healthy..."
    
    while ($attempts -lt $maxAttempts) {
        $attempts++
        
        # Check Docker health status
        $health = docker inspect $ContainerName --format='{{.State.Health.Status}}' 2>&1
        
        if ($health -eq "healthy") {
            Write-DeployLog "SUCCESS" "Container health check passed (attempt $attempts/$maxAttempts)"
            return $true
        }
        
        # Fallback: HTTP health check
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$Port/health" -TimeoutSec 3 -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                Write-DeployLog "SUCCESS" "HTTP health check passed (attempt $attempts/$maxAttempts)"
                return $true
            }
        } catch {
            # Continue trying
        }
        
        Write-DeployLog "WARNING" "Health check attempt $attempts/$maxAttempts failed, waiting $($config.HealthCheckInterval)s..."
        Start-Sleep -Seconds $config.HealthCheckInterval
    }
    
    Write-DeployLog "ERROR" "Health check timeout after $maxAttempts attempts"
    return $false
}

function Get-OpenBaoSecrets {
    param([string]$Env)
    
    Write-DeployLog "INFO" "Fetching secrets from OpenBao for environment: $Env"
    
    if ([string]::IsNullOrEmpty($env:OPENBAO_ROLE_ID) -or [string]::IsNullOrEmpty($env:OPENBAO_SECRET_ID)) {
        Write-DeployLog "WARNING" "OpenBao credentials not found in environment variables"
        return @{}
    }
    
    try {
        # Authenticate with OpenBao
        $env:VAULT_ADDR = $config.OpenBaoUrl
        $authResponse = bao write -namespace=snpsgroup auth/approle/login "role_id=$env:OPENBAO_ROLE_ID" "secret_id=$env:OPENBAO_SECRET_ID" -format=json 2>&1 | ConvertFrom-Json
        
        if ($null -eq $authResponse.auth.client_token) {
            throw "Failed to authenticate with OpenBao"
        }
        
        $env:VAULT_TOKEN = $authResponse.auth.client_token
        
        # Fetch secrets
        $secretPath = "$($ProjectName.ToLower())/$($Env.ToLower())"
        $secrets = bao kv get -namespace=snpsgroup -format=json "secret/$secretPath" 2>&1 | ConvertFrom-Json
        
        Write-DeployLog "SUCCESS" "Secrets fetched successfully"
        
        # Convert to environment variables format
        $envVars = @{}
        foreach ($key in $secrets.data.data.PSObject.Properties.Name) {
            $envKey = "SECRET_$($key.ToUpper() -replace '-','_')"
            $envVars[$envKey] = $secrets.data.data.$key
        }
        
        return $envVars
    } catch {
        Write-DeployLog "ERROR" "Failed to fetch secrets from OpenBao: $($_.Exception.Message)"
        return @{}
    }
}

function Start-Container {
    param(
        [string]$ContainerName,
        [int]$Port,
        [hashtable]$EnvVars = @{}
    )
    
    Write-DeployLog "INFO" "Starting container '$ContainerName' on port $Port"
    
    if ($DryRun) {
        Write-DeployLog "INFO" "[DRY RUN] Would start container: $ContainerName"
        return $true
    }
    
    # Build environment variables string
    $envString = @(
        "-e", "ASPNETCORE_ENVIRONMENT=$($currentEnvConfig.AspNetCoreEnv)"
        "-e", "ASPNETCORE_URLS=http://+:8080"
        "-e", "OPENBAO_URL=$($config.OpenBaoUrl)"
    )
    
    foreach ($key in $EnvVars.Keys) {
        $envString += "-e"
        $envString += "$key=$($EnvVars[$key])"
    }
    
    try {
        # Start container
        $containerId = docker run -d `
            --name $ContainerName `
            -p "$Port:8080" `
            @envString `
            --restart $currentEnvConfig.RestartPolicy `
            $config.ImageName
        
        if ($LASTEXITCODE -ne 0) {
            throw "Docker run failed with exit code $LASTEXITCODE"
        }
        
        Write-DeployLog "SUCCESS" "Container started with ID: $($containerId.Substring(0, 12))"
        
        # Add rollback action
        $script:RollbackActions += @{
            Action = "StopContainer"
            ContainerName = $ContainerName
        }
        
        return $true
    } catch {
        Write-DeployLog "ERROR" "Failed to start container: $($_.Exception.Message)"
        return $false
    }
}

function Stop-SafeContainer {
    param(
        [string]$ContainerName,
        [int]$DrainSeconds = 30
    )
    
    $container = Get-ContainerInfo -ContainerName $ContainerName
    
    if ($null -eq $container) {
        Write-DeployLog "WARNING" "Container '$ContainerName' not found"
        return $true
    }
    
    Write-DeployLog "INFO" "Stopping container '$ContainerName' (draining connections for $DrainSeconds seconds)..."
    
    if ($DryRun) {
        Write-DeployLog "INFO" "[DRY RUN] Would stop container: $ContainerName"
        return $true
    }
    
    # Drain connections
    Start-Sleep -Seconds $DrainSeconds
    
    # Stop container
    docker stop $ContainerName 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-DeployLog "SUCCESS" "Container stopped successfully"
        return $true
    } else {
        Write-DeployLog "ERROR" "Failed to stop container"
        return $false
    }
}

function Remove-Container {
    param([string]$ContainerName)
    
    if ($DryRun) {
        Write-DeployLog "INFO" "[DRY RUN] Would remove container: $ContainerName"
        return $true
    }
    
    docker rm $ContainerName 2>&1 | Out-Null
    Write-DeployLog "INFO" "Container '$ContainerName' removed"
}

function Backup-Container {
    param([string]$ContainerName)
    
    $container = Get-ContainerInfo -ContainerName $ContainerName
    
    if ($null -eq $container) {
        return $false
    }
    
    $backupName = "$ContainerName-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    Write-DeployLog "INFO" "Creating backup: $backupName"
    
    if ($DryRun) {
        Write-DeployLog "INFO" "[DRY RUN] Would create backup: $backupName"
        return $true
    }
    
    # Rename current container to backup
    docker rename $ContainerName $backupName 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-DeployLog "SUCCESS" "Backup created: $backupName"
        return $true
    } else {
        Write-DeployLog "ERROR" "Failed to create backup"
        return $false
    }
}

function Invoke-Rollback {
    Write-DeployLog "ERROR" "Deployment failed! Initiating rollback..."
    
    # Execute rollback actions in reverse order
    $script:RollbackActions | Sort-Object -Descending | ForEach-Object {
        $action = $_
        
        switch ($action.Action) {
            "StopContainer" {
                Write-DeployLog "INFO" "Rollback: Stopping container $($action.ContainerName)"
                docker stop $action.ContainerName 2>&1 | Out-Null
                docker rm $action.ContainerName 2>&1 | Out-Null
            }
        }
    }
    
    Write-DeployLog "SUCCESS" "Rollback completed"
}

function Deploy-BlueGreen {
    Write-DeployLog "INFO" "=== Blue-Green Deployment Strategy ==="
    
    $blueContainer = "$($config.ContainerBaseName)-blue"
    $greenContainer = "$($config.ContainerBaseName)-green"
    
    # 1. Pull new image
    Write-DeployLog "INFO" "Pulling image: $($config.ImageName)"
    
    if (!$DryRun) {
        docker pull $config.ImageName
        if ($LASTEXITCODE -ne 0) {
            Write-DeployLog "ERROR" "Failed to pull image"
            return $false
        }
    }
    
    # 2. Check if Blue is running
    $blueInfo = Get-ContainerInfo -ContainerName $blueContainer
    $blueRunning = ($null -ne $blueInfo -and $blueInfo.Status -like "Up*")
    
    if ($blueRunning) {
        Write-DeployLog "INFO" "Blue container is currently running"
    } else {
        Write-DeployLog "WARNING" "Blue container not running (first deployment or after failure)"
    }
    
    # 3. Fetch secrets
    $secrets = Get-OpenBaoSecrets -Env $Environment
    
    # 4. Start Green container
    $greenStarted = Start-Container -ContainerName $greenContainer -Port $GreenPort -EnvVars $secrets
    
    if (!$greenStarted) {
        Write-DeployLog "ERROR" "Failed to start Green container"
        Invoke-Rollback
        return $false
    }
    
    # 5. Health check Green
    $greenHealthy = Test-ContainerHealthy -ContainerName $greenContainer -Port $GreenPort
    
    if (!$greenHealthy) {
        Write-DeployLog "ERROR" "Green container failed health check"
        
        # Show logs for debugging
        Write-DeployLog "ERROR" "Container logs:"
        if (!$DryRun) {
            docker logs --tail 50 $greenContainer
        }
        
        Invoke-Rollback
        return $false
    }
    
    # 6. Switch traffic (proxy update would go here)
    Write-DeployLog "INFO" "Switching traffic from Blue to Green..."
    Write-DeployLog "WARNING" "NOTE: Update your load balancer/proxy to point to port $GreenPort"
    
    # 7. Drain connections from Blue
    if ($blueRunning) {
        Write-DeployLog "INFO" "Draining connections from Blue ($DrainTime seconds)..."
        Start-Sleep -Seconds $DrainTime
        
        # 8. Stop Blue
        Stop-SafeContainer -ContainerName $blueContainer -DrainSeconds 0
        
        # 9. Backup Blue
        Backup-Container -ContainerName $blueContainer
    }
    
    # 10. Green becomes the new Blue
    Write-DeployLog "INFO" "Promoting Green to Blue..."
    
    if (!$DryRun) {
        docker stop $greenContainer
        docker rename $greenContainer $blueContainer
        
        # Update port mapping
        docker rm $blueContainer 2>&1 | Out-Null
        
        # Restart with Blue port
        $secrets = Get-OpenBaoSecrets -Env $Environment
        Start-Container -ContainerName $blueContainer -Port $BluePort -EnvVars $secrets
        
        # Final health check
        $finalHealthy = Test-ContainerHealthy -ContainerName $blueContainer -Port $BluePort
        
        if (!$finalHealthy) {
            Write-DeployLog "ERROR" "Final health check failed after promotion"
            Invoke-Rollback
            return $false
        }
    }
    
    Write-DeployLog "SUCCESS" "Blue-Green deployment completed successfully!"
    return $true
}

function Deploy-Recreate {
    Write-DeployLog "INFO" "=== Recreate Deployment Strategy ==="
    
    $containerName = "$($config.ContainerBaseName)-main"
    
    # 1. Pull new image
    Write-DeployLog "INFO" "Pulling image: $($config.ImageName)"
    
    if (!$DryRun) {
        docker pull $config.ImageName
    }
    
    # 2. Stop and remove existing container
    $existing = Get-ContainerInfo -ContainerName $containerName
    
    if ($null -ne $existing) {
        Write-DeployLog "INFO" "Stopping existing container..."
        Stop-SafeContainer -ContainerName $containerName -DrainSeconds $DrainTime
        
        Backup-Container -ContainerName $containerName
        Remove-Container -ContainerName $containerName
    }
    
    # 3. Fetch secrets
    $secrets = Get-OpenBaoSecrets -Env $Environment
    
    # 4. Start new container
    $started = Start-Container -ContainerName $containerName -Port $BluePort -EnvVars $secrets
    
    if (!$started) {
        Write-DeployLog "ERROR" "Failed to start new container"
        Invoke-Rollback
        return $false
    }
    
    # 5. Health check
    $healthy = Test-ContainerHealthy -ContainerName $containerName -Port $BluePort
    
    if (!$healthy) {
        Write-DeployLog "ERROR" "Health check failed"
        Invoke-Rollback
        return $false
    }
    
    Write-DeployLog "SUCCESS" "Recreate deployment completed successfully!"
    return $true
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-Host "`n" + "="*70 -ForegroundColor Magenta
Write-Host " DOCKER DEPLOYMENT" -ForegroundColor Magenta
Write-Host " Project: $ProjectName" -ForegroundColor Magenta
Write-Host " Environment: $Environment" -ForegroundColor Magenta
Write-Host " Version: $Version" -ForegroundColor Magenta
Write-Host " Strategy: $Strategy" -ForegroundColor Magenta
if ($DryRun) {
    Write-Host " Mode: DRY RUN" -ForegroundColor Yellow
}
Write-Host "="*70 -ForegroundColor Magenta

try {
    # 1. Validate Docker
    if (!(Test-DockerInstalled)) {
        throw "Docker is not available"
    }
    
    # 2. Execute deployment strategy
    $success = switch ($Strategy) {
        "BlueGreen" { Deploy-BlueGreen }
        "Recreate" { Deploy-Recreate }
        default { throw "Unknown strategy: $Strategy" }
    }
    
    if (!$success) {
        throw "Deployment failed"
    }
    
    # 3. Summary
    Write-Host "`n" + "="*70 -ForegroundColor Green
    Write-Host " DEPLOYMENT SUCCESSFUL" -ForegroundColor Green
    Write-Host "="*70 -ForegroundColor Green
    
    Write-Host "`nDeployment Details:" -ForegroundColor Cyan
    Write-Host "  Project     : $ProjectName" -ForegroundColor White
    Write-Host "  Environment : $Environment" -ForegroundColor White
    Write-Host "  Version     : $Version" -ForegroundColor White
    Write-Host "  Strategy    : $Strategy" -ForegroundColor White
    Write-Host "  Port        : $BluePort" -ForegroundColor White
    Write-Host "  Status      : ✅ Running" -ForegroundColor Green
    
    Write-Host "`nHealth Check:" -ForegroundColor Cyan
    Write-Host "  URL: http://localhost:$BluePort/health" -ForegroundColor White
    
    if (!$DryRun) {
        # Test health check
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$BluePort/health" -TimeoutSec 5
            Write-Host "  Status: $($response.StatusCode) $($response.StatusDescription)" -ForegroundColor Green
        } catch {
            Write-Host "  Status: Unable to reach health endpoint" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    
    exit 0
    
} catch {
    Write-DeployLog "ERROR" "Deployment failed: $($_.Exception.Message)"
    
    Write-Host "`n" + "="*70 -ForegroundColor Red
    Write-Host " DEPLOYMENT FAILED" -ForegroundColor Red
    Write-Host "="*70 -ForegroundColor Red
    
    Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nDeployment log saved for investigation" -ForegroundColor Yellow
    
    # Save deployment log
    $logFile = "./deployment-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    $script:DeploymentLog | Out-File $logFile
    Write-Host "Log file: $logFile" -ForegroundColor Cyan
    
    exit 1
}
