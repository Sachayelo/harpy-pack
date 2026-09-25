param(
    [ValidateSet('dev', 'prod')]
    [string]$Channel = 'dev',
    [string]$Notes = '',
    [switch]$DryRun,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Root = Split-Path -Parent $PSScriptRoot
$PackDir = Join-Path $Root 'pack'
$ChannelDir = Join-Path $Root 'channels'
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
$Ignored = @('desktop.ini', 'Thumbs.db')

function Get-ModId([string]$JarPath) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($JarPath)
    try {
        $entry = $zip.GetEntry('fabric.mod.json')
        if (-not $entry) { return $null }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally {
        $zip.Dispose()
    }
    try { return ($text | ConvertFrom-Json).id } catch { }
    if ($text -match '"id"\s*:\s*"([^"]+)"') { return $Matches[1] }
    return $null
}

function Read-Manifest([string]$Name) {
    $path = Join-Path $ChannelDir "$Name.json"
    if (Test-Path $path) { return Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json }
    return $null
}

function Write-Json($Object, [string]$Path) {
    New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
    [System.IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 6), $Utf8NoBom)
}

function Assert-LastExit([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step a échoué (code $LASTEXITCODE)." }
}

function Show-List([string]$Title, $Items, [ConsoleColor]$Color) {
    if (-not $Items) { return }
    Write-Host "$Title ($(@($Items).Count))" -ForegroundColor $Color
    foreach ($item in $Items) { Write-Host "  $item" }
}

if (-not (Test-Path $PackDir)) { throw "Dossier introuvable : $PackDir" }

$remote = git -C $Root remote get-url origin
if ($remote -notmatch 'github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$') { throw "Dépôt GitHub introuvable ($remote)." }
$repo = $Matches[1]

Write-Host 'Analyse du pack...'
$entries = New-Object System.Collections.Generic.List[object]
$files = Get-ChildItem $PackDir -Recurse -File |
    Where-Object { $_.Name -notlike '.*' -and $Ignored -notcontains $_.Name } |
    Sort-Object FullName
foreach ($file in $files) {
    $rel = $file.FullName.Substring($PackDir.Length + 1).Replace('\', '/')
    $entry = [ordered]@{ path = $rel }
    if ($rel -like 'mods/*.jar') {
        $id = Get-ModId $file.FullName
        if ($id) { $entry['modId'] = $id }
    }
    $entry['sha256'] = (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLower()
    $entry['size'] = $file.Length
    $entries.Add($entry)
}
if ($entries.Count -eq 0) { throw 'Le dossier pack/ est vide.' }

$dupes = $entries | Where-Object { $_['modId'] } | Group-Object { $_['modId'] } | Where-Object { $_.Count -gt 1 }
if ($dupes) {
    $detail = ($dupes | ForEach-Object { "$($_.Name) : " + (($_.Group | ForEach-Object { $_['path'] }) -join ', ') }) -join "`n  "
    throw "Plusieurs jars ont le même identifiant de mod, Fabric refusera de démarrer :`n  $detail"
}

$known = @{}
$today = Get-Date -Format 'yyyy.MM.dd'
$build = 1
foreach ($name in 'dev', 'prod') {
    $manifest = Read-Manifest $name
    if (-not $manifest) { continue }
    foreach ($f in $manifest.files) { $known[$f.sha256] = $f.url }
    if ($manifest.version -like "$today-*") {
        $n = [int]$manifest.version.Substring($today.Length + 1)
        if ($n -ge $build) { $build = $n + 1 }
    }
}
$version = "$today-$build"
$tag = "v$version"

$current = Read-Manifest $Channel
$previous = @{}
if ($current) { foreach ($f in $current.files) { $previous[$f.path] = $f.sha256 } }
$added = @(); $updated = @(); $removed = @()
$present = @{}
foreach ($e in $entries) {
    $present[$e['path']] = $true
    if (-not $previous.ContainsKey($e['path'])) { $added += $e['path'] }
    elseif ($previous[$e['path']] -ne $e['sha256']) { $updated += $e['path'] }
}
foreach ($p in $previous.Keys) { if (-not $present.ContainsKey($p)) { $removed += $p } }

if ($current -and -not ($added -or $updated -or $removed)) {
    Write-Host "Rien à publier : le canal $Channel est déjà à jour ($($current.version))." -ForegroundColor Green
    return
}

$uploads = New-Object System.Collections.Generic.List[object]
foreach ($e in $entries) {
    if ($known.ContainsKey($e['sha256'])) {
        $e['url'] = $known[$e['sha256']]
        continue
    }
    $asset = ($e['path'] -replace '/', '__') -replace '[^A-Za-z0-9._-]', '_'
    $e['url'] = "https://github.com/$repo/releases/download/$tag/$asset"
    $uploads.Add([pscustomobject]@{ Source = (Join-Path $PackDir $e['path']); Asset = $asset; Size = $e['size'] })
}
$clash = $uploads | Group-Object Asset | Where-Object { $_.Count -gt 1 }
if ($clash) { throw "Deux fichiers portent le même nom une fois envoyés sur GitHub : $($clash.Name -join ', ')" }

$manifestOut = [ordered]@{
    schema    = 1
    channel   = $Channel
    version   = $version
    published = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    minecraft = '1.21.1'
    loader    = 'fabric'
    files     = $entries.ToArray()
}

$uploadMb = (($uploads | Measure-Object Size -Sum).Sum) / 1MB
Write-Host ''
if ($current) { $from = "remplace $($current.version)" } else { $from = 'première publication' }
Write-Host "Canal $Channel : $version ($from)" -ForegroundColor Cyan
Show-List 'Ajoutés' $added Green
Show-List 'Modifiés' $updated Yellow
Show-List 'Retirés' $removed Red
Write-Host ('À envoyer : {0} fichier(s), {1:N1} Mo' -f $uploads.Count, $uploadMb)
Write-Host ''

if ($DryRun) {
    $preview = Join-Path $Root ".preview\$Channel.json"
    Write-Json $manifestOut $preview
    Write-Host "Simulation : rien n'a été envoyé. Aperçu du manifeste : $preview" -ForegroundColor Cyan
    return
}

if (-not $Yes) {
    $answer = Read-Host "Publier sur le canal $Channel ? (o/N)"
    if ($answer -notmatch '^[oOyY]') { Write-Host 'Annulé.'; return }
}

$login = gh api user --jq .login
if ($LASTEXITCODE -ne 0) { throw "GitHub CLI n'est pas connecté : lance « gh auth login »." }

if ($uploads.Count -gt 0) {
    $staging = Join-Path ([System.IO.Path]::GetTempPath()) "harpy-publish-$version"
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory $staging | Out-Null
    $paths = foreach ($u in $uploads) {
        $target = Join-Path $staging $u.Asset
        Copy-Item $u.Source $target
        $target
    }

    $lines = @("Canal : $Channel", '')
    if ($Notes) { $lines += $Notes; $lines += '' }
    if ($added) { $lines += 'Ajoutés :'; $lines += ($added | ForEach-Object { "- $_" }); $lines += '' }
    if ($updated) { $lines += 'Modifiés :'; $lines += ($updated | ForEach-Object { "- $_" }); $lines += '' }
    if ($removed) { $lines += 'Retirés :'; $lines += ($removed | ForEach-Object { "- $_" }) }
    $notesFile = Join-Path $staging 'notes.md'
    [System.IO.File]::WriteAllText($notesFile, ($lines -join "`n"), $Utf8NoBom)

    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    gh release view $tag --repo $repo --json tagName *> $null
    $exists = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $savedPreference

    Write-Host "Envoi de $($uploads.Count) fichier(s) sur GitHub..."
    if (-not $exists) {
        gh release create $tag --repo $repo --title "Harpy Express $version" --notes-file $notesFile
        Assert-LastExit 'La création de la release'
    }
    gh release upload $tag $paths --repo $repo --clobber
    Assert-LastExit "L'envoi des fichiers"
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Json $manifestOut (Join-Path $ChannelDir "$Channel.json")
git -C $Root add -A
Assert-LastExit 'git add'
git -C $Root commit --quiet -m "Publie $version sur $Channel"
Assert-LastExit 'git commit'
git -C $Root push --quiet
Assert-LastExit 'git push'

Write-Host ''
Write-Host "Harpy Express $version est en ligne sur le canal $Channel (publié par $login)." -ForegroundColor Green
