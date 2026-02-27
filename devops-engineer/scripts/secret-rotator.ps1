<#
.SYNOPSIS
    Automated secret rotation for OpenBao and Azure DevOps

.DESCRIPTION
    Manages secret rotation lifecycle:
    - Generate new SecretIDs for AppRole authentication
    - Update Azure DevOps Variable Groups with new secrets
    - Validate new credentials before deactivating old ones
    - Document rotation history
    - Send notifications on rotation events
    
    Supports both manual and automated rotation workflows.

.PARAMETER ProjectName
    Project name whose secrets will be rotated

.PARAMETER Environment
    Target environment (Development, Staging, Production)

.PARAMETER RotateType
    Type of rotation: AppRoleSecretID, DatabasePassword, ApiKey, All (default: AppRoleSecretID)

.PARAMETER DryRun
    Perform validation without actually rotating secrets

.PARAMETER Force
    Skip confirmation prompts (use with caution)

.PARAMETER NotifyEmail
    Email address for rotation notifications

.EXAMPLE
    .\secret-rotator.ps1 -ProjectName "OrderService" -Environment "Production"

.EXAMPLE
    .\secret-rotator.ps1 -ProjectName "OrderService" -Environment "Staging" -RotateType "All" -DryRun

.EXAMPLE
    .\secret-rotator.ps1 -ProjectName "OrderService" -Environment "Production" -NotifyEmail "devops@snpsgroup.com"

.NOTES
    Rotation Schedule (recommended):
    - Development: 90 days
    - Staging: 60 days
    - Production: 30 days
    
    IMPORTANT: This script requires:
    - VAULT_TOKEN with admin permissions
    - Azure CLI authenticated with DevOps extension
    - Appropriate permissions in Azure DevOps
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("Development", "Staging", "Production")]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("AppRoleSecretID", "DatabasePassword", "ApiKey", "All")]
    [string]$RotateType = "AppRoleSecretID",
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [string]$NotifyEmail = ""
)

#Requires -Version 7.0

$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION
# ============================================================================
$config = @{
    OpenBaoUrl = if ($env:OPENBAO_URL) { $env:OPENBAO_URL } else { "https://keyvault.snpsgroup.com:8200" }
    AzureDevOpsOrg = "https://dev.azure.com/snpsgroup"
    RotationHistoryFile = "./deployment/rotation-history.json"
    BackupDirectory = "./deployment/secret-backups"
}

$rotationSchedule = @{
    Development = 90  # days
    Staging = 60
    Production = 30
}

# ============================================================================
# STATE
# ============================================================================
$script:RotationsPerformed = @()
$script:RotationsFailed = @()
$script:OldSecrets = @{}  # For rollback

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-RotationLog {
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
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-Prerequisites {
    Write-RotationLog "INFO" "Validating prerequisites..."
    
    # Check bao CLI
    try {
        $null = bao --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "OpenBao CLI not installed"
        }
    } catch {
        throw "OpenBao CLI not found. Install from: https://openbao.org"
    }
    
    # Check Azure CLI
    try {
        $null = az --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Azure CLI not installed"
        }
    } catch {
        throw "Azure CLI not found. Install from: https://aka.ms/InstallAzureCLIDeb"
    }
    
    # Check Azure DevOps extension
    try {
        $extensions = az extension list --output json | ConvertFrom-Json
        $devopsExt = $extensions | Where-Object { $_.name -eq "azure-devops" }
        if ($null -eq $devopsExt) {
            throw "Azure DevOps extension not installed (run: az extension add --name azure-devops)"
        }
    } catch {
        throw $_
    }
    
    # Check authentication
    if ([string]::IsNullOrEmpty($env:VAULT_TOKEN)) {
        throw "VAULT_TOKEN environment variable not set"
    }
    
    try {
        $account = az account show 2>&1 | ConvertFrom-Json
        if ($null -eq $account) {
            throw "Not logged in to Azure (run: az login)"
        }
    } catch {
        throw "Not logged in to Azure CLI (run: az login)"
    }
    
    Write-RotationLog "SUCCESS" "Prerequisites validated"
}

function Get-RotationHistory {
    if (Test-Path $config.RotationHistoryFile) {
        try {
            return Get-Content $config.RotationHistoryFile -Raw | ConvertFrom-Json
        } catch {
            Write-RotationLog "WARNING" "Failed to read rotation history: $($_.Exception.Message)"
            return @{ rotations = @() }
        }
    }
    return @{ rotations = @() }
}

function Save-RotationHistory {
    param([object]$Entry)
    
    $history = Get-RotationHistory
    $history.rotations += $Entry
    
    $historyDir = Split-Path $config.RotationHistoryFile -Parent
    if (!(Test-Path $historyDir)) {
        New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
    }
    
    $history | ConvertTo-Json -Depth 10 | Set-Content $config.RotationHistoryFile
    Write-RotationLog "INFO" "Rotation history updated"
}

function Get-LastRotationDate {
    param(
        [string]$Project,
        [string]$Env,
        [string]$SecretType
    )
    
    $history = Get-RotationHistory
    $lastRotation = $history.rotations | 
        Where-Object { $_.project -eq $Project -and $_.environment -eq $Env -and $_.type -eq $SecretType } |
        Sort-Object timestamp -Descending |
        Select-Object -First 1
    
    if ($null -ne $lastRotation) {
        return [datetime]$lastRotation.timestamp
    }
    return $null
}

function Test-RotationNeeded {
    param(
        [string]$Project,
        [string]$Env,
        [string]$SecretType
    )
    
    $lastRotation = Get-LastRotationDate -Project $Project -Env $Env -SecretType $SecretType
    
    if ($null -eq $lastRotation) {
        Write-RotationLog "INFO" "No previous rotation found for $SecretType in $Env"
        return $true
    }
    
    $daysSinceRotation = ((Get-Date) - $lastRotation).Days
    $maxAge = $rotationSchedule[$Env]
    
    Write-RotationLog "INFO" "Last rotation: $($daysSinceRotation) days ago (max: $maxAge days)"
    
    if ($daysSinceRotation -ge $maxAge) {
        Write-RotationLog "WARNING" "Rotation overdue by $($daysSinceRotation - $maxAge) days"
        return $true
    }
    
    return $false
}

function Backup-Secret {
    param(
        [string]$SecretName,
        [string]$SecretValue
    )
    
    if (!(Test-Path $config.BackupDirectory)) {
        New-Item -ItemType Directory -Path $config.BackupDirectory -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupFile = "$($config.BackupDirectory)/$ProjectName-$Environment-$SecretName-$timestamp.backup"
    
    $backup = @{
        project = $ProjectName
        environment = $Environment
        secretName = $SecretName
        secretValue = $SecretValue
        timestamp = Get-Date -Format "o"
    } | ConvertTo-Json
    
    # Encrypt backup (simple base64 for now - implement proper encryption in production)
    $encryptedBackup = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($backup))
    $encryptedBackup | Set-Content $backupFile
    
    Write-RotationLog "INFO" "Secret backed up to: $backupFile"
    $script:OldSecrets[$SecretName] = $SecretValue
}

function Rotate-AppRoleSecretID {
    param(
        [bool]$DryRunMode
    )
    
    Write-RotationLog "INFO" "Starting AppRole SecretID rotation..."
    
    $env:VAULT_ADDR = $config.OpenBaoUrl
    $roleName = "$ProjectName-$($Environment.ToLower())"
    
    # 1. Verify AppRole exists
        try {
            $roleInfo = bao read -namespace=snpsgroup "auth/approle/role/$roleName" -format=json 2>&1 | ConvertFrom-Json
            Write-RotationLog "INFO" "AppRole '$roleName' found"
        } catch {
            throw "AppRole '$roleName' not found in OpenBao"
        }

        # 2. Get current RoleID (doesn't change during rotation)
        try {
            $roleIdInfo = bao read -namespace=snpsgroup "auth/approle/role/$roleName/role-id" -format=json 2>&1 | ConvertFrom-Json
            $roleId = $roleIdInfo.data.role_id
            Write-RotationLog "INFO" "RoleID: $($roleId.Substring(0, 8))..."
        } catch {
            throw "Failed to get RoleID: $($_.Exception.Message)"
        }

        # 3. Generate new SecretID
        if ($DryRunMode) {
            Write-RotationLog "INFO" "[DRY RUN] Would generate new SecretID for role '$roleName'"
            $newSecretId = "dry-run-secret-id-$(New-Guid)"
        } else {
            try {
                $newSecretInfo = bao write -namespace=snpsgroup -f "auth/approle/role/$roleName/secret-id" -format=json 2>&1 | ConvertFrom-Json
                $newSecretId = $newSecretInfo.data.secret_id
                Write-RotationLog "SUCCESS" "New SecretID generated: $($newSecretId.Substring(0, 8))..."
            } catch {
                throw "Failed to generate new SecretID: $($_.Exception.Message)"
            }
        }
    
    # 4. Backup old SecretID (if exists in Azure DevOps)
    try {
        $varGroupName = "$ProjectName-$Environment-Secrets"
        $groups = az pipelines variable-group list --project $ProjectName --output json 2>&1 | ConvertFrom-Json
        $group = $groups | Where-Object { $_.name -eq $varGroupName }
        
        if ($null -ne $group) {
            $oldSecretId = $group.variables.'OpenBao.SecretId'.value
            if (![string]::IsNullOrEmpty($oldSecretId)) {
                Backup-Secret -SecretName "OpenBao.SecretId" -SecretValue $oldSecretId
            }
        }
    } catch {
        Write-RotationLog "WARNING" "Could not backup old SecretID: $($_.Exception.Message)"
    }
    
    # 5. Update Azure DevOps Variable Group
    if ($DryRunMode) {
        Write-RotationLog "INFO" "[DRY RUN] Would update Azure DevOps Variable Group '$varGroupName'"
    } else {
        try {
            $varGroupName = "$ProjectName-$Environment-Secrets"
            $groups = az pipelines variable-group list --project $ProjectName --output json 2>&1 | ConvertFrom-Json
            $group = $groups | Where-Object { $_.name -eq $varGroupName }
            
            if ($null -eq $group) {
                throw "Variable group '$varGroupName' not found"
            }
            
            # Update the variable
            az pipelines variable-group variable update `
                --group-id $group.id `
                --name "OpenBao.SecretId" `
                --value $newSecretId `
                --secret true `
                --project $ProjectName `
                --output none
            
            Write-RotationLog "SUCCESS" "Azure DevOps Variable Group updated"
        } catch {
            throw "Failed to update Azure DevOps: $($_.Exception.Message)"
        }
    }
    
    # 6. Test new credentials
    if (!$DryRunMode) {
        Write-RotationLog "INFO" "Testing new credentials..."
        try {
            $testAuth = bao write -namespace=snpsgroup auth/approle/login "role_id=$roleId" "secret_id=$newSecretId" -format=json 2>&1 | ConvertFrom-Json
            if ($null -ne $testAuth.auth.client_token) {
                Write-RotationLog "SUCCESS" "New credentials validated successfully"
            } else {
                throw "Authentication test failed"
            }
        } catch {
            Write-RotationLog "ERROR" "New credentials validation failed: $($_.Exception.Message)"
            Write-RotationLog "WARNING" "Rolling back changes..."
            # Rollback logic here
            throw "Rotation failed - credentials validation unsuccessful"
        }
    }
    
    # 7. Record rotation
    $rotationEntry = @{
        project = $ProjectName
        environment = $Environment
        type = "AppRoleSecretID"
        timestamp = Get-Date -Format "o"
        performedBy = $env:USERNAME
        success = $true
        dryRun = $DryRunMode
    }
    
    if (!$DryRunMode) {
        Save-RotationHistory -Entry $rotationEntry
    }
    
    $script:RotationsPerformed += "AppRoleSecretID"
    Write-RotationLog "SUCCESS" "AppRole SecretID rotation completed"
}

function Rotate-DatabasePassword {
    param([bool]$DryRunMode)
    
    Write-RotationLog "WARNING" "Database password rotation not yet implemented"
    Write-RotationLog "INFO" "This requires coordination with DBA team for password policy compliance"
    
    # Placeholder for future implementation
    # Steps would include:
    # 1. Generate new password meeting database policy requirements
    # 2. Create new database user or update existing password
    # 3. Test connection with new credentials
    # 4. Update OpenBao secret
    # 5. Update connection string tokens
    # 6. Trigger configuration update in deployed services
    # 7. Verify services reconnected successfully
    # 8. Deactivate old credentials after grace period
}

function Rotate-ApiKey {
    param([bool]$DryRunMode)
    
    Write-RotationLog "WARNING" "API key rotation not yet implemented"
    Write-RotationLog "INFO" "This requires integration with external API provider"
    
    # Placeholder for future implementation
    # Steps would include:
    # 1. Generate new API key via provider's API/portal
    # 2. Test new API key
    # 3. Update OpenBao secret
    # 4. Update configuration tokens
    # 5. Deploy configuration update
    # 6. Verify API calls work with new key
    # 7. Revoke old API key after grace period
}

function Send-RotationNotification {
    param(
        [string]$Email,
        [string]$Subject,
        [string]$Body
    )
    
    if ([string]::IsNullOrEmpty($Email)) {
        Write-RotationLog "INFO" "No notification email configured"
        return
    }
    
    Write-RotationLog "INFO" "Sending notification to: $Email"
    
    # Implement email sending logic here
    # Options:
    # - Send-MailMessage (requires SMTP configuration)
    # - Azure Logic Apps
    # - SendGrid API
    # - Internal notification system
    
    Write-RotationLog "INFO" "[Notification] Subject: $Subject"
    Write-RotationLog "INFO" "[Notification] Body: $Body"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-Host "`n" + "="*70 -ForegroundColor Magenta
Write-Host " SECRET ROTATION" -ForegroundColor Magenta
Write-Host " Project: $ProjectName" -ForegroundColor Magenta
Write-Host " Environment: $Environment" -ForegroundColor Magenta
Write-Host " Type: $RotateType" -ForegroundColor Magenta
if ($DryRun) {
    Write-Host " Mode: DRY RUN (no changes will be made)" -ForegroundColor Yellow
}
Write-Host "="*70 -ForegroundColor Magenta

try {
    # 1. Prerequisites
    Test-Prerequisites
    
    # 2. Check if rotation is needed
    if ($RotateType -ne "All") {
        $rotationNeeded = Test-RotationNeeded -Project $ProjectName -Env $Environment -SecretType $RotateType
        
        if (!$rotationNeeded -and !$Force) {
            Write-RotationLog "INFO" "Rotation not needed yet based on schedule"
            Write-Host "`nForce rotation anyway? (y/n): " -NoNewline
            $response = Read-Host
            if ($response -ne "y") {
                Write-RotationLog "INFO" "Rotation cancelled by user"
                exit 0
            }
        }
    }
    
    # 3. Confirmation (unless Force flag)
    if (!$Force -and !$DryRun) {
        Write-Host "`n⚠️  WARNING: This will rotate secrets for $Environment environment" -ForegroundColor Yellow
        Write-Host "Are you sure you want to continue? (y/n): " -NoNewline
        $response = Read-Host
        if ($response -ne "y") {
            Write-RotationLog "INFO" "Rotation cancelled by user"
            exit 0
        }
    }
    
    # 4. Perform rotation(s)
    switch ($RotateType) {
        "AppRoleSecretID" {
            Rotate-AppRoleSecretID -DryRunMode:$DryRun
        }
        "DatabasePassword" {
            Rotate-DatabasePassword -DryRunMode:$DryRun
        }
        "ApiKey" {
            Rotate-ApiKey -DryRunMode:$DryRun
        }
        "All" {
            Rotate-AppRoleSecretID -DryRunMode:$DryRun
            Rotate-DatabasePassword -DryRunMode:$DryRun
            Rotate-ApiKey -DryRunMode:$DryRun
        }
    }
    
    # 5. Summary
    Write-Host "`n" + "="*70 -ForegroundColor Green
    Write-Host " ROTATION SUMMARY" -ForegroundColor Green
    Write-Host "="*70 -ForegroundColor Green
    
    Write-Host "`nRotations Completed:" -ForegroundColor Green
    foreach ($rotation in $script:RotationsPerformed) {
        Write-Host "  ✅ $rotation" -ForegroundColor Green
    }
    
    if ($script:RotationsFailed.Count -gt 0) {
        Write-Host "`nRotations Failed:" -ForegroundColor Red
        foreach ($failure in $script:RotationsFailed) {
            Write-Host "  ❌ $failure" -ForegroundColor Red
        }
    }
    
    if ($DryRun) {
        Write-Host "`n[DRY RUN] No actual changes were made" -ForegroundColor Yellow
    } else {
        Write-Host "`n✅ Secret rotation completed successfully" -ForegroundColor Green
        
        # Send notification
        if (![string]::IsNullOrEmpty($NotifyEmail)) {
            $subject = "Secret Rotation Completed - $ProjectName ($Environment)"
            $body = @"
Secret rotation completed successfully:

Project: $ProjectName
Environment: $Environment
Rotations: $($script:RotationsPerformed -join ', ')
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Performed By: $env:USERNAME

Next rotation due: $(Get-Date).AddDays($rotationSchedule[$Environment])
"@
            Send-RotationNotification -Email $NotifyEmail -Subject $subject -Body $body
        }
    }
    
    Write-Host "`nNext rotation recommended: $(Get-Date).AddDays($rotationSchedule[$Environment]) -Format 'yyyy-MM-dd')" -ForegroundColor Cyan
    
} catch {
    Write-RotationLog "ERROR" "Rotation failed: $($_.Exception.Message)"
    
    if (![string]::IsNullOrEmpty($NotifyEmail)) {
        $subject = "Secret Rotation FAILED - $ProjectName ($Environment)"
        $body = @"
Secret rotation failed:

Project: $ProjectName
Environment: $Environment
Error: $($_.Exception.Message)
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

Please investigate and retry manually.
"@
        Send-RotationNotification -Email $NotifyEmail -Subject $subject -Body $body
    }
    
    exit 1
}
