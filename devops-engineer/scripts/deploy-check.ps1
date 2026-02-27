<#
.SYNOPSIS
    Pre-deployment validation and safety checks

.DESCRIPTION
    Comprehensive pre-deployment validation including:
    - Build artifact integrity
    - Configuration token replacement
    - Secret availability and freshness
    - Target environment health
    - Database migration readiness
    - Rollback capability verification
    - Resource availability checks
    
    This script should be run BEFORE actual deployment to catch issues early.

.PARAMETER Environment
    Target environment (Development, Staging, Production)

.PARAMETER ProjectName
    Project name being deployed

.PARAMETER PublishDirectory
    Directory containing build artifacts (default: ./publish)

.PARAMETER BackupRequired
    Verify backup was created (default: true for Staging/Production)

.PARAMETER SkipHealthCheck
    Skip target environment health check (default: false)

.PARAMETER SkipSecretValidation
    Skip OpenBao secret validation (default: false)

.EXAMPLE
    .\deploy-check.ps1 -Environment "Production" -ProjectName "OrderService"

.EXAMPLE
    .\deploy-check.ps1 -Environment "Development" -ProjectName "OrderService" -SkipHealthCheck

.NOTES
    Exit codes:
    0 = All checks passed, safe to deploy
    1 = Critical failure, DO NOT deploy
    2 = Warnings present, review before deploying
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Development", "Staging", "Production")]
    [string]$Environment,
    
    [Parameter(Mandatory=$true)]
    [string]$ProjectName,
    
    [Parameter(Mandatory=$false)]
    [string]$PublishDirectory = "./publish",
    
    [Parameter(Mandatory=$false)]
    [bool]$BackupRequired = ($Environment -in @("Staging", "Production")),
    
    [Parameter(Mandatory=$false)]
    [bool]$SkipHealthCheck = $false,
    
    [Parameter(Mandatory=$false)]
    [bool]$SkipSecretValidation = $false
)

#Requires -Version 7.0

$ErrorActionPreference = "Stop"

# ============================================================================
# SCRIPT STATE
# ============================================================================
$script:ChecksPassed = 0
$script:ChecksFailed = 0
$script:ChecksWarning = 0
$script:CriticalFailures = @()
$script:Warnings = @()

# ============================================================================
# CONFIGURATION
# ============================================================================
$config = @{
    OpenBaoUrl = if ($env:OPENBAO_URL) { $env:OPENBAO_URL } else { "https://keyvault.snpsgroup.com:8200" }
    HealthCheckTimeout = 30
    MaxBackupAge = if ($Environment -eq "Production") { 1 } else { 7 }  # Days
    RequiredDiskSpace = 5GB  # Minimum free space
    MaxDeploymentSize = 2GB  # Alert if larger
}

# Environment-specific settings
$envConfig = @{
    Development = @{
        BaseUrl = "http://localhost"
        Port = 5000
        RequireApproval = $false
        RequireBackup = $false
    }
    Staging = @{
        BaseUrl = "https://staging.snpsgroup.com"
        Port = 443
        RequireApproval = $false
        RequireBackup = $true
    }
    Production = @{
        BaseUrl = "https://www.snpsgroup.com"
        Port = 443
        RequireApproval = $true
        RequireBackup = $true
    }
}

$currentEnvConfig = $envConfig[$Environment]

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Test-DeployCheck {
    param(
        [string]$Name,
        [scriptblock]$Check,
        [bool]$Critical = $true,
        [string]$FailureMessage = "",
        [string]$SuccessMessage = ""
    )
    
    Write-Host "`n▶ Checking: $Name" -ForegroundColor Cyan
    
    try {
        $result = & $Check
        if ($result -eq $false) {
            throw "Check returned false"
        }
        
        Write-Host "  ✅ PASS" -ForegroundColor Green
        if ($SuccessMessage) {
            Write-Host "    $SuccessMessage" -ForegroundColor Gray
        }
        $script:ChecksPassed++
        return $true
        
    } catch {
        $errorMsg = if ($FailureMessage) { $FailureMessage } else { $_.Exception.Message }
        
        if ($Critical) {
            Write-Host "  ❌ FAIL: $errorMsg" -ForegroundColor Red
            $script:ChecksFailed++
            $script:CriticalFailures += "$Name : $errorMsg"
        } else {
            Write-Host "  ⚠️  WARNING: $errorMsg" -ForegroundColor Yellow
            $script:ChecksWarning++
            $script:Warnings += "$Name : $errorMsg"
        }
        return $false
    }
}

function Get-FileHash256 {
    param([string]$FilePath)
    return (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
}

function Get-DirectorySize {
    param([string]$Path)
    return (Get-ChildItem -Path $Path -Recurse | Measure-Object -Property Length -Sum).Sum
}

function Test-JsonValid {
    param([string]$FilePath)
    try {
        $content = Get-Content $FilePath -Raw
        $null = $content | ConvertFrom-Json
        return $true
    } catch {
        return $false
    }
}

function Get-TokensInFile {
    param([string]$FilePath)
    $content = Get-Content $FilePath -Raw
    return [regex]::Matches($content, '#\{([a-z0-9\-]+)\}') | ForEach-Object { $_.Value }
}

# ============================================================================
# BANNER
# ============================================================================
Write-Host "`n" + "="*70 -ForegroundColor Magenta
Write-Host " PRE-DEPLOYMENT VALIDATION" -ForegroundColor Magenta
Write-Host " Environment: $Environment" -ForegroundColor Magenta
Write-Host " Project: $ProjectName" -ForegroundColor Magenta
Write-Host " Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Magenta
Write-Host "="*70 -ForegroundColor Magenta

# ============================================================================
# SECTION 1: BUILD ARTIFACTS
# ============================================================================
Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host " BUILD ARTIFACTS VALIDATION" -ForegroundColor Cyan
Write-Host "="*70 -ForegroundColor Cyan

Test-DeployCheck "Publish directory exists" {
    if (!(Test-Path $PublishDirectory)) {
        throw "Directory not found: $PublishDirectory (run: nuke Publish)"
    }
    return $true
} -SuccessMessage "Found: $PublishDirectory"

Test-DeployCheck "Required files present" {
    $requiredFiles = @(
        "$ProjectName.dll",
        "$ProjectName.deps.json",
        "$ProjectName.runtimeconfig.json",
        "appsettings.json"
    )
    
    $missing = @()
    foreach ($file in $requiredFiles) {
        if (!(Test-Path "$PublishDirectory/$file")) {
            $missing += $file
        }
    }
    
    if ($missing.Count -gt 0) {
        throw "Missing files: $($missing -join ', ')"
    }
    return $true
} -SuccessMessage "All required files present"

Test-DeployCheck "Build artifacts size" {
    $size = Get-DirectorySize -Path $PublishDirectory
    $sizeMB = [math]::Round($size / 1MB, 2)
    
    Write-Host "    Size: $sizeMB MB" -ForegroundColor Gray
    
    if ($size -gt $config.MaxDeploymentSize) {
        $maxMB = [math]::Round($config.MaxDeploymentSize / 1MB, 2)
        throw "Deployment size ($sizeMB MB) exceeds recommended maximum ($maxMB MB)"
    }
    return $true
} -Critical $false

Test-DeployCheck "appsettings.json is valid JSON" {
    $appSettingsPath = "$PublishDirectory/appsettings.json"
    if (!(Test-JsonValid -FilePath $appSettingsPath)) {
        throw "Invalid JSON syntax in appsettings.json"
    }
    return $true
}

Test-DeployCheck "Environment-specific configuration exists" {
    $envConfigPath = "$PublishDirectory/appsettings.$Environment.json"
    if (Test-Path $envConfigPath) {
        if (!(Test-JsonValid -FilePath $envConfigPath)) {
            throw "Invalid JSON syntax in appsettings.$Environment.json"
        }
        Write-Host "    Found: appsettings.$Environment.json" -ForegroundColor Gray
    } else {
        Write-Host "    Using appsettings.json only" -ForegroundColor Gray
    }
    return $true
}

# ============================================================================
# SECTION 2: CONFIGURATION TOKENS
# ============================================================================
Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host " CONFIGURATION TOKEN VALIDATION" -ForegroundColor Cyan
Write-Host "="*70 -ForegroundColor Cyan

Test-DeployCheck "No unreplaced tokens in appsettings.json" {
    $tokens = Get-TokensInFile -FilePath "$PublishDirectory/appsettings.json"
    
    if ($tokens.Count -gt 0) {
        $uniqueTokens = $tokens | Select-Object -Unique
        throw "Found $($tokens.Count) unreplaced tokens: $($uniqueTokens -join ', ')"
    }
    return $true
} -SuccessMessage "All tokens replaced"

if (Test-Path "$PublishDirectory/appsettings.$Environment.json") {
    Test-DeployCheck "No unreplaced tokens in appsettings.$Environment.json" {
        $tokens = Get-TokensInFile -FilePath "$PublishDirectory/appsettings.$Environment.json"
        
        if ($tokens.Count -gt 0) {
            $uniqueTokens = $tokens | Select-Object -Unique
            throw "Found $($tokens.Count) unreplaced tokens: $($uniqueTokens -join ', ')"
        }
        return $true
    } -SuccessMessage "All environment tokens replaced"
}

Test-DeployCheck "No tokens in web.config / configuration files" {
    $configFiles = Get-ChildItem -Path $PublishDirectory -Filter "*.config" -ErrorAction SilentlyContinue
    
    $filesWithTokens = @()
    foreach ($file in $configFiles) {
        $tokens = Get-TokensInFile -FilePath $file.FullName
        if ($tokens.Count -gt 0) {
            $filesWithTokens += "$($file.Name) ($($tokens.Count) tokens)"
        }
    }
    
    if ($filesWithTokens.Count -gt 0) {
        throw "Found unreplaced tokens in: $($filesWithTokens -join ', ')"
    }
    return $true
} -Critical $false

# ============================================================================
# SECTION 3: SECRETS VALIDATION
# ============================================================================
if (!$SkipSecretValidation) {
    Write-Host "`n" + "="*70 -ForegroundColor Cyan
    Write-Host " SECRETS VALIDATION" -ForegroundColor Cyan
    Write-Host "="*70 -ForegroundColor Cyan
    
    Test-DeployCheck "OpenBao connectivity" {
        try {
            $response = Invoke-WebRequest -Uri "$($config.OpenBaoUrl)/v1/sys/health" -Method Get -SkipCertificateCheck -TimeoutSec 5
            if ($response.StatusCode -ne 200) {
                throw "Health check returned status: $($response.StatusCode)"
            }
            return $true
        } catch {
            throw "Cannot connect to OpenBao: $($_.Exception.Message)"
        }
    }
    
    Test-DeployCheck "OpenBao authentication" {
    if ([string]::IsNullOrEmpty($env:VAULT_TOKEN)) {
        throw "VAULT_TOKEN environment variable not set"
    }
    
    try {
        $env:VAULT_ADDR = $config.OpenBaoUrl
        $output = bao token lookup -namespace=snpsgroup 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Token invalid or expired"
        }
        return $true
    } catch {
        throw $_.Exception.Message
    }
}

Test-DeployCheck "Secrets exist for environment" {
    try {
        $env:VAULT_ADDR = $config.OpenBaoUrl
        $secretPath = "$ProjectName/$($Environment.ToLower())"
        
        $output = bao kv get -namespace=snpsgroup "secret/$secretPath" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Secret path 'secret/$secretPath' not found or not accessible"
        }
        
        Write-Host "    Path: secret/$secretPath" -ForegroundColor Gray
        return $true
    } catch {
        throw $_.Exception.Message
    }
}
    
    Test-DeployCheck "Secrets not expired" {
        try {
            $env:VAULT_ADDR = $config.OpenBaoUrl
            $tokenInfo = bao token lookup -namespace=snpsgroup -format=json 2>&1 | ConvertFrom-Json
            
            $ttl = $tokenInfo.data.ttl
            if ($ttl -lt 3600) {  # Less than 1 hour
                $ttlMinutes = [math]::Round($ttl / 60, 0)
                throw "Token expires in $ttlMinutes minutes (rotate before deployment)"
            }
            
            $ttlHours = [math]::Round($ttl / 3600, 1)
            Write-Host "    Token TTL: $ttlHours hours" -ForegroundColor Gray
            return $true
        } catch {
            throw $_.Exception.Message
        }
    } -Critical $false
}

# ============================================================================
# SECTION 4: TARGET ENVIRONMENT HEALTH
# ============================================================================
if (!$SkipHealthCheck) {
    Write-Host "`n" + "="*70 -ForegroundColor Cyan
    Write-Host " TARGET ENVIRONMENT HEALTH" -ForegroundColor Cyan
    Write-Host "="*70 -ForegroundColor Cyan
    
    $healthUrl = "$($currentEnvConfig.BaseUrl)/$ProjectName/health"
    
    Test-DeployCheck "Current deployment is healthy" {
        try {
            $response = Invoke-WebRequest -Uri $healthUrl -Method Get -TimeoutSec $config.HealthCheckTimeout
            
            if ($response.StatusCode -eq 200) {
                Write-Host "    Status: Healthy" -ForegroundColor Gray
                return $true
            } else {
                throw "Health check returned status: $($response.StatusCode)"
            }
        } catch {
            if ($_.Exception.Message -like "*404*") {
                Write-Host "    No existing deployment (first deployment)" -ForegroundColor Gray
                return $true
            }
            throw "Cannot reach health endpoint: $($_.Exception.Message)"
        }
    } -Critical $false
    
    Test-DeployCheck "Target server has sufficient disk space" {
        # This check requires remote access - implement based on your infrastructure
        # For now, check local disk space where artifacts are
        $drive = (Get-Item $PublishDirectory).PSDrive
        $freeSpace = (Get-PSDrive $drive.Name).Free
        
        if ($freeSpace -lt $config.RequiredDiskSpace) {
            $freeMB = [math]::Round($freeSpace / 1MB, 0)
            $reqMB = [math]::Round($config.RequiredDiskSpace / 1MB, 0)
            throw "Insufficient disk space: $freeMB MB free, need $reqMB MB"
        }
        
        $freeGB = [math]::Round($freeSpace / 1GB, 1)
        Write-Host "    Free space: $freeGB GB" -ForegroundColor Gray
        return $true
    } -Critical $false
}

# ============================================================================
# SECTION 5: BACKUP VERIFICATION
# ============================================================================
if ($BackupRequired) {
    Write-Host "`n" + "="*70 -ForegroundColor Cyan
    Write-Host " BACKUP VERIFICATION" -ForegroundColor Cyan
    Write-Host "="*70 -ForegroundColor Cyan
    
    Test-DeployCheck "Backup directory exists" {
        $backupDir = "./deployment/backups/$ProjectName/$Environment"
        if (!(Test-Path $backupDir)) {
            throw "Backup directory not found: $backupDir (create backup before deployment)"
        }
        return $true
    }
    
    Test-DeployCheck "Recent backup exists" {
        $backupDir = "./deployment/backups/$ProjectName/$Environment"
        $latestBackup = Get-ChildItem -Path $backupDir -Directory | 
            Sort-Object LastWriteTime -Descending | 
            Select-Object -First 1
        
        if ($null -eq $latestBackup) {
            throw "No backups found in $backupDir"
        }
        
        $age = (Get-Date) - $latestBackup.LastWriteTime
        if ($age.TotalDays -gt $config.MaxBackupAge) {
            throw "Latest backup is $([math]::Round($age.TotalDays, 1)) days old (max: $($config.MaxBackupAge) days)"
        }
        
        Write-Host "    Latest backup: $($latestBackup.Name)" -ForegroundColor Gray
        Write-Host "    Age: $([math]::Round($age.TotalHours, 1)) hours" -ForegroundColor Gray
        return $true
    }
    
    Test-DeployCheck "Backup integrity" {
        $backupDir = "./deployment/backups/$ProjectName/$Environment"
        $latestBackup = Get-ChildItem -Path $backupDir -Directory | 
            Sort-Object LastWriteTime -Descending | 
            Select-Object -First 1
        
        $backupManifest = "$($latestBackup.FullName)/manifest.json"
        if (!(Test-Path $backupManifest)) {
            throw "Backup manifest not found: $backupManifest"
        }
        
        if (!(Test-JsonValid -FilePath $backupManifest)) {
            throw "Backup manifest is corrupted (invalid JSON)"
        }
        
        Write-Host "    Backup integrity: OK" -ForegroundColor Gray
        return $true
    }
}

# ============================================================================
# SECTION 6: DEPLOYMENT READINESS
# ============================================================================
Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host " DEPLOYMENT READINESS" -ForegroundColor Cyan
Write-Host "="*70 -ForegroundColor Cyan

Test-DeployCheck "Build configuration matches environment" {
    $depsPath = "$PublishDirectory/$ProjectName.deps.json"
    if (Test-Path $depsPath) {
        $deps = Get-Content $depsPath -Raw | ConvertFrom-Json
        
        # Check for debug symbols in production
        if ($Environment -eq "Production") {
            $hasDebugSymbols = Test-Path "$PublishDirectory/*.pdb"
            if ($hasDebugSymbols) {
                throw "Debug symbols (.pdb) found in Production build (build with Release configuration)"
            }
        }
    }
    return $true
} -Critical $false

Test-DeployCheck "No temporary or test files" {
    $tempPatterns = @("*.tmp", "*.temp", "test*.json", "*-test.json")
    $tempFiles = @()
    
    foreach ($pattern in $tempPatterns) {
        $found = Get-ChildItem -Path $PublishDirectory -Filter $pattern -Recurse -ErrorAction SilentlyContinue
        $tempFiles += $found
    }
    
    if ($tempFiles.Count -gt 0) {
        $fileNames = $tempFiles | ForEach-Object { $_.Name }
        throw "Found temporary files: $($fileNames -join ', ')"
    }
    return $true
} -Critical $false

if ($Environment -eq "Production") {
    Test-DeployCheck "Production approval obtained" {
        if ($currentEnvConfig.RequireApproval) {
            Write-Host "`n    ⚠️  PRODUCTION DEPLOYMENT REQUIRES APPROVAL" -ForegroundColor Yellow
            Write-Host "    Have you obtained approval from the deployment manager? (y/n): " -NoNewline
            $response = Read-Host
            
            if ($response -ne "y") {
                throw "Production deployment approval not confirmed"
            }
        }
        return $true
    } -Critical $true
}

Test-DeployCheck "Git working directory is clean" {
    $status = git status --porcelain 2>&1
    if (![string]::IsNullOrEmpty($status)) {
        throw "Git working directory has uncommitted changes (commit or stash before deployment)"
    }
    return $true
} -Critical $false

Test-DeployCheck "Deployment tagged in Git" {
    $currentCommit = git rev-parse HEAD
    $tags = git tag --points-at HEAD
    
    if ([string]::IsNullOrEmpty($tags)) {
        $shortCommit = $currentCommit.Substring(0, 7)
        throw "Current commit ($shortCommit) is not tagged (create deployment tag: git tag v1.x.x)"
    }
    
    Write-Host "    Tag: $tags" -ForegroundColor Gray
    return $true
} -Critical $false

# ============================================================================
# SECTION 7: DEPENDENCIES
# ============================================================================
Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host " DEPENDENCY VALIDATION" -ForegroundColor Cyan
Write-Host "="*70 -ForegroundColor Cyan

Test-DeployCheck "No vulnerable packages" {
    try {
        $output = dotnet list package --vulnerable --include-transitive 2>&1
        if ($output -match "has the following vulnerable packages") {
            throw "Vulnerable packages detected (run: dotnet list package --vulnerable)"
        }
        return $true
    } catch {
        throw $_.Exception.Message
    }
} -Critical $false

Test-DeployCheck "No deprecated packages" {
    try {
        $output = dotnet list package --deprecated 2>&1
        if ($output -match "has the following deprecated packages") {
            throw "Deprecated packages detected (run: dotnet list package --deprecated)"
        }
        return $true
    } catch {
        throw $_.Exception.Message
    }
} -Critical $false

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host "`n" + "="*70 -ForegroundColor Magenta
Write-Host " VALIDATION SUMMARY" -ForegroundColor Magenta
Write-Host "="*70 -ForegroundColor Magenta

Write-Host "`nResults:" -ForegroundColor Cyan
Write-Host "  ✅ Passed  : $ChecksPassed" -ForegroundColor Green
Write-Host "  ⚠️  Warnings: $ChecksWarning" -ForegroundColor Yellow
Write-Host "  ❌ Failed  : $ChecksFailed" -ForegroundColor Red

if ($ChecksFailed -gt 0) {
    Write-Host "`n❌ CRITICAL FAILURES - DO NOT DEPLOY" -ForegroundColor Red -BackgroundColor Black
    Write-Host "`nThe following critical issues must be fixed before deployment:" -ForegroundColor Red
    foreach ($failure in $script:CriticalFailures) {
        Write-Host "  • $failure" -ForegroundColor Red
    }
    exit 1
    
} elseif ($ChecksWarning -gt 0) {
    Write-Host "`n⚠️  WARNINGS PRESENT - REVIEW BEFORE DEPLOYING" -ForegroundColor Yellow -BackgroundColor Black
    Write-Host "`nThe following warnings were detected:" -ForegroundColor Yellow
    foreach ($warning in $script:Warnings) {
        Write-Host "  • $warning" -ForegroundColor Yellow
    }
    Write-Host "`nContinue with deployment? (y/n): " -NoNewline
    $response = Read-Host
    if ($response -ne "y") {
        Write-Host "`n⏹️  Deployment cancelled by user" -ForegroundColor Yellow
        exit 2
    }
    Write-Host "`n✅ Proceeding with deployment (warnings acknowledged)" -ForegroundColor Green
    exit 0
    
} else {
    Write-Host "`n✅ ALL CHECKS PASSED - SAFE TO DEPLOY" -ForegroundColor Green -BackgroundColor Black
    Write-Host "`nEnvironment  : $Environment" -ForegroundColor Cyan
    Write-Host "Project      : $ProjectName" -ForegroundColor Cyan
    Write-Host "Artifacts    : $PublishDirectory" -ForegroundColor Cyan
    Write-Host "Target       : $($currentEnvConfig.BaseUrl)" -ForegroundColor Cyan
    Write-Host "`nYou may proceed with deployment." -ForegroundColor Green
    exit 0
}
