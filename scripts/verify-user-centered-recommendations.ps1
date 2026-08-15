[CmdletBinding()]
param([int]$BackendPort = 8080)

$ErrorActionPreference = 'Stop'
$baseUri = "http://127.0.0.1:$BackendPort/api/v1"
$password = 'Showcase-password-42!'

function Invoke-Json([string]$Method, [string]$Path, [object]$Body = $null, [string]$Token = '', [switch]$Idempotent) {
    $headers = @{}
    if ($Token) { $headers.Authorization = "Bearer $Token" }
    if ($Idempotent) { $headers['Idempotency-Key'] = [guid]::NewGuid().ToString() }
    $arguments = @{ Method = $Method; Uri = "$baseUri$Path"; Headers = $headers }
    if ($null -ne $Body) {
        $arguments.ContentType = 'application/json'
        $arguments.Body = $Body | ConvertTo-Json -Depth 12
    }
    Invoke-RestMethod @arguments
}

function Get-ShowcaseUser([string]$Email, [string]$Name, [string]$ClientType = 'WEB') {
    try {
        Invoke-Json Post '/auth/register' @{
            email = $Email; displayName = $Name; password = $password; timeZone = 'Asia/Singapore'
            clientType = $ClientType; deviceLabel = 'User-centered showcase'
        }
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -ne 409) { throw }
        Invoke-Json Post '/auth/login' @{
            email = $Email; password = $password; clientType = $ClientType; deviceLabel = 'User-centered showcase'
        }
    }
}

function New-Recommendation([string]$Token, [object]$Body) {
    Invoke-Json Post '/recommendations/generate' $Body $Token -Idempotent
}

function Assert-Profile([object]$Recommendation, [string]$ExpectedMode, [string[]]$ExpectedFactors, [switch]$RequireModel) {
    if ($Recommendation.decisionProfile.mode -ne $ExpectedMode) {
        throw "Expected decision mode $ExpectedMode, found $($Recommendation.decisionProfile.mode)."
    }
    foreach ($factor in $ExpectedFactors) {
        if ($factor -notin @($Recommendation.decisionProfile.appliedFactors)) {
            throw "Decision profile $ExpectedMode did not include $factor."
        }
    }
    if ($RequireModel -and $Recommendation.modelVersion -ne 'hybrid-ranking-v1') {
        throw "Expected hybrid-ranking-v1, found $($Recommendation.modelVersion)."
    }
    if (@($Recommendation.items).Count -eq 0) { throw "Decision profile $ExpectedMode returned no usable candidates." }
}

$defaultUser = Get-ShowcaseUser 'showcase.default@example.test' 'New User Demo'
$defaultRecommendation = New-Recommendation $defaultUser.accessToken @{ mealType = 'DINNER' }
Assert-Profile $defaultRecommendation 'DEFAULT' @() -RequireModel

$constraintUser = Get-ShowcaseUser 'showcase.constraints@example.test' 'Spice & Allergy Demo' 'ANDROID'
Invoke-Json Put '/users/me/preferences' @{
    currency = 'SGD'; spiceTolerance = 5; cleanlinessPriority = 0
    likedCuisineCodes = @('INDIAN'); dislikedCuisineCodes = @(); dietaryTagCodes = @()
    allergens = @(@{ code = 'SESAME'; severity = 'SEVERE' }); preferredMealTypes = @('DINNER')
} $constraintUser.accessToken | Out-Null
$constraintRecommendation = New-Recommendation $constraintUser.accessToken @{
    mealType = 'DINNER'; constraints = @{ avoidAllergenCodes = @('SESAME'); maxSpiceLevel = 5 }
}
Assert-Profile $constraintRecommendation 'CONSTRAINT_FOCUSED' @('SPICE_PREFERENCE', 'ALLERGEN_AVOIDANCE', 'CUISINE_PREFERENCE')

$groupOwner = Get-ShowcaseUser 'showcase.group@example.test' 'Group Decision Demo'
$memberOne = Get-ShowcaseUser 'showcase.member1@example.test' 'Trusted Member One'
$memberTwo = Get-ShowcaseUser 'showcase.member2@example.test' 'Trusted Member Two'
$groups = @(Invoke-Json Get '/groups' $null $groupOwner.accessToken)
$group = $groups | Where-Object name -eq 'Showcase Dinner Circle' | Select-Object -First 1
if (-not $group) { $group = Invoke-Json Post '/groups' @{ name = 'Showcase Dinner Circle'; description = 'Trusted real food-record evidence for the live showcase' } $groupOwner.accessToken }

foreach ($member in @($memberOne, $memberTwo)) {
    $members = @(Invoke-Json Get "/groups/$($group.id)/members" $null $groupOwner.accessToken)
    if ($member.userId -notin @($members.userId)) {
        $invitation = Invoke-Json Post "/groups/$($group.id)/invitations" @{ maxUses = 1 } $groupOwner.accessToken
        Invoke-Json Post '/group-invitations/join' @{ token = $invitation.token } $member.accessToken | Out-Null
    }
}

$recordIndex = 0
foreach ($member in @($memberOne, $memberTwo)) {
    $recordIndex++
    Invoke-Json Post '/food-records' @{
        mealId = '20000000-0000-4000-8000-000000000003'
        mealNameSnapshot = 'Chana Masala with Rice'
        placeId = '21000000-0000-4000-8000-000000000003'
        placeNameSnapshot = 'Serangoon Vegetarian Table'
        cuisineId = '10000000-0000-4000-8000-000000000004'
        occurredAt = "2026-08-1$recordIndex`T12:15:00Z"
        price = 9.50; currency = 'SGD'; rating = 5
        comment = "Trusted showcase record $recordIndex"; visibility = 'GROUP'; groupId = $group.id
    } $member.accessToken | Out-Null
}

$groupRecommendation = New-Recommendation $groupOwner.accessToken @{ mealType = 'DINNER'; groupId = $group.id }
Assert-Profile $groupRecommendation 'GROUP_GUIDED' @('GROUP_MEMBER_RECORDS')
if ($groupRecommendation.decisionProfile.groupMemberEvidenceCount -lt 2) {
    throw 'Group-guided result did not include at least two authorized group-record observations.'
}

[pscustomobject]@{
    default = [pscustomobject]@{ email = 'showcase.default@example.test'; sessionId = $defaultRecommendation.sessionId; lead = $defaultRecommendation.items[0].mealName; mode = $defaultRecommendation.decisionProfile.mode }
    constraints = [pscustomobject]@{ email = 'showcase.constraints@example.test'; sessionId = $constraintRecommendation.sessionId; lead = $constraintRecommendation.items[0].mealName; mode = $constraintRecommendation.decisionProfile.mode; factors = @($constraintRecommendation.decisionProfile.appliedFactors) }
    group = [pscustomobject]@{ email = 'showcase.group@example.test'; sessionId = $groupRecommendation.sessionId; groupId = $group.id; lead = $groupRecommendation.items[0].mealName; mode = $groupRecommendation.decisionProfile.mode; evidenceCount = $groupRecommendation.decisionProfile.groupMemberEvidenceCount }
} | ConvertTo-Json -Depth 8
