<#
.SYNOPSIS
    Real-time deployment health monitoring dashboard

.DESCRIPTION
    Monitors deployed services across environments providing:
    - Health endpoint status checks
    - Response time monitoring
    - Dependency health validation
    - Resource utilization tracking
    - Recent deployment history
    - Alert generation for anomalies
    
    Displays results in a continuously updated terminal dashboard.

.PARAMETER ProjectName
    Project name to monitor

.PARAMETER Environment
    Environment to monitor (Development, Staging, Production, All)

.PARAMETER RefreshInterval
    Dashboard refresh interval in seconds (default: 10)

.PARAMETER Duration
    Monitoring duration in minutes (0 = infinite, default: 0)

.PARAMETER AlertThresholds
    Enable alert generation for thresholds (default: true)

.PARAMETER ExportLog
    Export monitoring data to JSON log file

.EXAMPLE
    .\health-dashboard.ps1 -ProjectName "OrderService" -Environment "Production"

.EXAMPLE
    .\health-dashboard.ps1 -ProjectName "OrderService" -Environment "All" -RefreshInterval 5

.EXAMPLE
    .\health-dashboard.ps1 -ProjectName "OrderService" -Environment "Production" -ExportLog "./health-log.json"

.NOTES
    Press Ctrl+C to stop monitoring
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Development", "Staging", "Production", "All")]
    [string]$Environment = "All",
    
    [Parameter(Mandatory=$false)]
    [int]$RefreshInterval = 10,
    
    [Parameter(Mandatory=$false)]
    [int]$Duration = 0,  # minutes, 0 = infinite
    
    [Parameter(Mandatory=$false)]
    [bool]$AlertThresholds = $true,
    
    [Parameter(Mandatory=$false)]
    [string]$ExportLog = ""
)

#Requires -Version 7.0

$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION
# ============================================================================
$environments = @{
    Development = @{
        BaseUrl = "http://localhost:5000"
        HealthEndpoint = "/health"
        MetricsEndpoint = "/metrics"
        Color = "Cyan"
    }
    Staging = @{
        BaseUrl = "https://staging.snpsgroup.com"
        HealthEndpoint = "/health"
        MetricsEndpoint = "/metrics"
        Color = "Yellow"
    }
    Production = @{
        BaseUrl = "https://www.snpsgroup.com"
        HealthEndpoint = "/health"
        MetricsEndpoint = "/metrics"
        Color = "Green"
    }
}

$alertThresholds = @{
    ResponseTime = 2000  # ms
    ErrorRate = 5  # percentage
    MemoryUsage = 85  # percentage
    CpuUsage = 80  # percentage
}

# ============================================================================
# STATE
# ============================================================================
$script:MonitoringData = @{
    StartTime = Get-Date
    Checks = 0
    History = @()
    Alerts = @()
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Get-HealthStatus {
    param(
        [string]$Url,
        [int]$Timeout = 5
    )
    
    $result = @{
        Timestamp = Get-Date
        Status = "Unknown"
        ResponseTime = 0
        StatusCode = 0
        Message = ""
        Dependencies = @()
    }
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec $Timeout -ErrorAction Stop
        
        $stopwatch.Stop()
        $result.ResponseTime = $stopwatch.ElapsedMilliseconds
        $result.StatusCode = $response.StatusCode
        
        if ($response.StatusCode -eq 200) {
            $result.Status = "Healthy"
            
            # Parse health check response
            try {
                $healthData = $response.Content | ConvertFrom-Json
                
                # Extract dependency health if available
                if ($healthData.PSObject.Properties.Name -contains "dependencies") {
                    foreach ($dep in $healthData.dependencies.PSObject.Properties) {
                        $result.Dependencies += @{
                            Name = $dep.Name
                            Status = $dep.Value.status
                            ResponseTime = if ($dep.Value.responseTime) { $dep.Value.responseTime } else { 0 }
                        }
                    }
                }
            } catch {
                # Health endpoint doesn't return JSON, that's ok
            }
        } else {
            $result.Status = "Unhealthy"
            $result.Message = "HTTP $($response.StatusCode)"
        }
        
    } catch {
        $result.Status = "Down"
        $result.Message = $_.Exception.Message
        
        if ($_.Exception.Message -like "*404*") {
            $result.Message = "Health endpoint not found (404)"
        } elseif ($_.Exception.Message -like "*timeout*") {
            $result.Message = "Health check timeout"
        } elseif ($_.Exception.Message -like "*connection*") {
            $result.Message = "Cannot connect to service"
        }
    }
    
    return $result
}

function Get-MetricsData {
    param(
        [string]$Url,
        [int]$Timeout = 5
    )
    
    $result = @{
        CpuUsage = 0
        MemoryUsage = 0
        RequestRate = 0
        ErrorRate = 0
    }
    
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec $Timeout -ErrorAction Stop
        
        if ($response.StatusCode -eq 200) {
            # Parse Prometheus-style metrics
            $metrics = $response.Content -split "`n"
            
            foreach ($line in $metrics) {
                if ($line -match '^process_cpu_usage\s+(.+)$') {
                    $result.CpuUsage = [math]::Round([double]$Matches[1] * 100, 2)
                }
                if ($line -match '^process_memory_usage\s+(.+)$') {
                    $result.MemoryUsage = [math]::Round([double]$Matches[1] * 100, 2)
                }
                if ($line -match '^http_requests_total\s+(.+)$') {
                    $result.RequestRate = [double]$Matches[1]
                }
                if ($line -match '^http_errors_total\s+(.+)$') {
                    $result.ErrorRate = [double]$Matches[1]
                }
            }
        }
    } catch {
        # Metrics endpoint not available
    }
    
    return $result
}

function Test-Alerts {
    param([object]$Health, [object]$Metrics, [string]$Env)
    
    if (!$AlertThresholds) { return }
    
    $alerts = @()
    
    # Response time alert
    if ($Health.ResponseTime -gt $alertThresholds.ResponseTime) {
        $alerts += @{
            Severity = "Warning"
            Message = "High response time: $($Health.ResponseTime)ms (threshold: $($alertThresholds.ResponseTime)ms)"
            Environment = $Env
        }
    }
    
    # Memory usage alert
    if ($Metrics.MemoryUsage -gt $alertThresholds.MemoryUsage) {
        $alerts += @{
            Severity = "Critical"
            Message = "High memory usage: $($Metrics.MemoryUsage)% (threshold: $($alertThresholds.MemoryUsage)%)"
            Environment = $Env
        }
    }
    
    # CPU usage alert
    if ($Metrics.CpuUsage -gt $alertThresholds.CpuUsage) {
        $alerts += @{
            Severity = "Warning"
            Message = "High CPU usage: $($Metrics.CpuUsage)% (threshold: $($alertThresholds.CpuUsage)%)"
            Environment = $Env
        }
    }
    
    # Error rate alert
    if ($Metrics.ErrorRate -gt $alertThresholds.ErrorRate) {
        $alerts += @{
            Severity = "Critical"
            Message = "High error rate: $($Metrics.ErrorRate)% (threshold: $($alertThresholds.ErrorRate)%)"
            Environment = $Env
        }
    }
    
    # Service down alert
    if ($Health.Status -eq "Down") {
        $alerts += @{
            Severity = "Critical"
            Message = "Service is DOWN: $($Health.Message)"
            Environment = $Env
        }
    }
    
    foreach ($alert in $alerts) {
        $alert.Timestamp = Get-Date
        $script:MonitoringData.Alerts += $alert
    }
    
    return $alerts
}

function Format-HealthStatus {
    param([string]$Status)
    
    switch ($Status) {
        "Healthy" { return "✅ Healthy" }
        "Unhealthy" { return "⚠️  Unhealthy" }
        "Down" { return "❌ Down" }
        default { return "❓ Unknown" }
    }
}

function Format-ResponseTime {
    param([int]$Ms)
    
    if ($Ms -eq 0) { return "N/A" }
    
    $color = if ($Ms -lt 500) { "Green" }
              elseif ($Ms -lt 1000) { "Yellow" }
              elseif ($Ms -lt 2000) { "Magenta" }
              else { "Red" }
    
    return "$($Ms)ms"
}

function Render-Dashboard {
    param([hashtable]$Data)
    
    Clear-Host
    
    # Header
    Write-Host "`n" + "="*80 -ForegroundColor Cyan
    Write-Host " DEPLOYMENT HEALTH DASHBOARD" -ForegroundColor Cyan
    Write-Host " Project: $ProjectName" -ForegroundColor Cyan
    Write-Host " Monitoring: $(if ($Environment -eq 'All') { 'All Environments' } else { $Environment })" -ForegroundColor Cyan
    Write-Host " Uptime: $([math]::Round(((Get-Date) - $script:MonitoringData.StartTime).TotalMinutes, 1)) minutes" -ForegroundColor Cyan
    Write-Host " Last Update: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "="*80 -ForegroundColor Cyan
    
    # Environment Health
    foreach ($envName in $Data.Keys | Sort-Object) {
        $envData = $Data[$envName]
        $envColor = $environments[$envName].Color
        
        Write-Host "`n┌─ $envName " -NoNewline -ForegroundColor $envColor
        Write-Host ("─" * (75 - $envName.Length)) -ForegroundColor $envColor
        
        # Health Status
        $statusIcon = Format-HealthStatus -Status $envData.Health.Status
        Write-Host "│ Status       : " -NoNewline -ForegroundColor $envColor
        Write-Host $statusIcon -NoNewline
        if ($envData.Health.Status -ne "Healthy") {
            Write-Host " ($($envData.Health.Message))" -ForegroundColor Red
        } else {
            Write-Host ""
        }
        
        # Response Time
        Write-Host "│ Response Time: " -NoNewline -ForegroundColor $envColor
        $rtColor = if ($envData.Health.ResponseTime -lt 500) { "Green" }
                   elseif ($envData.Health.ResponseTime -lt 1000) { "Yellow" }
                   elseif ($envData.Health.ResponseTime -lt 2000) { "Magenta" }
                   else { "Red" }
        Write-Host "$(Format-ResponseTime -Ms $envData.Health.ResponseTime)" -ForegroundColor $rtColor
        
        # Metrics
        if ($envData.Metrics.CpuUsage -gt 0 -or $envData.Metrics.MemoryUsage -gt 0) {
            Write-Host "│ CPU Usage    : " -NoNewline -ForegroundColor $envColor
            $cpuColor = if ($envData.Metrics.CpuUsage -lt 50) { "Green" }
                        elseif ($envData.Metrics.CpuUsage -lt 80) { "Yellow" }
                        else { "Red" }
            Write-Host "$($envData.Metrics.CpuUsage)%" -ForegroundColor $cpuColor
            
            Write-Host "│ Memory Usage : " -NoNewline -ForegroundColor $envColor
            $memColor = if ($envData.Metrics.MemoryUsage -lt 70) { "Green" }
                        elseif ($envData.Metrics.MemoryUsage -lt 85) { "Yellow" }
                        else { "Red" }
            Write-Host "$($envData.Metrics.MemoryUsage)%" -ForegroundColor $memColor
        }
        
        # Dependencies
        if ($envData.Health.Dependencies.Count -gt 0) {
            Write-Host "│ Dependencies :" -ForegroundColor $envColor
            foreach ($dep in $envData.Health.Dependencies) {
                $depStatus = if ($dep.Status -eq "Healthy") { "✅" } else { "❌" }
                Write-Host "│   $depStatus $($dep.Name): $($dep.Status) ($($dep.ResponseTime)ms)" -ForegroundColor Gray
            }
        }
        
        Write-Host "└" + ("─" * 79) -ForegroundColor $envColor
    }
    
    # Recent Alerts
    if ($script:MonitoringData.Alerts.Count -gt 0) {
        Write-Host "`n┌─ RECENT ALERTS " + ("─" * 63) -ForegroundColor Red
        
        $recentAlerts = $script:MonitoringData.Alerts | 
            Sort-Object Timestamp -Descending | 
            Select-Object -First 5
        
        foreach ($alert in $recentAlerts) {
            $icon = if ($alert.Severity -eq "Critical") { "🚨" } else { "⚠️ " }
            $color = if ($alert.Severity -eq "Critical") { "Red" } else { "Yellow" }
            $time = $alert.Timestamp.ToString("HH:mm:ss")
            Write-Host "│ $icon [$time] [$($alert.Environment)] $($alert.Message)" -ForegroundColor $color
        }
        
        Write-Host "└" + ("─" * 79) -ForegroundColor Red
    }
    
    # Footer
    Write-Host "`nRefreshing every $RefreshInterval seconds... Press Ctrl+C to stop" -ForegroundColor Gray
}

function Export-MonitoringData {
    param([string]$FilePath, [object]$Data)
    
    if ([string]::IsNullOrEmpty($FilePath)) { return }
    
    $exportData = @{
        project = $ProjectName
        timestamp = Get-Date -Format "o"
        uptime_minutes = [math]::Round(((Get-Date) - $script:MonitoringData.StartTime).TotalMinutes, 2)
        total_checks = $script:MonitoringData.Checks
        environments = $Data
        alerts = $script:MonitoringData.Alerts
    }
    
    $exportData | ConvertTo-Json -Depth 10 | Add-Content -Path $FilePath
}

# ============================================================================
# MAIN MONITORING LOOP
# ============================================================================

Write-Host "Starting health monitoring for $ProjectName..." -ForegroundColor Cyan

# Determine which environments to monitor
$envsToMonitor = if ($Environment -eq "All") {
    $environments.Keys
} else {
    @($Environment)
}

$startTime = Get-Date
$endTime = if ($Duration -gt 0) {
    $startTime.AddMinutes($Duration)
} else {
    [datetime]::MaxValue
}

try {
    while ((Get-Date) -lt $endTime) {
        $currentData = @{}
        
        foreach ($envName in $envsToMonitor) {
            $envConfig = $environments[$envName]
            $healthUrl = "$($envConfig.BaseUrl)/$ProjectName$($envConfig.HealthEndpoint)"
            $metricsUrl = "$($envConfig.BaseUrl)/$ProjectName$($envConfig.MetricsEndpoint)"
            
            # Get health status
            $health = Get-HealthStatus -Url $healthUrl
            
            # Get metrics
            $metrics = Get-MetricsData -Url $metricsUrl
            
            # Test for alerts
            $alerts = Test-Alerts -Health $health -Metrics $metrics -Env $envName
            
            $currentData[$envName] = @{
                Health = $health
                Metrics = $metrics
                Alerts = $alerts
            }
            
            $script:MonitoringData.Checks++
        }
        
        # Render dashboard
        Render-Dashboard -Data $currentData
        
        # Export log
        if (![string]::IsNullOrEmpty($ExportLog)) {
            Export-MonitoringData -FilePath $ExportLog -Data $currentData
        }
        
        # Wait for refresh interval
        Start-Sleep -Seconds $RefreshInterval
    }
    
    Write-Host "`n✅ Monitoring completed (duration reached)" -ForegroundColor Green
    
} catch {
    if ($_.Exception.Message -like "*operation was canceled*") {
        Write-Host "`n⏹️  Monitoring stopped by user" -ForegroundColor Yellow
    } else {
        Write-Host "`n❌ Monitoring error: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# Final Summary
Write-Host "`n" + "="*80 -ForegroundColor Cyan
Write-Host " MONITORING SUMMARY" -ForegroundColor Cyan
Write-Host "="*80 -ForegroundColor Cyan

$duration = (Get-Date) - $script:MonitoringData.StartTime
Write-Host "`nTotal Monitoring Time: $([math]::Round($duration.TotalMinutes, 1)) minutes" -ForegroundColor Cyan
Write-Host "Total Health Checks  : $($script:MonitoringData.Checks)" -ForegroundColor Cyan
Write-Host "Total Alerts         : $($script:MonitoringData.Alerts.Count)" -ForegroundColor Cyan

if ($script:MonitoringData.Alerts.Count -gt 0) {
    $criticalCount = ($script:MonitoringData.Alerts | Where-Object { $_.Severity -eq "Critical" }).Count
    $warningCount = ($script:MonitoringData.Alerts | Where-Object { $_.Severity -eq "Warning" }).Count
    
    Write-Host "  Critical: $criticalCount" -ForegroundColor Red
    Write-Host "  Warning : $warningCount" -ForegroundColor Yellow
}

if (![string]::IsNullOrEmpty($ExportLog)) {
    Write-Host "`nMonitoring log exported to: $ExportLog" -ForegroundColor Green
}

Write-Host ""
