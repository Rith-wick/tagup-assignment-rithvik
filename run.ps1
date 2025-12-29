param(
  [switch]$PortForward,
  [switch]$Logs,
  [switch]$Psql,
  [switch]$Down,
  [switch]$Reset,
  [switch]$Nuke
)

$ErrorActionPreference = "Stop"

# -------------------------
# Configuration
# -------------------------
$CLUSTER_NAME = "tagup"
$NAMESPACE    = "fleet"

$API_IMAGE    = "fleet-api:1.0"
$CLIENT_IMAGE = "fleet-client:1.0"

$K8S_DIR      = "k8s"
$YAML_NS      = Join-Path $K8S_DIR "namespace.yaml"
$YAML_PG      = Join-Path $K8S_DIR "postgres.yaml"
$YAML_API     = Join-Path $K8S_DIR "api.yaml"
$YAML_CLIENT  = Join-Path $K8S_DIR "client.yaml"

$API_SVC_NAME = "fleet-api"
$API_PORT     = 8000
$PG_POD_NAME  = "postgres"

# -------------------------
# Cross-platform helper
# -------------------------
$IS_WINDOWS = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
  [System.Runtime.InteropServices.OSPlatform]::Windows
)

function Invoke-NativeCapture {
  param(
    [Parameter(Mandatory=$true)][string]$File,
    [Parameter(Mandatory=$true)][string[]]$Args
  )

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $File
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute = $false

  if ($psi.PSObject.Properties.Name -contains "ArgumentList" -and $null -ne $psi.ArgumentList) {
    foreach ($a in $Args) { [void]$psi.ArgumentList.Add($a) }
  } else {
    $escaped = $Args | ForEach-Object {
      if ($_ -match '[\s"]') { '"' + ($_ -replace '"','\"') + '"' } else { $_ }
    }
    $psi.Arguments = ($escaped -join ' ')
  }

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  [void]$p.Start()

  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()

  $combined = (($stdout + "`n" + $stderr).TrimEnd())
  $lines = if ($combined.Length -gt 0) { @($combined -split "`r?`n") } else { @() }

  return @{ Output = $lines; ExitCode = $p.ExitCode }
}

# -------------------------
# Utility functions
# -------------------------
function Require-Command($cmd) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw "Required command '$cmd' not found in PATH."
  }
}

function Check-Prerequisites() {
  Require-Command "docker"
  Require-Command "kind"
  Require-Command "kubectl"

  & docker info *> $null
  if ($LASTEXITCODE -ne 0) {
    throw "Docker is not running or not reachable. Start Docker Desktop and try again."
  }
}

function Kind-Cluster-Exists() {
  $r = Invoke-NativeCapture -File "kind" -Args @("get","clusters")
  if ($r.ExitCode -ne 0) { return $false }
  return ($r.Output -contains $CLUSTER_NAME)
}

function Ensure-Kind-Cluster() {
  if (Kind-Cluster-Exists) {
    Write-Host "Kind cluster '$CLUSTER_NAME' already exists."
    return
  }

  Write-Host "Creating kind cluster '$CLUSTER_NAME'..."
  & kind create cluster --name $CLUSTER_NAME -v 9 | Out-Host

  if ($LASTEXITCODE -ne 0) {
    & docker info 2>&1 | Out-Host
    & docker ps -a 2>&1 | Out-Host
    throw "kind create cluster failed (see output above)."
  }

  if (-not (Kind-Cluster-Exists)) {
    $kc = Invoke-NativeCapture -File "kind" -Args @("get","clusters")
    throw (("Kind cluster '$CLUSTER_NAME' still not visible after creation." + "" + "---- kind get clusters ----" + $kc.Output) -join "`n")
  }
}

function Build-Images() {
  Write-Host "Building Docker images..."

  docker build -t $API_IMAGE ./api | Out-Host
  docker build -t $CLIENT_IMAGE ./client | Out-Host
}

function Load-Images() {
  Write-Host "Loading Docker images into kind cluster..."
  kind load docker-image $API_IMAGE --name $CLUSTER_NAME | Out-Host
  kind load docker-image $CLIENT_IMAGE --name $CLUSTER_NAME | Out-Host
}

function Apply-K8s() {
  Write-Host "Applying Kubernetes manifests..."
  kubectl apply -f $YAML_NS | Out-Host
  kubectl apply -f $YAML_PG -n $NAMESPACE | Out-Host
  kubectl apply -f $YAML_API -n $NAMESPACE | Out-Host
  kubectl apply -f $YAML_CLIENT -n $NAMESPACE | Out-Host
}

function Wait-For-Pods() {
  Write-Host "Waiting for all pods to become Ready..."
  kubectl wait --for=condition=Ready pod --all -n $NAMESPACE --timeout=180s | Out-Host
}

function Print-Status() {
  Write-Host ""
  Write-Host "Current Kubernetes status:"
  kubectl get pods -n $NAMESPACE | Out-Host
  kubectl get svc -n $NAMESPACE | Out-Host
}

function Print-Next-Steps() {
  $runner = if ($IS_WINDOWS) { ".\run.ps1" } else { "pwsh ./run.ps1" }

  Write-Host ""
  Write-Host "Deployment completed successfully."
  Write-Host ""
  Write-Host "Recommended next steps:"
  Write-Host ""
  Write-Host "1) Port-forward API and open Swagger docs:"
  Write-Host "   $runner -PortForward"
  Write-Host "   http://127.0.0.1:$API_PORT/docs"
  Write-Host ""
  Write-Host "2) Tail client logs (shows POST + GET latest + risk):"
  Write-Host "   $runner -Logs"
  Write-Host ""
  Write-Host "3) Verify database rows using psql:"
  Write-Host "   $runner -Psql"
  Write-Host ""
  Write-Host "   Example SQL:"
  Write-Host "     SELECT * FROM asset_telemetry"
  Write-Host "     ORDER BY recorded_at DESC"
  Write-Host "     LIMIT 5;"
  Write-Host ""
  Write-Host "Cleanup options:"
  Write-Host "   Stop client (keep DB + API):   $runner -Down"
  Write-Host "   Reset application + DB:        $runner -Reset"
  Write-Host "   Delete entire cluster:         $runner -Nuke"
  Write-Host ""
}

# -------------------------
# Actions
# -------------------------
function Action-Up() {
  Check-Prerequisites
  Ensure-Kind-Cluster
  Build-Images
  Load-Images
  Apply-K8s
  Wait-For-Pods
  Print-Status
  Print-Next-Steps
}

function Action-PortForward() {
  Check-Prerequisites
  Write-Host "Port-forwarding API service..."
  Write-Host "Open http://127.0.0.1:$API_PORT/docs"
  Write-Host "Press Ctrl+C to stop."
  kubectl port-forward -n $NAMESPACE svc/$API_SVC_NAME $API_PORT`:$API_PORT
}

function Get-FirstPodName([string]$prefix) {
  $name = kubectl get pods -n $NAMESPACE -o jsonpath="{range .items[*]}{.metadata.name}{'\n'}{end}" 2>$null |
    Where-Object { $_ -like "$prefix*" } |
    Select-Object -First 1

  return $name
}

function Action-Logs() {
  Check-Prerequisites

  $clientPod = Get-FirstPodName "fleet-client"
  if (-not $clientPod) {
    throw "fleet-client pod not found."
  }

  Write-Host "Tailing logs for pod/$clientPod"
  Write-Host "Press Ctrl+C to stop."
  kubectl logs -n $NAMESPACE -f "pod/$clientPod"
}

function Action-Psql() {
  Check-Prerequisites
  Write-Host "Opening psql inside postgres pod."
  Write-Host ""
  Write-Host "Run this query to verify stored telemetry:"
  Write-Host "  SELECT * FROM asset_telemetry ORDER BY recorded_at DESC LIMIT 5;"
  Write-Host ""
  Write-Host "Type \q to exit psql."
  Write-Host ""
  kubectl exec -it -n $NAMESPACE $PG_POD_NAME -- psql -U fleetuser -d fleetdb
}

function Action-Down() {
  Check-Prerequisites
  Write-Host "Stopping client (database and api will remain)..."
  kubectl delete -f $YAML_CLIENT -n $NAMESPACE --ignore-not-found | Out-Host
  Print-Status
}

function Action-Reset() {
  Check-Prerequisites
  Write-Host "Resetting application and wiping database..."
  kubectl delete all --all -n $NAMESPACE --ignore-not-found | Out-Host
  kubectl delete configmap --all -n $NAMESPACE --ignore-not-found | Out-Host
  kubectl delete pvc --all -n $NAMESPACE --ignore-not-found | Out-Host
  Print-Status
}

function Action-Nuke() {
  Check-Prerequisites
  Write-Host "Deleting kind cluster '$CLUSTER_NAME'..."
  kind delete cluster --name $CLUSTER_NAME | Out-Host
}

# -------------------------
# Entry point
# -------------------------
try {
  if ($Nuke)        { Action-Nuke }
  elseif ($Reset)  { Action-Reset }
  elseif ($Down)   { Action-Down }
  elseif ($Psql)   { Action-Psql }
  elseif ($Logs)   { Action-Logs }
  elseif ($PortForward) { Action-PortForward }
  else             { Action-Up }
}
catch {
  Write-Host ""
  Write-Host "Error: $($_.Exception.Message)"
  Write-Host ""
  exit 1
}