[CmdletBinding()]
param(
    [string]$ProjectName = 'foodmind-recommendation-diversity',
    [int]$BackendPort = 8080,
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$environmentPath = if (Test-Path -LiteralPath (Join-Path $repositoryRoot '.env')) {
    Join-Path $repositoryRoot '.env'
} else {
    Join-Path $repositoryRoot '.env.example'
}
$composeArguments = @('compose', '--env-file', $environmentPath, '--project-name', $ProjectName)

function Invoke-Compose {
    & docker @composeArguments @args
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed with exit code $LASTEXITCODE."
    }
}

function Invoke-DatabaseScalar([string]$Sql) {
    $output = & docker @composeArguments exec -T -e "VERIFY_SQL=$Sql" postgres sh -ec 'psql -At -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$VERIFY_SQL"'
    if ($LASTEXITCODE -ne 0) {
        throw "Database verification failed with exit code $LASTEXITCODE."
    }
    return ($output | Select-Object -Last 1).Trim()
}

function New-IdempotencyHeaders([string]$AccessToken) {
    return @{
        Authorization = "Bearer $AccessToken"
        'Idempotency-Key' = [guid]::NewGuid().ToString()
    }
}

Push-Location $repositoryRoot
try {
    $expectedMlCommit = '6b5b417411e04f5388d0eab39e1a57dee9d92676'
    $actualMlCommit = (git -c safe.directory=* -C services/ml rev-parse HEAD).Trim()
    if ($actualMlCommit -ne $expectedMlCommit) {
        throw "ML source drift: expected $expectedMlCommit, found $actualMlCommit."
    }
    python services/backend/scripts/build-ml-local-recommendation-seed.py --ml-root services/ml --check
    if ($LASTEXITCODE -ne 0) {
        throw 'The committed ML-derived local seed does not match its manifest.'
    }

    Invoke-Compose up --build -d --wait --wait-timeout $TimeoutSeconds

    $seedCounts = Invoke-DatabaseScalar @"
SELECT count(DISTINCT pm.place_id) || ':' || count(*)
FROM place_meal pm
JOIN meal m ON m.id = pm.meal_id
WHERE m.description LIKE 'Local ML-derived menu item%';
"@
    if ($seedCounts -ne '6:96') {
        throw "Expected 6 seeded places and 96 offerings, found $seedCounts."
    }

    $baseUri = "http://127.0.0.1:$BackendPort/api/v1"
    $suffix = "{0}-{1}" -f [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(), (Get-Random -Maximum 100000)
    $registration = Invoke-RestMethod -Method Post -Uri "$baseUri/auth/register" -ContentType 'application/json' -Body (@{
        email = "recommendation-smoke-$suffix@example.test"
        displayName = 'Recommendation Smoke'
        password = 'Local-smoke-password-42!'
        timeZone = 'Asia/Singapore'
        clientType = 'ANDROID'
        deviceLabel = 'Infra smoke'
    } | ConvertTo-Json)
    $token = $registration.accessToken
    if (-not $token) {
        throw 'Registration did not return an access token.'
    }

    $requestBody = @{ mealType = 'DINNER' } | ConvertTo-Json
    $first = Invoke-RestMethod -Method Post -Uri "$baseUri/recommendations/generate" -Headers (New-IdempotencyHeaders $token) -ContentType 'application/json' -Body $requestBody
    $firstItems = @($first.items)
    if ($first.modelVersion -ne 'hybrid-ranking-v1' -or $firstItems.Count -lt 1 -or $firstItems.Count -gt 3) {
        throw "Unexpected recommendation result: model=$($first.modelVersion), count=$($firstItems.Count)."
    }

    $placeMealIds = @($firstItems.placeMealId | Where-Object { $_ })
    if ($placeMealIds.Count -ne $firstItems.Count -or ($placeMealIds | Where-Object { $_ -notmatch '^[0-9a-f-]{36}$' })) {
        throw 'The local smoke expected catalogue-backed UUID candidates only.'
    }
    $quotedIds = ($placeMealIds | ForEach-Object { "'$_'" }) -join ','
    $diversity = (Invoke-DatabaseScalar "SELECT count(DISTINCT pm.recommendation_category_code) || ':' || count(DISTINCT c.code) FROM place_meal pm JOIN meal m ON m.id = pm.meal_id LEFT JOIN cuisine c ON c.id = m.cuisine_id WHERE pm.id IN ($quotedIds);").Split(':')
    if ($firstItems.Count -ge 3 -and [int]$diversity[0] -lt 2 -and [int]$diversity[1] -lt 2) {
        throw "The top three did not diversify category or cuisine: $($diversity -join ':')."
    }

    $blocked = $firstItems[0]
    $feedback = Invoke-RestMethod -Method Post -Uri "$baseUri/recommendations/$($first.sessionId)/feedback" -Headers (New-IdempotencyHeaders $token) -ContentType 'application/json' -Body (@{
        eventType = 'REJECTED'
        candidateId = $blocked.candidateId
        reasonCode = 'DO_NOT_RECOMMEND'
    } | ConvertTo-Json)
    if ($feedback.reasonCode -ne 'DO_NOT_RECOMMEND' -or $null -ne $feedback.effectiveUntil -or $feedback.supervisedLabel -ne 0) {
        throw 'Permanent rejection did not persist with null expiry and supervised label 0.'
    }

    $history = Invoke-RestMethod -Method Get -Uri "$baseUri/recommendations/$($first.sessionId)" -Headers @{ Authorization = "Bearer $token" }
    if ($blocked.candidateId -notin @($history.items.candidateId)) {
        throw 'The historical recommendation session changed after feedback.'
    }

    $second = Invoke-RestMethod -Method Post -Uri "$baseUri/recommendations/generate" -Headers (New-IdempotencyHeaders $token) -ContentType 'application/json' -Body $requestBody
    if (@($second.items | Where-Object { $_.mealId -eq $blocked.mealId -and $_.placeId -eq $blocked.placeId }).Count -ne 0) {
        throw 'A permanently rejected meal/place target reappeared in a future session.'
    }

    Write-Host "Recommendation diversity smoke passed: seed=$seedCounts; model=$($first.modelVersion); diversity=$($diversity -join ':'); permanent exclusion verified."
} finally {
    Pop-Location
}
