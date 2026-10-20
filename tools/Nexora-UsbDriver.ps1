# Nexora 1.2 - Diagnostic/installation explicite du pilote USB/IP Windows.
# Aucune suppression de pilote, aucun changement du mode de signature Windows.
[CmdletBinding()]
param(
    [ValidateSet('Status','Install')]
    [string] $Action = 'Status',
    [string] $InfPath
)
$ErrorActionPreference = 'Stop'

function Get-UsbipCommand {
    $candidates = @()
    if ($env:ProgramFiles) { $candidates += Join-Path $env:ProgramFiles 'USBip\usbip.exe' }
    if (${env:ProgramFiles(x86)}) { $candidates += Join-Path ${env:ProgramFiles(x86)} 'USBip\usbip.exe' }
    foreach ($path in $candidates) {
        if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { return $path }
    }
    $command = Get-Command usbip.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

function Show-Status {
    Write-Host "`n=== Nexora / USB-IP : diagnostic ===" -ForegroundColor Cyan
    $cli = Get-UsbipCommand
    if ($cli) { Write-Host "Client usbip.exe : $cli" -ForegroundColor Green }
    else { Write-Host 'Client usbip.exe : ABSENT' -ForegroundColor Yellow }

    $devices = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
        $_.InstanceId -like 'ROOT\USB\*' -and $_.FriendlyName -match 'USBip|VHCI'
    })
    if ($devices.Count -eq 0) {
        Write-Host 'Contrôleur VHCI USB/IP : INTROUVABLE' -ForegroundColor Yellow
        Write-Host 'Le fichier usbip.exe seul ne prouve pas que le pilote fonctionne.' -ForegroundColor Yellow
    }
    foreach ($device in $devices) {
        $driver = Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
            Where-Object { $_.DeviceID -eq $device.InstanceId } | Select-Object -First 1
        Write-Host "Contrôleur : $($device.FriendlyName) ($($device.InstanceId))"
        Write-Host "État PnP    : $($device.Status)"
        if ($driver) {
            Write-Host "Version     : $($driver.DriverVersion)"
            Write-Host "Signataire  : $($driver.Signer)"
            Write-Host "INF         : $($driver.InfName)"
        }
        if ($device.Status -ne 'OK') {
            Write-Host 'Le pilote est présent mais ne fonctionne pas normalement.' -ForegroundColor Yellow
        }
    }
    if ($cli) {
        Write-Host "`nPorts USB/IP :" -ForegroundColor Cyan
        & $cli port
    }
    return ($devices.Count -gt 0 -and @($devices | Where-Object { $_.Status -eq 'OK' }).Count -gt 0 -and [bool]$cli)
}

function Validate-DriverInf([string] $path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Sélectionnez un fichier INF provenant du paquet USB/IP signé.'
    }
    $resolved = (Resolve-Path -LiteralPath $path).Path
    if ([IO.Path]::GetExtension($resolved).ToLowerInvariant() -ne '.inf') {
        throw 'Le paquet doit être fourni sous forme de fichier .inf.'
    }
    if ($resolved.StartsWith('\\')) { throw 'Copiez le pilote en local avant installation.' }
    if ((Get-Item -LiteralPath $resolved).Length -gt 5MB) { throw 'INF anormalement volumineux.' }
    $text = Get-Content -LiteralPath $resolved -Raw -ErrorAction Stop
    if ($text -notmatch '(?i)usbip|vhci') {
        throw 'Ce fichier INF ne semble pas appartenir au contrôleur USB/IP attendu.'
    }
    $match = [regex]::Match($text, '(?im)^\s*CatalogFile(?:\.NTamd64)?\s*=\s*([^;\r\n]+)')
    if (-not $match.Success) { throw 'Aucun catalogue de signature référencé par ce fichier INF.' }
    $catName = $match.Groups[1].Value.Trim().Trim('"')
    if ($catName -match '[\\/]' -or $catName -match '^\.') {
        throw 'Nom de catalogue invalide.'
    }
    $cat = Join-Path (Split-Path -Parent $resolved) $catName
    if (-not (Test-Path -LiteralPath $cat -PathType Leaf)) {
        throw "Catalogue introuvable : $catName"
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $cat
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) {
        throw "Le catalogue du pilote ne présente pas une signature valide : $($signature.Status)."
    }
    Write-Host "Catalogue signé : $catName" -ForegroundColor Green
    Write-Host "Éditeur         : $($signature.SignerCertificate.Subject)"
    return $resolved
}

if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
    throw 'Nexora USB/IP nécessite Windows.'
}
if ($Action -eq 'Status') {
    [void](Show-Status)
    return
}

if ($Action -eq 'Install') {
    if (-not $InfPath) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Nexora - Choisir le pilote USB/IP signé (.inf)'
        $dialog.Filter = 'Pilote Windows (*.inf)|*.inf'
        if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return }
        $InfPath = $dialog.FileName
    }
    $inf = Validate-DriverInf $InfPath
    Write-Host "`nCeci va installer le pilote $inf dans Windows." -ForegroundColor Yellow
    Write-Host 'Une confirmation administrateur (UAC) sera demandée. Aucune signature Windows ne sera désactivée.'
    $answer = Read-Host 'Confirmer ? (O/N)'
    if ($answer -notin @('O','o','Oui','oui')) {
        Write-Host 'Opération annulée.'
        return
    }
    $systemPnPUtil = Join-Path $env:windir 'System32\pnputil.exe'
    $proc = Start-Process -FilePath $systemPnPUtil -Verb RunAs -PassThru -Wait `
        -ArgumentList @('/add-driver', ('"' + $inf + '"'), '/install')
    if ($proc.ExitCode -ne 0) {
        throw "Échec de pnputil (code $($proc.ExitCode)). Vérifiez la signature, la compatibilité et les droits administrateur."
    }
    Write-Host 'PnPUtil a terminé. Un contrôleur absent peut nécessiter le programme officiel du fournisseur.' -ForegroundColor Green
    [void](Show-Status)
    Write-Host 'Si le contrôleur ne fonctionne pas, ne désactivez PAS la vérification des signatures.' -ForegroundColor Yellow
}
