param(
    # Note de version des joueurs, écrite dans l'atelier du launcher : { title, image, changes: [{ kind, text }] }.
    # Sans elle, la note réunit tout ce qui a été publié sur dev depuis la dernière prod.
    [string]$ChangesFile = '',
    [switch]$DryRun,
    [switch]$Yes,
    # Résumé lisible par l'atelier du launcher (avec -DryRun).
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'signing.ps1')
. (Join-Path $PSScriptRoot 'releases.ps1')
$DevPath = Join-Path $Root 'channels\dev.json'
$ProdPath = Join-Path $Root 'channels\prod.json'

function Assert-LastExit([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step a échoué (code $LASTEXITCODE)." }
}

if (-not (Test-Path $DevPath)) { throw "Rien à promouvoir : aucune version n'a encore été publiée sur dev." }
$dev = Get-Content $DevPath -Raw -Encoding UTF8 | ConvertFrom-Json
$prod = $null
if (Test-Path $ProdPath) { $prod = Get-Content $ProdPath -Raw -Encoding UTF8 | ConvertFrom-Json }
$from = if ($prod) { $prod.version } else { 'aucune' }
$pending = Get-PendingReleases $dev $prod

if ($Json) {
    Write-Output ('HARPY_JSON:' + ([ordered]@{
        devVersion  = $dev.version
        prodVersion = $(if ($prod) { $prod.version } else { $null })
        nothing     = [bool]($prod -and $prod.version -eq $dev.version)
        pending     = $pending
    } | ConvertTo-Json -Compress -Depth 10))
    return
}

if ($prod -and $prod.version -eq $dev.version) {
    Write-Host "La prod est déjà en $($dev.version)." -ForegroundColor Green
    return
}

if ($ChangesFile) {
    $release = Read-ReleaseNotes $ChangesFile
} else {
    $release = [ordered]@{ title = ''; image = ''; changes = (Merge-Changes $pending) }
}

Write-Host "Prod : $from -> $($dev.version)" -ForegroundColor Cyan
Write-Host "Versions dev incluses : $((@($pending) | ForEach-Object { $_.version }) -join ', ')"
if ($release.title) { Write-Host $release.title -ForegroundColor Yellow }
Format-Changes $release.changes | ForEach-Object { Write-Host "  $_" }
if (-not $release.changes) { Write-Host '  (aucune nouveauté écrite : les joueurs ne verront que le numéro de version)' -ForegroundColor DarkYellow }
if ($DryRun) { return }

if (-not $Yes) {
    $answer = Read-Host 'Envoyer cette version à tous les joueurs ? (o/N)'
    if ($answer -notmatch '^[oOyY]') { Write-Host 'Annulé.'; return }
}

Assert-Signing
# Les fichiers de dev, la note des joueurs, l'historique de la prod (pas le journal de dev).
$out = [ordered]@{
    schema    = 1
    channel   = 'prod'
    version   = $dev.version
    published = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}
if ($release.title) { $out['title'] = $release.title }
if ($release.image) { $out['image'] = $release.image }
foreach ($property in $dev.PSObject.Properties) {
    if (@('schema', 'channel', 'version', 'published', 'title', 'image', 'notes', 'changes', 'history', 'blockedMods', 'files') -contains $property.Name) { continue }
    $out[$property.Name] = $property.Value
}
$out['notes'] = @($release.changes | ForEach-Object { $_.text })
$out['changes'] = $release.changes
$out['history'] = Get-History $prod
$out['blockedMods'] = @($dev.blockedMods)
$out['files'] = @($dev.files)
Write-SignedManifest $out $ProdPath

git -C $Root add channels/prod.json channels/prod.json.sig
Assert-LastExit 'git add'
if (Test-Path (Join-Path $Root 'news')) {
    git -C $Root add news
    Assert-LastExit 'git add'
}
git -C $Root commit --quiet -m "Passe $($dev.version) en prod"
Assert-LastExit 'git commit'
git -C $Root push --quiet
Assert-LastExit 'git push'

Write-Host "Les joueurs recevront $($dev.version) à leur prochain lancement." -ForegroundColor Green
