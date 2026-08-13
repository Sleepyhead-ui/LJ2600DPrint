param(
    [string]$Gateway = '192.168.1.1',
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{4,12}$')]
    [string]$Pin
)

$ErrorActionPreference = 'Stop'
$webPrintRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$packageRoot = Join-Path $webPrintRoot 'WebPrint'
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ('lj2600d-web-' + [Guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $stagingRoot 'lj2600d-web.tar.gz'
$openedTelnet = $false

function Test-TcpPort {
    param([string]$HostName, [int]$Port, [int]$TimeoutMs = 1500)
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $task = $client.ConnectAsync($HostName, $Port)
        return $task.Wait($TimeoutMs) -and $client.Connected
    } catch { return $false }
    finally { $client.Dispose() }
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
        } else { Start-Sleep -Milliseconds 25 }
    }
    $builder.ToString()
}

function Wait-ForText {
    param([Net.Sockets.NetworkStream]$Stream, [string]$Pattern, [int]$TimeoutMs = 6000)
    $text = ''
    $deadline = [DateTime]::Now.AddMilliseconds($TimeoutMs)
    while ([DateTime]::Now -lt $deadline) {
        $text += Read-AvailableText -Stream $Stream
        if ($text -match $Pattern) { return $text }
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
    param([Net.Sockets.NetworkStream]$Stream, [string]$Command, [int]$TimeoutMs = 8000)
    $marker = '__CMD_' + [Guid]::NewGuid().ToString('N').Substring(0, 10) + '__'
    Send-Line -Stream $Stream -Line "$Command; code=`$?; echo $marker`$code"
    $response = Wait-ForText -Stream $Stream -Pattern ([regex]::Escape($marker) + '\d+') -TimeoutMs $TimeoutMs
    $match = [regex]::Match($response, [regex]::Escape($marker) + '(\d+)')
    if (-not $match.Success -or [int]$match.Groups[1].Value -ne 0) {
        $clean = $response -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
        throw "Gateway command failed: $Command`n$clean"
    }
    $response
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
                $client.ReceiveTimeout = 8000
                $client.SendTimeout = 20000
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

function Send-ArchiveByTelnet {
    param([Net.Sockets.NetworkStream]$Stream, [string]$Base64)
    [void](Invoke-RemoteCommand -Stream $Stream -Command 'mkdir -p /osgi/lj2600d-web-upload && : > /osgi/lj2600d-web-upload/package.b64')
    $chunkSize = 720
    $chunkCount = [Math]::Ceiling($Base64.Length / $chunkSize)
    for ($offset = 0; $offset -lt $Base64.Length; $offset += $chunkSize) {
        $length = [Math]::Min($chunkSize, $Base64.Length - $offset)
        $chunk = $Base64.Substring($offset, $length)
        [void](Invoke-RemoteCommand -Stream $Stream -Command "printf '%s' '$chunk' >> /osgi/lj2600d-web-upload/package.b64")
        $index = [Math]::Floor($offset / $chunkSize) + 1
        if ($index % 100 -eq 0 -or $index -eq $chunkCount) {
            Write-Progress -Activity 'Uploading Web Print' -Status "$index / $chunkCount chunks" -PercentComplete (100 * $index / $chunkCount)
        }
    }
    Write-Progress -Activity 'Uploading Web Print' -Completed
    [void](Invoke-RemoteCommand -Stream $Stream -Command 'base64 -d /osgi/lj2600d-web-upload/package.b64 > /osgi/lj2600d-web-upload/package.tar.gz' -TimeoutMs 20000)
}

try {
    New-Item -ItemType Directory -Force $stagingRoot | Out-Null
    $stageDirectory = Join-Path $stagingRoot 'lj2600d-web'
    New-Item -ItemType Directory -Force $stageDirectory | Out-Null
    Copy-Item -Recurse -Force (Join-Path $packageRoot 'www') (Join-Path $stageDirectory 'www')
    Copy-Item -Recurse -Force (Join-Path $packageRoot 'gateway\www\*') (Join-Path $stageDirectory 'www')
    Copy-Item -Force (Join-Path $packageRoot 'gateway\httpd.conf') $stageDirectory
    Copy-Item -Force (Join-Path $packageRoot 'gateway\watch-web.sh') $stageDirectory
    Copy-Item -Force (Join-Path $packageRoot 'gateway\install.sh') $stageDirectory
    Copy-Item -Force (Join-Path $packageRoot 'gateway\uninstall.sh') $stageDirectory

    tar -czf $archivePath -C $stagingRoot lj2600d-web
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the deployment archive.' }
    $archiveBytes = [IO.File]::ReadAllBytes($archivePath)
    $archiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash.ToLowerInvariant()
    $archiveBase64 = [Convert]::ToBase64String($archiveBytes)
    Write-Host ("Prepared {0:N0} bytes, SHA-256 {1}" -f $archiveBytes.Length, $archiveHash) -ForegroundColor Cyan

    [void](Test-Connection -ComputerName $Gateway -Count 1 -Quiet -ErrorAction SilentlyContinue)
    $neighbor = Get-NetNeighbor -IPAddress $Gateway -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object LinkLayerAddress -Match '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}' |
        Select-Object -First 1
    if (-not $neighbor) { throw 'Cannot determine gateway MAC address.' }
    $mac = ($neighbor.LinkLayerAddress -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    $password = 'Fh@' + $mac.Substring($mac.Length - 6)

    if (-not (Test-TcpPort -HostName $Gateway -Port 23)) {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "http://$Gateway/cgi-bin/telnetenable.cgi?telnetenable=1&key=$mac" -TimeoutSec 8
        if ($response.StatusCode -ne 200 -or $response.Content -notmatch 'telnet') { throw 'The gateway did not enable Telnet.' }
        $openedTelnet = $true
        Start-Sleep -Milliseconds 600
    }

    $client = [Net.Sockets.TcpClient]::new()
    $stream = $null
    try {
        $client.Connect($Gateway, 23)
        $stream = $client.GetStream()
        [void](Wait-ForText -Stream $stream -Pattern 'login\s*:')
        Send-Line -Stream $stream -Line 'admin'
        [void](Wait-ForText -Stream $stream -Pattern 'Password\s*:')
        Send-Line -Stream $stream -Line $password
        $login = Wait-ForText -Stream $stream -Pattern 'Login incorrect|(?m)[#$]\s*$'
        if ($login -match 'Login incorrect') { throw 'Telnet authentication failed.' }
        [void](Invoke-RemoteCommand -Stream $stream -Command 'rm -rf /osgi/lj2600d-web-upload && mkdir -p /osgi/lj2600d-web-upload')
        $served = $false
        $serverJob = $null
        try {
            $localAddress = Get-LocalAddressForGateway -HostName $Gateway
            $portProbe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse($localAddress), 0)
            $portProbe.Start()
            $transferPort = ([Net.IPEndPoint]$portProbe.LocalEndpoint).Port
            $portProbe.Stop()
            $serverJob = Start-OneShotArchiveServer -Archive $archivePath -Address $localAddress -Port $transferPort
            if (Wait-ArchiveServerReady -Job $serverJob) {
                try {
                    [void](Invoke-RemoteCommand -Stream $stream -Command "wget -q -O /osgi/lj2600d-web-upload/package.tar.gz http://$localAddress`:$transferPort/lj2600d-web.tar.gz" -TimeoutMs 30000)
                    $served = $true
                    Write-Host 'Transferred package over the local network.' -ForegroundColor Cyan
                } catch {
                    Write-Warning 'Direct local transfer failed; falling back to Telnet chunks.'
                }
            }
        } finally {
            if ($serverJob) {
                Stop-Job -Job $serverJob -ErrorAction SilentlyContinue
                Remove-Job -Job $serverJob -Force -ErrorAction SilentlyContinue
            }
        }
        if (-not $served) {
            Send-ArchiveByTelnet -Stream $stream -Base64 $archiveBase64
        }

        $verifyCommand = 'test "$(sha256sum /osgi/lj2600d-web-upload/package.tar.gz | awk ''{print $1}'')" = ''' + $archiveHash + ''''
        [void](Invoke-RemoteCommand -Stream $stream -Command $verifyCommand -TimeoutMs 20000)
        [void](Invoke-RemoteCommand -Stream $stream -Command 'rm -rf /osgi/lj2600d-web-upload/new && mkdir -p /osgi/lj2600d-web-upload/new && tar -xzf /osgi/lj2600d-web-upload/package.tar.gz -C /osgi/lj2600d-web-upload/new && test -f /osgi/lj2600d-web-upload/new/lj2600d-web/www/index.html' -TimeoutMs 20000)
        [void](Invoke-RemoteCommand -Stream $stream -Command 'if [ -f /osgi/lj2600d-web/watch.sh.before-web ]; then cp /osgi/lj2600d-web/watch.sh.before-web /osgi/lj2600d-web-upload/new/lj2600d-web/watch.sh.before-web; fi')
        [void](Invoke-RemoteCommand -Stream $stream -Command 'echo 0 > /osgi/lj2600d-web-upload/had_old; if [ -d /osgi/lj2600d-web ]; then rm -rf /osgi/lj2600d-web.previous; mv /osgi/lj2600d-web /osgi/lj2600d-web.previous; echo 1 > /osgi/lj2600d-web-upload/had_old; fi')
        [void](Invoke-RemoteCommand -Stream $stream -Command 'mv /osgi/lj2600d-web-upload/new/lj2600d-web /osgi/lj2600d-web && chmod 755 /osgi/lj2600d-web/install.sh')
        try {
            [void](Invoke-RemoteCommand -Stream $stream -Command ('/osgi/lj2600d-web/install.sh ' + $Pin) -TimeoutMs 30000)
        } catch {
            [void](Invoke-RemoteCommand -Stream $stream -Command 'rm -rf /osgi/lj2600d-web; if [ "$(cat /osgi/lj2600d-web-upload/had_old 2>/dev/null)" = 1 ]; then mv /osgi/lj2600d-web.previous /osgi/lj2600d-web; nohup /osgi/lj2600d-web/watch-web.sh >/var/tmp/lj2600d-web.launch.log 2>&1 & fi')
            throw
        }
        [void](Invoke-RemoteCommand -Stream $stream -Command 'rm -rf /osgi/lj2600d-web-upload')
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($client) { $client.Dispose() }
    }

    Start-Sleep -Seconds 1
    $status = Invoke-RestMethod -Uri "http://$Gateway`:8631/cgi-bin/status.cgi" -TimeoutSec 8
    if (-not $status.ok -or -not $status.printer) { throw 'Web Print started, but the printer is not ready.' }
    Write-Host "Web Print is ready: http://$Gateway`:8631/" -ForegroundColor Green
} finally {
    if ($openedTelnet) {
        try { Invoke-WebRequest -UseBasicParsing -Uri "http://$Gateway/cgi-bin/telnetenable.cgi?telnetenable=0&key=$mac" -TimeoutSec 8 | Out-Null }
        catch { Write-Warning 'Failed to close Telnet automatically.' }
    }
    if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
}
