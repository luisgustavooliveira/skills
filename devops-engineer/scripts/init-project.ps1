<#
.SYNOPSIS
    Initialize a new .NET project with SnpsGroup deployment structure

.DESCRIPTION
    This script automates the setup of a new .NET project with:
    - Standard directory structure
    - NUKE build system
    - Templates copied and customized
    - Git initialization
    - Pre-requisites validation

.PARAMETER ProjectName
    Name of the project (e.g., "MyProject")

.PARAMETER SolutionPath
    Path to the .sln file (auto-detected if not provided)

.PARAMETER Namespace
    Root namespace (default: "SnpsGroup.{ProjectName}")

.PARAMETER DeploymentDocsPath
    Path to deployment-docs directory

.PARAMETER CreateGit
    Initialize git repository (default: true)

.PARAMETER DryRun
    Preview changes without executing (default: false)

.EXAMPLE
    .\init-project.ps1 -ProjectName "OrderService"

.EXAMPLE
    .\init-project.ps1 -ProjectName "OrderService" -Namespace "Company.Services.OrderService" -DryRun $true
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName,
    
    [Parameter(Mandatory=$false)]
    [string]$SolutionPath,
    
    [Parameter(Mandatory=$false)]
    [string]$Namespace,
    
    [Parameter(Mandatory=$false)]
    [string]$DeploymentDocsPath = "../deployment-docs",
    
    [Parameter(Mandatory=$false)]
    [bool]$CreateGit = $true,
    
    [Parameter(Mandatory=$false)]
    [bool]$DryRun = $false
)

#Requires -Version 7.0

$ErrorActionPreference = "Stop"

# Colors
$ColorInfo = "Cyan"
$ColorSuccess = "Green"
$ColorWarning = "Yellow"
$ColorError = "Red"

function Write-Step {
    param([string]$Message)
    Write-Host "`n▶ $Message" -ForegroundColor $ColorInfo
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✅ $Message" -ForegroundColor $ColorSuccess
}

function Write-Warning {
    param([string]$Message)
    Write-Host "  ⚠️  $Message" -ForegroundColor $ColorWarning
}

function Write-Error {
    param([string]$Message)
    Write-Host "  ❌ $Message" -ForegroundColor $ColorError
}

# ============================================================================
# STEP 1: Validate Prerequisites
# ============================================================================
Write-Step "Validating prerequisites..."

# Check .NET SDK
try {
    $dotnetVersion = dotnet --version
    if ([version]$dotnetVersion -lt [version]"9.0") {
        throw ".NET SDK 9.0+ required, found: $dotnetVersion"
    }
    Write-Success ".NET SDK $dotnetVersion"
} catch {
    Write-Error "$ NET SDK not found or version too old"
    exit 1
}

# Check Git
try {
    $gitVersion = git --version
    Write-Success "Git installed"
} catch {
    Write-Error "Git not found - install from https://git-scm.com"
    exit 1
}

# Check NUKE
try {
    $nukeVersion = nuke --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "NUKE not installed"
    }
    Write-Success "NUKE GlobalTool installed"
} catch {
    Write-Warning "NUKE not installed, will install it..."
    if (!$DryRun) {
        dotnet tool install Nuke.GlobalTool --global
        Write-Success "NUKE GlobalTool installed"
    }
}

# Check deployment-docs path
if (!(Test-Path $DeploymentDocsPath)) {
    Write-Error "Deployment docs not found at: $DeploymentDocsPath"
    exit 1
}
Write-Success "Deployment docs found"

# ============================================================================
# STEP 2: Detect Solution File
# ============================================================================
Write-Step "Detecting solution file..."

if ([string]::IsNullOrEmpty($SolutionPath)) {
    $slnFiles = Get-ChildItem -Filter "*.sln" -ErrorAction SilentlyContinue
    
    if ($slnFiles.Count -eq 0) {
        Write-Warning "No .sln file found in current directory"
        $SolutionPath = "$ProjectName.sln"
        Write-Warning "Will use: $SolutionPath"
    } elseif ($slnFiles.Count -eq 1) {
        $SolutionPath = $slnFiles[0].FullName
        Write-Success "Detected: $SolutionPath"
    } else {
        Write-Warning "Multiple .sln files found:"
        $slnFiles | ForEach-Object { Write-Host "  - $($_.Name)" }
        $SolutionPath = Read-Host "Enter solution file name"
    }
} else {
    if (!(Test-Path $SolutionPath)) {
        Write-Error "Solution file not found: $SolutionPath"
        exit 1
    }
    Write-Success "Using: $SolutionPath"
}

$SolutionName = [System.IO.Path]::GetFileNameWithoutExtension($SolutionPath)

# ============================================================================
# STEP 3: Set Default Namespace
# ============================================================================
if ([string]::IsNullOrEmpty($Namespace)) {
    $Namespace = "SnpsGroup.$ProjectName"
    Write-Success "Using namespace: $Namespace"
}

# ============================================================================
# STEP 4: Create Directory Structure
# ============================================================================
Write-Step "Creating directory structure..."

$directories = @(
    "build",
    "build/Helpers",
    "build/Targets",
    "config",
    "deployment/docker",
    "deployment/kubernetes",
    "deployment/scripts",
    "docs",
    ".azure/pipelines",
    ".azure/pipelines/templates",
    ".azure/pipelines/variables"
)

foreach ($dir in $directories) {
    if ($DryRun) {
        Write-Host "  [DRY RUN] Would create: $dir"
    } else {
        if (!(Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Success "Created: $dir"
        } else {
            Write-Warning "Already exists: $dir"
        }
    }
}

# ============================================================================
# STEP 5: Copy Templates
# ============================================================================
Write-Step "Copying templates..."

$templateMappings = @{
    "$DeploymentDocsPath/templates/nuke/Build.cs.template" = "build/Build.cs"
    "$DeploymentDocsPath/templates/nuke/Helpers/OpenBaoHelper.cs" = "build/Helpers/OpenBaoHelper.cs"
    "$DeploymentDocsPath/templates/nuke/Helpers/ConfigHelper.cs" = "build/Helpers/ConfigHelper.cs"
    "$DeploymentDocsPath/templates/nuke/Helpers/DeploymentHelper.cs" = "build/Helpers/DeploymentHelper.cs"
    "$DeploymentDocsPath/templates/nuke/Helpers/HealthCheckHelper.cs" = "build/Helpers/HealthCheckHelper.cs"
    "$DeploymentDocsPath/templates/pipeline/azure-pipelines.yml.template" = "azure-pipelines.yml"
    "$DeploymentDocsPath/templates/configs/appsettings.json.template" = "config/appsettings.json"
    "$DeploymentDocsPath/templates/configs/appsettings.Development.json.template" = "config/appsettings.Development.json"
    "$DeploymentDocsPath/templates/configs/appsettings.Production.json.template" = "config/appsettings.Production.json"
    "$DeploymentDocsPath/templates/scripts/migrate-secrets-template.ps1" = "deployment/scripts/migrate-secrets.ps1"
}

foreach ($mapping in $templateMappings.GetEnumerator()) {
    $source = $mapping.Key
    $destination = $mapping.Value
    
    if (!(Test-Path $source)) {
        Write-Warning "Template not found: $source"
        continue
    }
    
    if ($DryRun) {
        Write-Host "  [DRY RUN] Would copy: $source → $destination"
    } else {
        if (Test-Path $destination) {
            Write-Warning "Already exists, skipping: $destination"
        } else {
            Copy-Item -Path $source -Destination $destination -Force
            Write-Success "Copied: $destination"
        }
    }
}

# ============================================================================
# STEP 6: Substitute Placeholders
# ============================================================================
Write-Step "Substituting placeholders..."

$placeholders = @{
    "{ProjectName}" = $ProjectName
    "{SolutionName}" = $SolutionName
    "{Namespace}" = $Namespace
}

$filesToProcess = @(
    "build/Build.cs",
    "azure-pipelines.yml",
    "config/appsettings.json",
    "config/appsettings.Development.json",
    "config/appsettings.Production.json",
    "deployment/scripts/migrate-secrets.ps1"
)

foreach ($file in $filesToProcess) {
    if (!(Test-Path $file)) {
        Write-Warning "File not found for substitution: $file"
        continue
    }
    
    if ($DryRun) {
        Write-Host "  [DRY RUN] Would substitute placeholders in: $file"
        continue
    }
    
    try {
        $content = Get-Content $file -Raw -ErrorAction Stop
        $originalContent = $content
        
        foreach ($placeholder in $placeholders.GetEnumerator()) {
            $content = $content -replace [regex]::Escape($placeholder.Key), $placeholder.Value
        }
        
        if ($content -ne $originalContent) {
            Set-Content -Path $file -Value $content -NoNewline
            Write-Success "Updated: $file"
        } else {
            Write-Host "  ℹ️  No placeholders found in: $file" -ForegroundColor Gray
        }
    } catch {
        Write-Warning "Could not process file: $file - $($_.Exception.Message)"
    }
}

# ============================================================================
# STEP 7: Initialize NUKE (if Build.cs exists)
# ============================================================================
if ((Test-Path "build/Build.cs") -and !$DryRun) {
    Write-Step "Setting up NUKE..."
    
    # Create global.json if it doesn't exist
    if (!(Test-Path "global.json")) {
        @"
{
  "sdk": {
    "version": "9.0.100",
    "rollForward": "latestMinor"
  }
}
"@ | Set-Content "global.json"
        Write-Success "Created global.json"
    }
    
    # Create build scripts if they don't exist
    if (!(Test-Path "build.cmd")) {
        @"
@echo off
dotnet run --project build/_build.csproj -- %*
"@ | Set-Content "build.cmd"
        Write-Success "Created build.cmd"
    }
    
    if (!(Test-Path "build.sh")) {
        @"
#!/bin/bash
dotnet run --project build/_build.csproj -- `$@
"@ | Set-Content "build.sh"
        chmod +x build.sh 2>$null
        Write-Success "Created build.sh"
    }
}

# ============================================================================
# STEP 8: Initialize Git
# ============================================================================
if ($CreateGit -and !$DryRun) {
    if (!(Test-Path ".git")) {
        Write-Step "Initializing Git repository..."
        
        git init
        Write-Success "Git initialized"
        
        # Create .gitignore
        if (!(Test-Path ".gitignore")) {
            @"
# Build outputs
**/bin/
**/obj/
artifacts/
**/publish/

# IDE
.vs/
.vscode/
*.user
*.suo

# NUKE
.tmp/

# Secrets (NEVER commit these!)
**/appsettings.*.json
!**/appsettings.json
!**/*.template
deployment/scripts/migrate-secrets.ps1
*.secret

# OS
.DS_Store
Thumbs.db
"@ | Set-Content ".gitignore"
            Write-Success "Created .gitignore"
        }
        
        git add .gitignore
        git commit -m "chore: initial commit - project structure" --quiet
        Write-Success "Initial commit created"
    } else {
        Write-Warning "Git already initialized"
    }
}

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host "`n" + "="*70 -ForegroundColor $ColorInfo
Write-Host " 🎉 PROJECT INITIALIZATION COMPLETE" -ForegroundColor $ColorSuccess
Write-Host "="*70 -ForegroundColor $ColorInfo

Write-Host "`nProject Details:" -ForegroundColor $ColorInfo
Write-Host "  Project Name : $ProjectName"
Write-Host "  Solution     : $SolutionName"
Write-Host "  Namespace    : $Namespace"

if ($DryRun) {
    Write-Host "`n⚠️  This was a DRY RUN - no files were modified" -ForegroundColor $ColorWarning
    Write-Host "   Run without -DryRun parameter to apply changes" -ForegroundColor $ColorWarning
} else {
    Write-Host "`nNext Steps:" -ForegroundColor $ColorInfo
    Write-Host "  1. Review generated files"
    Write-Host "  2. Customize build/Build.cs for your project needs"
    Write-Host "  3. Configure OpenBao secrets: deployment/scripts/migrate-secrets.ps1"
    Write-Host "  4. Test local build: ./build.cmd Compile Test"
    Write-Host "  5. Commit changes: git add . && git commit -m 'feat: add deployment structure'"
    Write-Host "  6. Setup Azure DevOps pipeline"
    Write-Host ""
    Write-Host "📖 Documentation: See deployment-docs/README.md for detailed guide" -ForegroundColor $ColorInfo
}

Write-Host ""
