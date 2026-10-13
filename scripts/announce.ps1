# Annonces du launcher (maintenance, événements, fin d'un bundle...) et chaînes
# Twitch dont le live s'affiche en bannière. Écrit channels/news.json, signé
# comme les manifestes, puis l'envoie sur GitHub.
param(
    # { twitch: ["chaine"], announcements: [{ id, kind, title, text, until, audience, url, image }] }
    [Parameter(Mandatory = $true)][string]$File,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'signing.ps1')
$NewsPath = Join-Path $Root 'channels\news.json'
$Kinds = @('info', 'event', 'maintenance')
$Audiences = @('all', 'prod', 'dev')

function Assert-LastExit([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step a échoué (code $LASTEXITCODE)." }
}

function Get-Link([string]$Url) {
    $Url = $Url.Trim()
    if (-not $Url) { return '' }
    if ($Url -notmatch '^https://[^\s]+$') { throw "Lien refusé (il doit commencer par https://) : $Url" }
    return $Url
}

$data = Get-Content $File -Raw -Encoding UTF8 | ConvertFrom-Json

$twitch = New-Object System.Collections.Generic.List[string]
foreach ($channel in @($data.twitch)) {
    $name = "$channel".Trim().ToLowerInvariant() -replace '^https?://(www\.)?twitch\.tv/', ''
    if (-not $name) { continue }
    if ($name -notmatch '^[a-z0-9_]{3,25}$') { throw "Nom de chaîne Twitch invalide : $channel" }
    if (-not $twitch.Contains($name)) { $twitch.Add($name) }
}

$announcements = New-Object System.Collections.Generic.List[object]
foreach ($item in @($data.announcements)) {
    if (-not $item) { continue }
    $title = "$($item.title)".Trim()
    if (-not $title) { throw 'Chaque annonce a besoin d''un titre.' }
    $kind = "$($item.kind)"
    if ($Kinds -notcontains $kind) { $kind = 'info' }
    $audience = "$($item.audience)"
    if ($Audiences -notcontains $audience) { $audience = 'all' }
    $until = "$($item.until)".Trim()
    if ($until -and $until -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "Date de fin invalide pour « $title » (format AAAA-MM-JJ)." }
    $id = "$($item.id)".Trim()
    if (-not $id) { $id = [guid]::NewGuid().ToString('N').Substring(0, 12) }

    $entry = [ordered]@{ id = $id; kind = $kind; title = $title; text = "$($item.text)".Trim(); audience = $audience }
    if ($until) { $entry['until'] = $until }
    $url = Get-Link "$($item.url)"
    if ($url) { $entry['url'] = $url }
    $image = Get-Link "$($item.image)"
    if ($image) { $entry['image'] = $image }
    $announcements.Add($entry)
}

$out = [ordered]@{
    schema        = 1
    updated       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    twitch        = $twitch.ToArray()
    announcements = $announcements.ToArray()
}

Write-Host "Annonces : $($announcements.Count) · Twitch : $(if ($twitch.Count) { $twitch -join ', ' } else { 'aucune chaîne' })" -ForegroundColor Cyan
foreach ($entry in $announcements) { Write-Host "  [$($entry.kind)] $($entry.title)" }
if (-not $Yes) {
    $answer = Read-Host 'Publier ces annonces ? (o/N)'
    if ($answer -notmatch '^[oOyY]') { Write-Host 'Annulé.'; return }
}

Assert-Signing
Write-SignedManifest $out $NewsPath

git -C $Root add channels/news.json channels/news.json.sig
Assert-LastExit 'git add'
if (Test-Path (Join-Path $Root 'news')) {
    git -C $Root add news
    Assert-LastExit 'git add'
}
git -C $Root diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host 'Rien n''a changé.' -ForegroundColor Green
    return
}
git -C $Root commit --quiet -m 'Met à jour les annonces du launcher'
Assert-LastExit 'git commit'
git -C $Root push --quiet
Assert-LastExit 'git push'

Write-Host 'Annonces en ligne : les launchers les affichent dans les minutes qui viennent.' -ForegroundColor Green
