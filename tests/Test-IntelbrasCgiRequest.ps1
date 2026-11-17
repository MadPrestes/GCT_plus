#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot 'Modules\IntelbrasCGI.psm1'
Import-Module -Name $modulePath -Force -ErrorAction Stop

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$camera = [pscustomobject]@{
    Ip       = '127.0.0.1'
    HttpPort = $port
}
$runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
$runspace.Open()
$powerShell = [System.Management.Automation.PowerShell]::Create()
$powerShell.Runspace = $runspace
$null = $powerShell.AddScript({
    param($ModulePath, $Camera)
    Import-Module -Name $ModulePath -Force -ErrorAction Stop
    Set-IntelbrasFlip -Camera $Camera -Value $false -Confirm:$false
}.ToString()).AddArgument($modulePath).AddArgument($camera)

$client = $null
$asyncResult = $null
$requestLines = @()
try {
    $asyncResult = $powerShell.BeginInvoke()
    for ($requestIndex = 0; $requestIndex -lt 2; $requestIndex++) {
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        while (-not $listener.Pending() -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 50
        }
        if (-not $listener.Pending()) {
            throw 'Timed out waiting for a local CGI test request.'
        }

        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()
        $reader = [System.IO.StreamReader]::new($stream)
        $requestLines += $reader.ReadLine()
        while ($reader.ReadLine() -ne '') { }

        if ($requestIndex -eq 0) {
            $statusLine = 'HTTP/1.1 200 OK'
            $body = 'OK'
        }
        else {
            $statusLine = 'HTTP/1.1 400 Bad Request'
            $body = 'Error | Bad Request!'
        }
        $bodyBytes = [System.Text.Encoding]::ASCII.GetBytes($body)
        $responseBytes = [System.Text.Encoding]::ASCII.GetBytes(
            "$statusLine`r`nContent-Length: $($bodyBytes.Length)`r`nConnection: close`r`n`r`n"
        ) + $bodyBytes
        $stream.Write($responseBytes, 0, $responseBytes.Length)
        $stream.Close()
        $client.Close()
        $client = $null
    }

    $result = @($powerShell.EndInvoke($asyncResult))
    if ($requestLines[0] -ne 'GET /cgi-bin/configManager.cgi?action=setConfig&VideoInOptions[0].Flip=false HTTP/1.1') {
        throw "CGI write did not preserve the literal index brackets: $($requestLines[0])"
    }
    if ($requestLines[1] -ne 'GET /cgi-bin/configManager.cgi?action=getConfig&name=VideoInOptions HTTP/1.1') {
        throw "CGI readback used an unexpected request: $($requestLines[1])"
    }
    if ($result.Count -ne 1 -or -not $result[0].Accepted -or $result[0].Verified) {
        $resultText = ConvertTo-Json -InputObject $result -Depth 4 -Compress
        $errorText = ($powerShell.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '
        throw "Expected an accepted, unverified write. Results: $resultText. Errors: $errorText"
    }
    if ($result[0].VerificationError -notmatch 'HTTP 400' -or
        $result[0].VerificationResponseBody -ne 'Error | Bad Request!') {
        throw 'The readback failure details were not returned.'
    }

    Write-Output 'CGI request and failed-readback tests passed (local loopback only; no camera was contacted).'
}
finally {
    if ($null -ne $client) {
        $client.Close()
    }
    if ($null -ne $asyncResult -and -not $asyncResult.IsCompleted) {
        $powerShell.Stop()
    }
    $powerShell.Dispose()
    $runspace.Close()
    $runspace.Dispose()
    $listener.Stop()
}
