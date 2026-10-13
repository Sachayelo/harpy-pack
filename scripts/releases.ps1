# Notes de version : ce que les joueurs lisent dans le launcher.
#
# Chaque manifeste porte la note de sa version (title, image, changes) et
# l'historique des versions précédentes de son canal (history). Sur dev, cet
# historique sert de journal : au passage en prod, tout ce qui a été publié sur
# dev depuis la dernière prod est proposé pour écrire la note des joueurs.

$ChangeKinds = @('new', 'balance', 'fix')
$HistoryLimit = 40

function New-Change([string]$Kind, [string]$Text) {
    if ($ChangeKinds -notcontains $Kind) { $Kind = 'new' }
    return [ordered]@{ kind = $Kind; text = $Text.Trim() }
}

# Lignes tapées en console : « Correctif : ... » et « Équilibrage : ... » choisissent la catégorie.
function ConvertTo-Changes([string[]]$Lines) {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($line in $Lines) {
        $text = "$line".Trim()
        if (-not $text) { continue }
        $kind = 'new'
        if ($text -match '^(?i)(correctif|fix)\s*:\s*(.+)$') { $kind = 'fix'; $text = $Matches[2] }
        elseif ($text -match '^(?i)([ée]quilibrage|balance)\s*:\s*(.+)$') { $kind = 'balance'; $text = $Matches[2] }
        elseif ($text -match '^(?i)(nouveau|nouveaut[ée])\s*:\s*(.+)$') { $text = $Matches[2] }
        $list.Add((New-Change $kind $text))
    }
    return , $list.ToArray()
}

# Le fichier JSON écrit par l'atelier du launcher : { title, image, changes: [{ kind, text }] }.
function Read-ReleaseNotes([string]$Path) {
    $data = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($change in @($data.changes)) {
        if (-not $change -or -not "$($change.text)".Trim()) { continue }
        $list.Add((New-Change "$($change.kind)" "$($change.text)"))
    }
    return [ordered]@{
        title   = "$($data.title)".Trim()
        image   = "$($data.image)".Trim()
        changes = $list.ToArray()
    }
}

# Les manifestes d'avant les catégories n'ont que des lignes de texte.
function Get-Changes($Manifest) {
    if ($Manifest.changes) { return , @($Manifest.changes) }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($note in @($Manifest.notes)) { if ($note) { $list.Add((New-Change 'new' "$note")) } }
    return , $list.ToArray()
}

# La version que décrit un manifeste, telle qu'elle entre dans l'historique.
function Get-Release($Manifest) {
    $release = [ordered]@{ version = $Manifest.version; published = $Manifest.published }
    if ($Manifest.title) { $release['title'] = $Manifest.title }
    if ($Manifest.image) { $release['image'] = $Manifest.image }
    $release['changes'] = Get-Changes $Manifest
    return $release
}

# Le manifeste lui-même puis son historique, du plus récent au plus ancien.
function Get-History($Manifest) {
    $list = New-Object System.Collections.Generic.List[object]
    if ($Manifest) {
        $list.Add((Get-Release $Manifest))
        foreach ($release in @($Manifest.history)) {
            if ($release -and $list.Count -lt $HistoryLimit) { $list.Add($release) }
        }
    }
    return , $list.ToArray()
}

# Ce qui a été publié sur dev depuis la version actuellement en prod.
function Get-PendingReleases($Dev, $Prod) {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($release in (Get-History $Dev)) {
        if ($Prod -and $release.version -eq $Prod.version) { break }
        $list.Add($release)
    }
    return , $list.ToArray()
}

# Les nouveautés de plusieurs versions dev en une seule note, sans doublons.
function Merge-Changes($Releases) {
    $seen = @{}
    $list = New-Object System.Collections.Generic.List[object]
    # Du plus ancien au plus récent : l'ordre dans lequel les choses ont été faites.
    $ordered = @($Releases)
    [array]::Reverse($ordered)
    foreach ($release in $ordered) {
        foreach ($change in @($release.changes)) {
            if (-not $change) { continue }
            $key = "$($change.text)".Trim().ToLowerInvariant()
            if (-not $key -or $seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $list.Add((New-Change "$($change.kind)" "$($change.text)"))
        }
    }
    return , $list.ToArray()
}

# Les nouveautés en Markdown, pour les releases GitHub.
function Format-Changes($Changes) {
    $labels = @{ new = 'Nouveautés'; balance = 'Équilibrage'; fix = 'Correctifs' }
    $lines = @()
    foreach ($kind in $ChangeKinds) {
        $items = @($Changes | Where-Object { $_ -and $_.kind -eq $kind })
        if (-not $items) { continue }
        $lines += "$($labels[$kind]) :"
        $lines += ($items | ForEach-Object { "- $($_.text)" })
        $lines += ''
    }
    return $lines
}
