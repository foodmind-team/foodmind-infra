[CmdletBinding()]
param(
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repositoryRoot
try {
    docker compose config --quiet
    docker compose up --build -d --wait --wait-timeout $TimeoutSeconds
    $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8080/actuator/health/readiness' -TimeoutSec 10
    if ($health.status -ne 'UP') {
        throw "Backend readiness is not UP: $($health | ConvertTo-Json -Compress)"
    }
    docker compose ps
} finally {
    Pop-Location
}
