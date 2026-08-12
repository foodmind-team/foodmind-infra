[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot

Push-Location $repositoryRoot
try {
    git submodule update --init --recursive
    if (-not (Test-Path -LiteralPath '.env')) {
        Copy-Item -LiteralPath '.env.example' -Destination '.env'
        Write-Host 'Created .env from .env.example. Optionally add DEEPSEEK_API_KEY and set FOODMIND_LLM_ENABLED=true.'
    }
    docker compose up --build -d --wait
} finally {
    Pop-Location
}
