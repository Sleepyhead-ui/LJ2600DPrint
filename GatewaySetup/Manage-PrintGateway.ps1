[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Check', 'Install', 'Uninstall')]
    [string]$Action = 'Check',

    [string]$Gateway = '192.168.1.1',

    [ValidateSet('LJ2600D')]
    [string]$Profile = 'LJ2600D',

    [string]$MacAddress,

    [Management.Automation.PSCredential]$Credential,

    [switch]$IncludeWebPrint,

    [ValidatePattern('^\d{4,12}$')]
    [string]$Pin,

    [string]$ReportPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$setupRoot = $PSScriptRoot
$repositoryRoot = Split-Path -Parent $setupRoot
$probePath = Join-Path $setupRoot 'gateway\probe.sh'
$printPackagePath = Join-Path $setupRoot 'gateway\lj2600d-print'
$openedTelnet = $false
$resolvedMac = $null
$session = $null
$probe = $null

function Test-IPv4Address {
    param([string]$Value)
    $parsed = $null
    return [Net.IPAddress]::TryParse($Value, [ref]$parsed) -and
        $parsed.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork
}

function Test-TcpPort {
    param([string]$HostName, [int]$Port, [int]$TimeoutMs = 1500)
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $task = $client.ConnectAsync($HostName, $Port)
        return $task.Wait($TimeoutMs) -and $client.Connected
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Get-NormalizedMac {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $normalized = ($Value -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if ($normalized.Length -ne 12) { throw 'MAC address must contain exactly 12 hexadecimal digits.' }
    $normalized
}

function Find-GatewayMac {
    param([string]$HostName, [string]$ExplicitMac)
    $normalized = Get-NormalizedMac -Value $ExplicitMac
    if ($normalized) { return $normalized }

    [void](Test-Connection -ComputerName $HostName -Count 1 -Quiet -ErrorAction SilentlyContinue)
    if (Get-Command Get-NetNeighbor -ErrorAction SilentlyContinue) {
        $neighbor = Get-NetNeighbor -IPAddress $HostName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object LinkLayerAddress -Match '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}' |
            Select-Object -First 1
        if ($neighbor) { return Get-NormalizedMac -Value $neighbor.LinkLayerAddress }
    }

    $arpOutput = & arp -a $HostName 2>$null
    $match = [regex]::Match(($arpOutput -join "`n"), '([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}')
    if ($match.Success) { return Get-NormalizedMac -Value $match.Value }
    throw 'Cannot determine the gateway MAC address. Supply -MacAddress explicitly.'
}

function Set-FiberHomeTelnet {
    param([bool]$Enabled, [string]$HostName, [string]$Mac)
    $flag = if ($Enabled) { '1' } else { '0' }
    $response = Invoke-WebRequest -UseBasicParsing `
        -Uri "http://$HostName/cgi-bin/telnetenable.cgi?telnetenable=$flag&key=$Mac" `
        -TimeoutSec 8
    if ($response.StatusCode -ne 200 -or $response.Content -notmatch 'telnet') {
        throw 'The gateway did not accept the FiberHome Telnet control request.'
    }
}

function Read-AvailableText {
    param([Net.Sockets.NetworkStream]$Stream, [int]$Milliseconds = 220)
    $builder = [Text.StringBuilder]::new()
    $deadline = [DateTime]::Now.AddMilliseconds($Milliseconds)
    while ([DateTime]::Now -lt $deadline) {
        if ($Stream.DataAvailable) {
            $buffer = [byte[]]::new(8192)
            $count = $Stream.Read($buffer, 0, $buffer.Length)
            if ($count -le 0) { break }
            [void]$builder.Append([Text.Encoding]::ASCII.GetString($buffer, 0, $count))
        } else {
            Start-Sleep -Milliseconds 25
        }
    }
    $builder.ToString()
}

function Wait-ForText {
    param(
        [Net.Sockets.NetworkStream]$Stream,
        [string]$Pattern,
        [int]$TimeoutMs = 6000
    )
    $received = ''
    $deadline = [DateTime]::Now.AddMilliseconds($TimeoutMs)
    while ([DateTime]::Now -lt $deadline) {
        $received += Read-AvailableText -Stream $Stream
        if ($received -match $Pattern) { return $received }
    }
    throw "Timed out waiting for gateway response: $Pattern"
}

function Send-Line {
    param([Net.Sockets.NetworkStream]$Stream, [string]$Line)
    $bytes = [Text.Encoding]::ASCII.GetBytes($Line + "`r`n")
    $Stream.Write($bytes, 0, $bytes.Length)
    $Stream.Flush()
}

function Invoke-RemoteCommand {
    param(
        [Net.Sockets.NetworkStream]$Stream,
        [string]$Command,
        [int]$TimeoutMs = 10000
    )
    $marker = '__LJPG_' + [Guid]::NewGuid().ToString('N').Substring(0, 12) + '__'
    Send-Line -Stream $Stream -Line "$Command; code=`$?; echo $marker`$code"
    try {
        $response = Wait-ForText -Stream $Stream `
            -Pattern ([regex]::Escape($marker) + '\d+') `
            -TimeoutMs $TimeoutMs
    } catch {
        throw "Timed out running gateway command: $Command"
    }
    $match = [regex]::Match($response, [regex]::Escape($marker) + '(\d+)')
    if (-not $match.Success -or [int]$match.Groups[1].Value -ne 0) {
        $clean = $response -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
        throw "Gateway command failed: $Command`n$clean"
    }
    $response.Substring(0, $match.Index)
}

function Open-GatewaySession {
    param(
        [string]$HostName,
        [string]$Mac,
        [Management.Automation.PSCredential]$LoginCredential
    )
    if (-not (Test-TcpPort -HostName $HostName -Port 23)) {
        Set-FiberHomeTelnet -Enabled $true -HostName $HostName -Mac $Mac
        $script:openedTelnet = $true
        Start-Sleep -Milliseconds 700
        if (-not (Test-TcpPort -HostName $HostName -Port 23 -TimeoutMs 2500)) {
            throw 'Telnet was requested but TCP port 23 did not open.'
        }
    }

    if ($LoginCredential) {
        $username = $LoginCredential.UserName
        $password = $LoginCredential.GetNetworkCredential().Password
    } else {
        if ([string]::IsNullOrWhiteSpace($Mac)) {
            throw 'A gateway MAC address is required for the FiberHome derived credential.'
        }
        $username = 'admin'
        $password = 'Fh@' + $Mac.Substring($Mac.Length - 6)
    }

    $client = [Net.Sockets.TcpClient]::new()
    try {
        $client.Connect($HostName, 23)
        $stream = $client.GetStream()
        [void](Wait-ForText -Stream $stream -Pattern 'login\s*:')
        Send-Line -Stream $stream -Line $username
        [void](Wait-ForText -Stream $stream -Pattern 'Password\s*:')
        Send-Line -Stream $stream -Line $password
        $login = Wait-ForText -Stream $stream -Pattern 'Login incorrect|(?m)[#$]\s*$'
        if ($login -match 'Login incorrect') { throw 'Telnet authentication failed.' }
        [pscustomobject]@{ Client = $client; Stream = $stream }
    } catch {
        $client.Dispose()
        throw
    }
}

function Close-GatewaySession {
    param($GatewaySession)
    if (-not $GatewaySession) { return }
    try { Send-Line -Stream $GatewaySession.Stream -Line 'exit' } catch { }
    $GatewaySession.Stream.Dispose()
    $GatewaySession.Client.Dispose()
}

function Send-Base64File {
    param(
        [Net.Sockets.NetworkStream]$Stream,
        [byte[]]$Bytes,
        [string]$RemotePath,
        [string]$Activity = 'Uploading probe'
    )
    $base64 = [Convert]::ToBase64String($Bytes)
    $remoteBase64 = $RemotePath + '.b64'
    [void](Invoke-RemoteCommand -Stream $Stream -Command ": > '$remoteBase64'")
    $chunkSize = 720
    $chunkCount = [Math]::Ceiling($base64.Length / $chunkSize)
    for ($offset = 0; $offset -lt $base64.Length; $offset += $chunkSize) {
        $length = [Math]::Min($chunkSize, $base64.Length - $offset)
        $chunk = $base64.Substring($offset, $length)
        [void](Invoke-RemoteCommand -Stream $Stream `
            -Command "printf '%s' '$chunk' >> '$remoteBase64'")
        $index = [Math]::Floor($offset / $chunkSize) + 1
        Write-Progress -Activity $Activity -Status "$index / $chunkCount" `
            -PercentComplete (100 * $index / $chunkCount)
    }
    Write-Progress -Activity $Activity -Completed
    [void](Invoke-RemoteCommand -Stream $Stream `
        -Command "base64 -d '$remoteBase64' > '$RemotePath' && rm -f '$remoteBase64'" `
        -TimeoutMs 20000)
}

function Invoke-GatewayProbe {
    param([Net.Sockets.NetworkStream]$Stream)
    $probeText = [IO.File]::ReadAllText($probePath).Replace("`r`n", "`n")
    $probeBytes = [Text.UTF8Encoding]::new($false).GetBytes($probeText)
    Send-Base64File -Stream $Stream -Bytes $probeBytes `
        -RemotePath '/var/tmp/lj2600d-gateway-probe.sh' -Activity 'Uploading read-only probe'
    $output = Invoke-RemoteCommand -Stream $Stream `
        -Command 'sh /var/tmp/lj2600d-gateway-probe.sh; result=$?; rm -f /var/tmp/lj2600d-gateway-probe.sh; test $result -eq 0' `
        -TimeoutMs 20000
    $result = [ordered]@{}
    foreach ($match in [regex]::Matches($output, '(?m)^LJPG_([A-Z0-9_]+)=([^\r\n]*)')) {
        $result[$match.Groups[1].Value] = $match.Groups[2].Value.Trim()
    }
    if (-not $result.Contains('PROBE_VERSION')) {
        throw "The gateway probe did not return machine-readable output.`n$output"
    }
    $result
}

function Get-LocalPortSummary {
    param([string]$HostName)
    $summary = [ordered]@{}
    foreach ($port in 23, 80, 515, 631, 8631) {
        $summary[[string]$port] = if (Test-TcpPort -HostName $HostName -Port $port) { 'open' } else { 'closed' }
    }
    $summary
}

function Format-Kilobytes {
    param([string]$Value)
    $number = 0L
    if ([long]::TryParse($Value, [ref]$number)) {
        return ('{0:N1} MB' -f ($number / 1024.0))
    }
    $Value
}

function New-CompatibilityReport {
    param(
        [Collections.IDictionary]$ProbeResult,
        [Collections.IDictionary]$LocalPorts
    )
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('LJ2600D Print Gateway Compatibility Report')
    $lines.Add(('Generated: {0:yyyy-MM-dd HH:mm:ss zzz}' -f [DateTimeOffset]::Now))
    $lines.Add("Gateway: $Gateway")
    $lines.Add("Profile: $Profile")
    $lines.Add('')
    $lines.Add("Compatibility grade: $($ProbeResult.GRADE)")
    $lines.Add("Assessment: $($ProbeResult.REASON)")
    $lines.Add("Automatic install: $($ProbeResult.AUTO_INSTALL)")
    $lines.Add('Printer language: requires a real LJ2600D print test')
    $lines.Add('')
    $lines.Add('Gateway')
    $lines.Add("  System: $($ProbeResult.SYSTEM)")
    $lines.Add("  Architecture: $($ProbeResult.ARCH)")
    $lines.Add("  Kernel: $($ProbeResult.KERNEL)")
    $lines.Add("  BusyBox: $($ProbeResult.BUSYBOX)")
    $lines.Add("  Available memory: $(Format-Kilobytes $ProbeResult.MEM_AVAILABLE_KB)")
    $lines.Add("  Persistent storage: $($ProbeResult.PERSIST_PATH), free $(Format-Kilobytes $ProbeResult.PERSIST_FREE_KB)")
    $lines.Add("  Startup mechanism: $($ProbeResult.STARTUP)")
    $lines.Add('')
    $lines.Add('USB printer')
    $lines.Add("  Device: $($ProbeResult.PRINTER_DEVICE)")
    $lines.Add("  Driver: $($ProbeResult.USBLP)")
    $lines.Add("  Identity: $($ProbeResult.USB_MANUFACTURER) $($ProbeResult.USB_PRODUCT)")
    $lines.Add("  VID:PID: $($ProbeResult.USB_VID):$($ProbeResult.USB_PID)")
    $lines.Add('')
    $lines.Add('Components')
    foreach ($name in 'TCPSVD', 'LPD', 'SOFTLIMIT', 'HTTPD', 'WGET', 'TAR', 'SHA256SUM', 'BASE64') {
        $lines.Add("  $name`: $($ProbeResult['CMD_' + $name])")
    }
    $lines.Add('')
    $lines.Add('Services seen from this computer')
    foreach ($port in $LocalPorts.Keys) { $lines.Add("  TCP $port`: $($LocalPorts[$port])") }
    $lines.Add('')
    $lines.Add('Existing installation')
    $lines.Add("  Print service: $($ProbeResult.PRINT_SERVICE_INSTALLED)")
    $lines.Add("  Managed by this tool: $($ProbeResult.PRINT_SERVICE_MANAGED)")
    $lines.Add("  Web Print: $($ProbeResult.WEB_SERVICE_INSTALLED)")
    $lines.Add('')
    $lines.Add('Grades: A = supported automatic install; B = LPD capable but startup adaptation required;')
    $lines.Add('C = USB printer visible for temporary forwarding; D = USB printer not detected.')
    $lines -join [Environment]::NewLine
}

function Save-Report {
    param([string]$Content, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $reportDirectory = Join-Path $setupRoot 'reports'
        $fileName = 'gateway-{0:yyyyMMdd-HHmmss}.txt' -f (Get-Date)
        $Path = Join-Path $reportDirectory $fileName
    }
    $resolvedDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $resolvedDirectory)) {
        New-Item -ItemType Directory -Force -Path $resolvedDirectory | Out-Null
    }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($Path), $Content, [Text.UTF8Encoding]::new($false))
    [IO.Path]::GetFullPath($Path)
}

function Get-LocalAddressForGateway {
    param([string]$HostName)
    $udp = [Net.Sockets.UdpClient]::new()
    try {
        $udp.Connect($HostName, 9)
        ([Net.IPEndPoint]$udp.Client.LocalEndPoint).Address.ToString()
    } finally {
        $udp.Dispose()
    }
}

function Start-OneShotArchiveServer {
    param([string]$Archive, [string]$Address, [int]$Port)
    Start-Job -ScriptBlock {
        param($ArchivePath, $BindAddress, $ListenPort)
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse($BindAddress), $ListenPort)
        try {
            $listener.Start()
            Write-Output 'READY'
            $client = $listener.AcceptTcpClient()
            try {
                $stream = $client.GetStream()
                $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
                while ($true) {
                    $line = $reader.ReadLine()
                    if ($null -eq $line -or $line.Length -eq 0) { break }
                }
                $length = (Get-Item -LiteralPath $ArchivePath).Length
                $header = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: application/gzip`r`nContent-Length: $length`r`nConnection: close`r`n`r`n")
                $stream.Write($header, 0, $header.Length)
                $file = [IO.File]::OpenRead($ArchivePath)
                try { $file.CopyTo($stream) } finally { $file.Dispose() }
                $stream.Flush()
                Write-Output 'SENT'
            } finally {
                $client.Dispose()
            }
        } finally {
            $listener.Stop()
        }
    } -ArgumentList $Archive, $Address, $Port
}

function Wait-ArchiveServerReady {
    param([Management.Automation.Job]$Job, [int]$TimeoutMs = 5000)
    $deadline = [DateTime]::Now.AddMilliseconds($TimeoutMs)
    while ([DateTime]::Now -lt $deadline) {
        $output = Receive-Job -Job $Job
        if ($output -contains 'READY') { return $true }
        if ($Job.State -in @('Failed', 'Stopped', 'Completed')) { return $false }
        Start-Sleep -Milliseconds 80
    }
    $false
}

function New-PrintPackage {
    # WhatIf still validates a disposable local archive; it never contacts the gateway.
    $WhatIfPreference = $false
    $stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ('lj2600d-print-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $stagingRoot | Out-Null
    $stageDirectory = Join-Path $stagingRoot 'lj2600d-print'
    Copy-Item -Recurse -Force $printPackagePath $stageDirectory
    foreach ($file in Get-ChildItem -LiteralPath $stageDirectory -Filter '*.sh') {
        $text = [IO.File]::ReadAllText($file.FullName).Replace("`r`n", "`n")
        [IO.File]::WriteAllText($file.FullName, $text, [Text.UTF8Encoding]::new($false))
    }
    $archivePath = Join-Path $stagingRoot 'lj2600d-print.tar.gz'
    & tar -czf $archivePath -C $stagingRoot lj2600d-print
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $archivePath)) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
        throw 'Could not create the print-service package.'
    }
    [pscustomobject]@{
        Root = $stagingRoot
        Archive = $archivePath
        Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash.ToLowerInvariant()
        Bytes = [IO.File]::ReadAllBytes($archivePath)
    }
}

function Send-PrintPackage {
    param([Net.Sockets.NetworkStream]$Stream, $Package)
    [void](Invoke-RemoteCommand -Stream $Stream `
        -Command 'rm -rf /osgi/lj2600d-print-upload && mkdir -p /osgi/lj2600d-print-upload')
    $served = $false
    $serverJob = $null
    try {
        $localAddress = Get-LocalAddressForGateway -HostName $Gateway
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse($localAddress), 0)
        $listener.Start()
        $transferPort = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
        $listener.Stop()
        $serverJob = Start-OneShotArchiveServer -Archive $Package.Archive `
            -Address $localAddress -Port $transferPort
        if (Wait-ArchiveServerReady -Job $serverJob) {
            try {
                [void](Invoke-RemoteCommand -Stream $Stream `
                    -Command "wget -q -O /osgi/lj2600d-print-upload/package.tar.gz http://$localAddress`:$transferPort/lj2600d-print.tar.gz" `
                    -TimeoutMs 30000)
                $served = $true
                Write-Host 'Transferred the package over the local network.' -ForegroundColor Cyan
            } catch {
                Write-Warning 'Direct transfer failed; using Telnet chunks.'
            }
        }
    } finally {
        if ($serverJob) {
            Stop-Job -Job $serverJob -ErrorAction SilentlyContinue
            Remove-Job -Job $serverJob -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $served) {
        Send-Base64File -Stream $Stream -Bytes $Package.Bytes `
            -RemotePath '/osgi/lj2600d-print-upload/package.tar.gz' `
            -Activity 'Uploading print service'
    }
}

function Install-PrintService {
    param([Net.Sockets.NetworkStream]$Stream, $Package)
    Send-PrintPackage -Stream $Stream -Package $Package
    $verify = 'test "$(sha256sum /osgi/lj2600d-print-upload/package.tar.gz | awk ''{print $1}'')" = ''' + $Package.Hash + ''''
    [void](Invoke-RemoteCommand -Stream $Stream -Command $verify -TimeoutMs 20000)
    [void](Invoke-RemoteCommand -Stream $Stream `
        -Command 'mkdir -p /osgi/lj2600d-print-upload/new && tar -xzf /osgi/lj2600d-print-upload/package.tar.gz -C /osgi/lj2600d-print-upload/new && test -f /osgi/lj2600d-print-upload/new/lj2600d-print/install.sh' `
        -TimeoutMs 20000)
    [void](Invoke-RemoteCommand -Stream $Stream `
        -Command 'if [ -d /osgi/lj2600d-print/setup-backup ]; then rm -rf /osgi/lj2600d-print-upload/new/lj2600d-print/setup-backup; cp -a /osgi/lj2600d-print/setup-backup /osgi/lj2600d-print-upload/new/lj2600d-print/setup-backup; fi')
    [void](Invoke-RemoteCommand -Stream $Stream `
        -Command 'rm -rf /osgi/lj2600d-print.previous; if [ -d /osgi/lj2600d-print ]; then mv /osgi/lj2600d-print /osgi/lj2600d-print.previous; fi; mv /osgi/lj2600d-print-upload/new/lj2600d-print /osgi/lj2600d-print; chmod 755 /osgi/lj2600d-print/*.sh')
    try {
        [void](Invoke-RemoteCommand -Stream $Stream `
            -Command ("/osgi/lj2600d-print/install.sh '$Gateway'") -TimeoutMs 30000)
    } catch {
        [void](Invoke-RemoteCommand -Stream $Stream `
            -Command '/osgi/lj2600d-print/uninstall.sh >/dev/null 2>&1 || true; if [ -d /osgi/lj2600d-print.previous ]; then rm -rf /osgi/lj2600d-print; mv /osgi/lj2600d-print.previous /osgi/lj2600d-print; nohup /osgi/lj2600d-print/watch.sh >/var/tmp/lj2600d-watch.launch.log 2>&1 & fi')
        throw
    } finally {
        [void](Invoke-RemoteCommand -Stream $Stream `
            -Command 'rm -rf /osgi/lj2600d-print-upload' -TimeoutMs 10000)
    }
}

if (-not (Test-IPv4Address -Value $Gateway)) { throw 'Gateway must be an IPv4 address.' }
if (-not (Test-Path -LiteralPath $probePath)) { throw "Probe script is missing: $probePath" }
if ($IncludeWebPrint -and $Action -ne 'Install') { throw '-IncludeWebPrint is valid only with -Action Install.' }
if ($IncludeWebPrint -and [string]::IsNullOrWhiteSpace($Pin)) { throw '-Pin is required with -IncludeWebPrint.' }

$localPorts = Get-LocalPortSummary -HostName $Gateway
Write-Host "Gateway $Gateway | 515: $($localPorts['515']) | 8631: $($localPorts['8631'])" -ForegroundColor Cyan

if ($Action -ne 'Check' -and -not $PSCmdlet.ShouldProcess($Gateway, "$Action LJ2600D print service")) {
    if ($Action -eq 'Install') {
        $package = New-PrintPackage
        try {
            Write-Host ("WhatIf package: {0:N0} bytes, SHA-256 {1}" -f $package.Bytes.Length, $package.Hash) -ForegroundColor Cyan
            Write-Host 'Would run the compatibility probe, require grade A, back up startup configuration, install the watchdog, and verify TCP 515.'
        } finally {
            Remove-Item -LiteralPath $package.Root -Recurse -Force -WhatIf:$false
        }
    } else {
        Write-Host 'Would restore the pre-install startup configuration and stop only processes recorded by GatewaySetup.'
    }
    return
}

try {
    if ($Credential -and (Test-TcpPort -HostName $Gateway -Port 23)) {
        $resolvedMac = Get-NormalizedMac -Value $MacAddress
    } else {
        $resolvedMac = Find-GatewayMac -HostName $Gateway -ExplicitMac $MacAddress
    }
    $session = Open-GatewaySession -HostName $Gateway -Mac $resolvedMac -LoginCredential $Credential
    Write-Host 'Connected to the gateway maintenance shell.' -ForegroundColor Cyan
    $probe = Invoke-GatewayProbe -Stream $session.Stream
    $report = New-CompatibilityReport -ProbeResult $probe -LocalPorts $localPorts
    $savedReport = Save-Report -Content $report -Path $ReportPath
    Write-Host "Compatibility: grade $($probe.GRADE) - $($probe.REASON)" -ForegroundColor Green
    Write-Host "Report: $savedReport" -ForegroundColor Green

    if ($Action -eq 'Install') {
        if ($probe.AUTO_INSTALL -ne 'yes' -or $probe.GRADE -ne 'A') {
            throw "Automatic install refused: this gateway is grade $($probe.GRADE) and startup support is $($probe.AUTO_INSTALL)."
        }
        $package = New-PrintPackage
        try {
            Write-Host ("Prepared {0:N0} bytes, SHA-256 {1}" -f $package.Bytes.Length, $package.Hash) -ForegroundColor Cyan
            Install-PrintService -Stream $session.Stream -Package $package
        } finally {
            Remove-Item -LiteralPath $package.Root -Recurse -Force
        }
        if (-not (Test-TcpPort -HostName $Gateway -Port 515 -TimeoutMs 3000)) {
            throw 'Installation completed, but TCP port 515 is not reachable.'
        }
        Write-Host 'Print service installed and TCP port 515 is online.' -ForegroundColor Green
    } elseif ($Action -eq 'Uninstall') {
        if ($probe.PRINT_SERVICE_MANAGED -ne 'yes') {
            throw 'Uninstall refused because the installed service is not marked as managed by GatewaySetup.'
        }
        [void](Invoke-RemoteCommand -Stream $session.Stream `
            -Command '/osgi/lj2600d-print/uninstall.sh' -TimeoutMs 20000)
        Write-Host 'GatewaySetup changes were reverted; files remain for inspection.' -ForegroundColor Green
    }
} finally {
    Close-GatewaySession -GatewaySession $session
    if ($openedTelnet -and $resolvedMac) {
        try {
            Set-FiberHomeTelnet -Enabled $false -HostName $Gateway -Mac $resolvedMac
            Write-Host 'Temporary Telnet access was closed.' -ForegroundColor Cyan
        } catch {
            Write-Warning 'Failed to close Telnet automatically. Close it from the gateway maintenance interface.'
        }
    }
}

if ($Action -eq 'Install' -and $IncludeWebPrint) {
    $webDeploy = Join-Path $repositoryRoot 'WebPrint\scripts\Deploy-LJ2600D-WebPrint.ps1'
    & $webDeploy -Gateway $Gateway -Pin $Pin
    if ($LASTEXITCODE -ne 0) { throw 'The optional Web Print deployment failed.' }
}
