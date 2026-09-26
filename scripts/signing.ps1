# Signature des manifestes : les launchers n'installent que ce qui a été publié
# depuis ce PC. La clé est celle des versions du launcher ; elle n'est dans
# aucun dépôt (voir %USERPROFILE%\.harpy).

$SigningKey = Join-Path $env:USERPROFILE '.harpy\launcher-update.key'
$TauriCli = Join-Path $env:USERPROFILE 'Desktop\harpy-launcher\node_modules\.bin\tauri.cmd'

function Assert-Signing {
    if (-not (Test-Path $SigningKey)) { throw "Clé de signature introuvable ($SigningKey)." }
    if (-not (Test-Path $TauriCli)) { throw "Outil de signature introuvable : lance « npm install » dans harpy-launcher." }
}

# Signe le manifeste tel que GitHub le servira : fins de ligne LF, sans BOM.
function Protect-Manifest([string]$Path) {
    $text = [System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding $false))
    Remove-Item "$Path.sig" -ErrorAction SilentlyContinue
    $null = & $TauriCli signer sign -f $SigningKey -p '""' $Path
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$Path.sig")) { throw "La signature de $(Split-Path $Path -Leaf) a échoué." }
}

function Write-SignedManifest($Object, [string]$Path) {
    New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
    [System.IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding $false))
    Protect-Manifest $Path
}
