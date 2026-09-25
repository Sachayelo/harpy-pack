param([switch]$Yes)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$DevPath = Join-Path $Root 'channels\dev.json'
$ProdPath = Join-Path $Root 'channels\prod.json'
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Assert-LastExit([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step a échoué (code $LASTEXITCODE)." }
}

if (-not (Test-Path $DevPath)) { throw "Rien à promouvoir : aucune version n'a encore été publiée sur dev." }
$dev = Get-Content $DevPath -Raw -Encoding UTF8 | ConvertFrom-Json

$from = 'aucune'
if (Test-Path $ProdPath) {
    $prod = Get-Content $ProdPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($prod.version -eq $dev.version) {
        Write-Host "La prod est déjà en $($dev.version)." -ForegroundColor Green
        return
    }
    $from = $prod.version
}

Write-Host "Prod : $from -> $($dev.version)" -ForegroundColor Cyan
if (-not $Yes) {
    $answer = Read-Host 'Envoyer cette version à tous les joueurs ? (o/N)'
    if ($answer -notmatch '^[oOyY]') { Write-Host 'Annulé.'; return }
}

$dev.channel = 'prod'
[System.IO.File]::WriteAllText($ProdPath, ($dev | ConvertTo-Json -Depth 6), $Utf8NoBom)

git -C $Root add channels/prod.json
Assert-LastExit 'git add'
git -C $Root commit --quiet -m "Passe $($dev.version) en prod"
Assert-LastExit 'git commit'
git -C $Root push --quiet
Assert-LastExit 'git push'

Write-Host "Les joueurs recevront $($dev.version) à leur prochain lancement." -ForegroundColor Green
