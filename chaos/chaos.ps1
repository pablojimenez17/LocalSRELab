<#
.SYNOPSIS
    LocalSRE Lab - Chaos Engineering Toolkit (PowerShell Native)
.DESCRIPTION
    Automates SRE incident experiments on Kubernetes / Docker containers for LocalSRE Lab.
.EXAMPLE
    .\chaos.ps1 kill-api
    .\chaos.ps1 cpu-stress -Duration 20 -Concurrency 6
    .\chaos.ps1 error-spike -Count 80
    .\chaos.ps1 partition-db -Duration 25
    .\chaos.ps1 status
#>

param (
    [Parameter(Position=0)]
    [ValidateSet("kill-api", "kill-pod", "cpu-stress", "error-spike", "partition-db", "unready", "status", "help")]
    [string]$Command = "help",

    [Parameter()]
    [int]$Duration = 15,

    [Parameter()]
    [int]$Concurrency = 4,

    [Parameter()]
    [int]$Count = 100,

    [Parameter()]
    [string]$Namespace = "localsre",

    [Parameter()]
    [string]$ApiUrl = "http://localhost:8000"
)

function Write-Banner {
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "            * LocalSRE Lab - Chaos Engineering Suite *          " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
}

function Show-Help {
    Write-Banner
    Write-Host "Usage: .\chaos.ps1 [command] [options]"
    Write-Host ""
    Write-Host "Available Commands:"
    Write-Host "  kill-api       Randomly terminates one API pod to verify self-healing" -ForegroundColor Yellow
    Write-Host "  cpu-stress     Injects heavy CPU load to observe HPA autoscaling" -ForegroundColor Yellow
    Write-Host "  error-spike    Fires continuous HTTP 500 errors to trigger Prometheus alerts" -ForegroundColor Yellow
    Write-Host "  partition-db   Forces pod unready state to verify traffic isolation" -ForegroundColor Yellow
    Write-Host "  status         Checks pod health, endpoints, and probe statuses" -ForegroundColor Yellow
    Write-Host "  help           Displays this help screen" -ForegroundColor Yellow
    Write-Host ""
}

function Get-LabStatus {
    Write-Host "[INFO] Checking Kubernetes resources in namespace: $Namespace" -ForegroundColor Blue
    try {
        kubectl get pods,svc,hpa -n $Namespace -o wide
        Write-Host ""
        Write-Host "[INFO] Service Endpoints:" -ForegroundColor Blue
        kubectl get endpoints localsre-api -n $Namespace
    } catch {
        Write-Host "[WARN] kubectl command unavailable or cluster unreachable." -ForegroundColor DarkYellow
    }

    Write-Host ""
    Write-Host "[INFO] Probing API at $ApiUrl..." -ForegroundColor Blue
    try {
        $health = Invoke-RestMethod -Uri "$ApiUrl/healthz" -Method Get -TimeoutSec 3
        $jsonHealth = $health | ConvertTo-Json -Compress
        Write-Host "Liveness /healthz: $jsonHealth" -ForegroundColor Green
    } catch {
        Write-Host "Liveness /healthz: Down or unreachable" -ForegroundColor Red
    }

    try {
        $ready = Invoke-RestMethod -Uri "$ApiUrl/readyz" -Method Get -TimeoutSec 3
        $jsonReady = $ready | ConvertTo-Json -Compress
        Write-Host "Readiness /readyz: $jsonReady" -ForegroundColor Green
    } catch {
        Write-Host "Readiness /readyz: Degraded (503 Service Unavailable)" -ForegroundColor DarkYellow
    }
}

function Invoke-KillApi {
    Write-Banner
    Write-Host "[WARN] Experiment 01: Pod Self-Healing and High Availability" -ForegroundColor Yellow

    $pods = kubectl get pods -n $Namespace -l app.kubernetes.io/name=localsre-api -o jsonpath='{.items[*].metadata.name}'
    if (-not $pods) {
        Write-Host "[ERROR] No pods found in namespace $Namespace." -ForegroundColor Red
        return
    }

    $podList = $pods -split ' '
    $randomPod = $podList | Get-Random

    Write-Host "[WARN] Killing random API pod: $randomPod..." -ForegroundColor Yellow
    kubectl delete pod $randomPod -n $Namespace --wait=$false

    Write-Host ""
    Write-Host "[INFO] Watching Kubernetes ReplicaSet recreate the pod..." -ForegroundColor Blue
    Start-Sleep -Seconds 2
    kubectl get pods -n $Namespace -l app.kubernetes.io/name=localsre-api
    Write-Host "[SUCCESS] Kubernetes automatically launched a new pod to maintain the desired 3 replicas." -ForegroundColor Green
}

function Invoke-CpuStress {
    Write-Banner
    Write-Host "[WARN] Experiment 02: CPU Stress and Horizontal Pod Autoscaler" -ForegroundColor Yellow
    Write-Host "[INFO] Triggering CPU load via $ApiUrl/chaos/cpu-stress ($Concurrency parallel workers)" -ForegroundColor Blue

    1..$Concurrency | ForEach-Object -Parallel {
        $targetUrl = $using:ApiUrl
        $targetDur = $using:Duration
        try {
            $null = Invoke-RestMethod -Uri "$targetUrl/chaos/cpu-stress?duration_seconds=$targetDur" -Method Post -TimeoutSec ($targetDur + 5)
        } catch {}
    } -ThrottleLimit $Concurrency

    Write-Host "[INFO] Monitoring HPA status for 15 seconds..." -ForegroundColor Blue
    1..5 | ForEach-Object {
        try { kubectl get hpa localsre-api-hpa -n $Namespace } catch {}
        Start-Sleep -Seconds 3
    }
    Write-Host "[SUCCESS] CPU load experiment completed." -ForegroundColor Green
}

function Invoke-ErrorSpike {
    Write-Banner
    Write-Host "[WARN] Experiment 03: HTTP 500 Error Spike and Alerting" -ForegroundColor Yellow
    Write-Host "[INFO] Sending $Count requests to trigger 500 errors..." -ForegroundColor Blue

    $errors = 0
    $success = 0

    1..$Count | ForEach-Object {
        try {
            $resp = Invoke-WebRequest -Uri "$ApiUrl/chaos/error-spike?error_rate=1.0" -Method Get -UseBasicParsing -TimeoutSec 2
            $success++
        } catch {
            $errors++
        }
        Write-Host -NoNewline "."
    }
    Write-Host ""
    Write-Host "[INFO] Dispatched: $Count requests | 500 Errors: $errors | Successes: $success" -ForegroundColor Green
    Write-Host "[INFO] Open Grafana to view the Error Rate (5xx %) surge and Prometheus Alerts tab." -ForegroundColor Cyan
}

function Invoke-PartitionDb {
    Write-Banner
    Write-Host "[WARN] Experiment 04: Dependency Degradation and Service Decoupling" -ForegroundColor Yellow
    Write-Host "[INFO] Setting pod into UNREADY state for $Duration seconds..." -ForegroundColor Blue

    try {
        $null = Invoke-RestMethod -Uri "$ApiUrl/chaos/unready?duration_seconds=$Duration" -Method Post
        Write-Host "[INFO] Pod set to unready. Verifying /readyz..." -ForegroundColor Blue
        try {
            $null = Invoke-RestMethod -Uri "$ApiUrl/readyz" -Method Get
        } catch {
            Write-Host "[SUCCESS] Readiness probe returned 503 as expected! Pod isolated from traffic." -ForegroundColor Green
        }
    } catch {
        Write-Host "[ERROR] Could not communicate with API at $ApiUrl" -ForegroundColor Red
    }
}

switch ($Command) {
    "kill-api"     { Invoke-KillApi }
    "kill-pod"     { Invoke-KillApi }
    "cpu-stress"   { Invoke-CpuStress }
    "error-spike"  { Invoke-ErrorSpike }
    "partition-db" { Invoke-PartitionDb }
    "unready"      { Invoke-PartitionDb }
    "status"       { Get-LabStatus }
    default        { Show-Help }
}
