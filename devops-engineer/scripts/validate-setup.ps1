<#
.SYNOPSIS
    Validate deployment prerequisites and configuration

.DESCRIPTION
    Comprehensive validation of environment setup including:
    - Required tools (.NET SDK, Git, NUKE, PowerShell)
    - OpenBao connectivity and authentication
    - Azure DevOps access
    - Directory structure
    - Template customization status

.PARAMETER Environment
    Target environment to validate (Development, Staging, Production)

.PARAMETER ValidateOpenBao
    Validate OpenBao connectivity (default: true)

.PARAMETER ValidateAzureDevOps
    Validate Azure DevOps access (default: true)

.PARAMETER ProjectName
    Project name for environment-specific validation

.EXAMPLE
    .\validate-setup.ps1

.EXAMPLE
    .\validate-setup.ps1 -Environment "Production" -ProjectName "OrderService"
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Development", "Staging", "Production", "")]
    [string]$Environment = "",
    
    [Parameter(Mandatory=$false)]
    [bool]$ValidateOpenBao = $true,
    
    [Parameter(Mandatory=$false)]
    [bool]$ValidateAzureDevOps = $true,
    
    [Parameter(Mandatory=$false)]
    [string]$ProjectName = ""
)

#Requires -Version 7.0

$ErrorActionPreference = "Stop"

$script:ValidationsPassed = 0
$script:ValidationsFailed = 0
$script:ValidationsWarning = 0

function Test-Validation {
    param(
        [string]$Name,
        [scriptblock]$Test,
        [bool]$Critical = $true
    )
    
    Write-Host "`n▶ Validating: $Name" -ForegroundColor Cyan
    
    try {
        $result = & $Test
        if ($result -eq $false) {
            throw "Validation returned false"
        }
        Write-Host "  ✅ PASS" -ForegroundColor Green
        $script:ValidationsPassed++
        return $true
    } catch {
        if ($Critical) {
            Write-Host "  ❌ FAIL: $($_.Exception.Message)" -ForegroundColor Red
            $script:ValidationsFailed++
        } else {
            Write-Host "  ⚠️  WARNING: $($_.Exception.Message)" -ForegroundColor Yellow
            $script:ValidationsWarning++
        }
        return $false
    }
}

# ============================================================================
# TOOLS VALIDATION
# ============================================================================
Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host " PREREQUISITES VALIDATION" -ForegroundColor Cyan
Write-Host "="*70 -ForegroundColor Cyan

# .NET SDK
Test-Validation ".NET SDK 9.0+" {
    $version = dotnet --version
    if ([version]$version -lt [version]"9.0") {
        throw "Version $version is too old (need 9.0+)"
    }
    Write-Host "    Version: $version" -ForegroundColor Gray
    return $true
} -Critical $true

# Git
Test-Validation "Git" {
    $version = git --version
    $gitConfig = git config --global user.name
    if ([string]::IsNullOrEmpty($gitConfig)) {
        throw "Git not configured (run: git config --global user.name 'Your Name')"
    }
    Write-Host "    Configured for: $gitConfig" -ForegroundColor Gray
    return $true
} -Critical $true

# NUKE GlobalTool
Test-Validation "NUKE GlobalTool" {
    $output = nuke --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Not installed (run: dotnet tool install Nuke.GlobalTool --global)"
    }
    Write-Host "    Installed" -ForegroundColor Gray
    return $true
} -Critical $true

# PowerShell Version
Test-Validation "PowerShell 7.0+" {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "Version $($PSVersionTable.PSVersion) is too old (need 7.0+)"
    }
    Write-Host "    Version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
    return $true
} -Critical $false

# ============================================================================
# DIRECTORY STRUCTURE VALIDATION
# ============================================================================
Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host " DIRECTORY STRUCTURE" -ForegroundColor Cyan
Write-Host "="*70 -ForegroundColor Cyan

$requiredDirs = @(
    "build",
    "build/Helpers",
    "config",
    "deployment/scripts"
)

foreach ($dir in $requiredDirs) {
    Test-Validation "Directory: $dir" {
        if (!(Test-Path $dir)) {
            throw "Missing (run: init-project.ps1)"
        }
        return $true
    } -Critical $true
}

# ============================================================================
# FILES VALIDATION
# ============================================================================
Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host " REQUIRED FILES" -ForegroundColor Cyan
Write-Host "="*70 -ForegroundColor Cyan

$requiredFiles = @{
    "build/Build.cs" = "NUKE build definition"
    "build/Helpers/OpenBaoHelper.cs" = "OpenBao integration"
    "build/Helpers/ConfigHelper.cs" = "Configuration helper"
    "build/Helpers/DeploymentHelper.cs" = "Deployment helper"
    "build/Helpers/HealthCheckHelper.cs" = "Health check helper"
    "config/appsettings.json" = "Base configuration"
    "global.json" = ".NET SDK version pinning"
}

foreach ($file in $requiredFiles.GetEnumerator()) {
    Test-Validation "File: $($file.Key)" {
        if (!(Test-Path $file.Key)) {
            throw "Missing - $($file.Value)"
        }
        return $true
    } -Critical $true
}

# ============================================================================
# PLACEHOLDER VALIDATION
# ============================================================================
Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host " PLACEHOLDER CUSTOMIZATION" -ForegroundColor Cyan
Write-Host "="*70 -ForegroundColor Cyan

$filesToCheck = @(
    "build/Build.cs",
    "config/appsettings.json"
)

foreach ($file in $filesToCheck) {
    if (!(Test-Path $file)) { continue }
    
    Test-Validation "Placeholders in: $file" {
        $content = Get-Content $file -Raw
        $placeholders = [regex]::Matches($content, '\{(ProjectName|SolutionName|Namespace)\}')
        
        if ($placeholders.Count -gt 0) {
            $foundPlaceholders = $placeholders | ForEach-Object { $_.Value } | Select-Object -Unique
            throw "Found unreplaced: $($foundPlaceholders -join ', ')"
        }
        Write-Host "    All placeholders replaced" -ForegroundColor Gray
        return $true
    } -Critical $false
}

# ============================================================================
# OPENBAO VALIDATION
# ============================================================================
if ($ValidateOpenBao) {
    Write-Host "`n" + "="*70 -ForegroundColor Cyan
    Write-Host " OPENBAO CONNECTIVITY" -ForegroundColor Cyan
    Write-Host "="*70 -ForegroundColor Cyan
    
    $openBaoUrl = $env:OPENBAO_URL
    if ([string]::IsNullOrEmpty($openBaoUrl)) {
        $openBaoUrl = "https://keyvault.snpsgroup.com:8200"
    }
    
    Test-Validation "OpenBao URL: $openBaoUrl" {
        try {
            $response = Invoke-WebRequest -Uri "$openBaoUrl/v1/sys/health" -Method Get -SkipCertificateCheck -TimeoutSec 5
            if ($response.StatusCode -eq 200) {
                Write-Host "    Status: Healthy" -ForegroundColor Gray
                return $true
            }
        } catch {
            throw "Not accessible: $($_.Exception.Message)"
        }
    } -Critical $false
    
    # Validate bao CLI
    Test-Validation "OpenBao CLI" {
    try {
        $output = bao --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Not installed (download from https://openbao.org)"
        }
        Write-Host "    Installed" -ForegroundColor Gray
        return $true
    } catch {
        throw $_.Exception.Message
    }
} -Critical $false

# Validate authentication (if token exists)
if (![string]::IsNullOrEmpty($env:VAULT_TOKEN)) {
    Test-Validation "OpenBao Authentication" {
        try {
            $env:VAULT_ADDR = $openBaoUrl
            $output = bao token lookup -namespace=snpsgroup 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Token invalid or expired"
            }
            Write-Host "    Authenticated" -ForegroundColor Gray
            return $true
        } catch {
            throw $_.Exception.Message
        }
    } -Critical $false
}
}

# ============================================================================
# AZURE DEVOPS VALIDATION
# ============================================================================
if ($ValidateAzureDevOps) {
    Write-Host "`n" + "="*70 -ForegroundColor Cyan
    Write-Host " AZURE DEVOPS" -ForegroundColor Cyan
    Write-Host "="*70 -ForegroundColor Cyan
    
    Test-Validation "Azure CLI" {
        try {
            $output = az --version 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Not installed (download from https://aka.ms/InstallAzureCLIDeb)"
            }
            Write-Host "    Installed" -ForegroundColor Gray
            return $true
        } catch {
            throw $_.Exception.Message
        }
    } -Critical $false
    
    Test-Validation "Azure DevOps Extension" {
        try {
            $extensions = az extension list --output json | ConvertFrom-Json
            $devopsExt = $extensions | Where-Object { $_.name -eq "azure-devops" }
            if ($null -eq $devopsExt) {
                throw "Extension not installed (run: az extension add --name azure-devops)"
            }
            Write-Host "    Extension installed" -ForegroundColor Gray
            return $true
        } catch {
            throw $_.Exception.Message
        }
    } -Critical $false
    
    # Check if logged in
    Test-Validation "Azure DevOps Login" {
        try {
            $account = az account show 2>&1 | ConvertFrom-Json
            if ($null -eq $account) {
                throw "Not logged in (run: az login)"
            }
            Write-Host "    Logged in as: $($account.user.name)" -ForegroundColor Gray
            return $true
        } catch {
            throw "Not logged in (run: az login)"
        }
    } -Critical $false
}

# ============================================================================
# BUILD VALIDATION
# ============================================================================
if (Test-Path "build/Build.cs") {
    Write-Host "`n" + "="*70 -ForegroundColor Cyan
    Write-Host " BUILD SYSTEM" -ForegroundColor Cyan
    Write-Host "="*70 -ForegroundColor Cyan
    
    Test-Validation "Build.cs Compilation" {
        try {
            if (!(Test-Path "build/_build.csproj")) {
                throw "NUKE project not initialized (run: nuke :setup)"
            }
            
            $output = dotnet build build/_build.csproj --nologo --verbosity quiet 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Compilation failed: $output"
            }
            Write-Host "    Build.cs compiles successfully" -ForegroundColor Gray
            return $true
        } catch {
            throw $_.Exception.Message
        }
    } -Critical $true
    
    Test-Validation "NUKE Targets" {
        try {
            $output = nuke --help 2>&1
            $targets = @("Clean", "Restore", "Compile", "Test", "Publish")
            $missingTargets = @()
            
            foreach ($target in $targets) {
                if ($output -notmatch $target) {
                    $missingTargets += $target
                }
            }
            
            if ($missingTargets.Count -gt 0) {
                throw "Missing targets: $($missingTargets -join ', ')"
            }
            Write-Host "    All essential targets present" -ForegroundColor Gray
            return $true
        } catch {
            throw $_.Exception.Message
        }
    } -Critical $false
}

# ============================================================================
# ENVIRONMENT-SPECIFIC VALIDATION
# ============================================================================
if (![string]::IsNullOrEmpty($Environment) -and ![string]::IsNullOrEmpty($ProjectName)) {
    Write-Host "`n" + "="*70 -ForegroundColor Cyan
    Write-Host " ENVIRONMENT: $Environment" -ForegroundColor Cyan
    Write-Host "="*70 -ForegroundColor Cyan
    
    # Check OpenBao secrets exist
    if ($ValidateOpenBao -and ![string]::IsNullOrEmpty($env:VAULT_TOKEN)) {
        Test-Validation "OpenBao Secrets Path" {
            try {
                $env:VAULT_ADDR = if ([string]::IsNullOrEmpty($env:OPENBAO_URL)) { "https://keyvault.snpsgroup.com:8200" } else { $env:OPENBAO_URL }
                $secretPath = "$ProjectName/$($Environment.ToLower())"
                
                $output = bao kv get -namespace=snpsgroup "secret/$secretPath" 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "Secret path 'secret/$secretPath' not found or not accessible"
                }
                Write-Host "    Secrets accessible at: secret/$secretPath" -ForegroundColor Gray
                return $true
            } catch {
                throw $_.Exception.Message
            }
        } -Critical $false
    }
    
    # Check Azure DevOps Variable Group
    if ($ValidateAzureDevOps) {
        Test-Validation "Azure DevOps Variable Group" {
            try {
                $groupName = "$ProjectName-$Environment-Secrets"
                $groups = az pipelines variable-group list --project $ProjectName --output json 2>&1 | ConvertFrom-Json
                $group = $groups | Where-Object { $_.name -eq $groupName }
                
                if ($null -eq $group) {
                    throw "Variable group '$groupName' not found"
                }
                Write-Host "    Variable group exists: $groupName" -ForegroundColor Gray
                return $true
            } catch {
                throw $_.Exception.Message
            }
        } -Critical $false
    }
}

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host " VALIDATION SUMMARY" -ForegroundColor Cyan
Write-Host "="*70 -ForegroundColor Cyan

Write-Host "`nResults:" -ForegroundColor Cyan
Write-Host "  ✅ Passed  : $ValidationsPassed" -ForegroundColor Green
Write-Host "  ⚠️  Warnings: $ValidationsWarning" -ForegroundColor Yellow
Write-Host "  ❌ Failed  : $ValidationsFailed" -ForegroundColor Red

if ($ValidationsFailed -gt 0) {
    Write-Host "`n❌ VALIDATION FAILED" -ForegroundColor Red
    Write-Host "   Fix critical issues before proceeding" -ForegroundColor Red
    exit 1
} elseif ($ValidationsWarning -gt 0) {
    Write-Host "`n⚠️  VALIDATION PASSED WITH WARNINGS" -ForegroundColor Yellow
    Write-Host "   Review warnings above - some features may not work" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "`n✅ ALL VALIDATIONS PASSED" -ForegroundColor Green
    Write-Host "   System is ready for deployment!" -ForegroundColor Green
    exit 0
}
