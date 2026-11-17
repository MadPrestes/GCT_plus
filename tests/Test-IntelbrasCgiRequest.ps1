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

$digestListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$digestListener.Start()
$digestPort = ([System.Net.IPEndPoint]$digestListener.LocalEndpoint).Port
$digestCamera = [pscustomobject]@{
    Ip       = '127.0.0.1'
    HttpPort = $digestPort
}
$digestPassword = ConvertTo-SecureString -String 'test-only-password' -AsPlainText -Force
$digestCredential = New-Object System.Management.Automation.PSCredential('test-user', $digestPassword)
$digestRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
$digestRunspace.Open()
$digestPowerShell = [System.Management.Automation.PowerShell]::Create()
$digestPowerShell.Runspace = $digestRunspace
$null = $digestPowerShell.AddScript({
    param($ModulePath, $Camera, $Credential)
    Import-Module -Name $ModulePath -Force -ErrorAction Stop
    Invoke-IntelbrasCgiRequest -Camera $Camera -Query 'action=getConfig&name=VideoInOptions' -Credential $Credential
}.ToString()).AddArgument($modulePath).AddArgument($digestCamera).AddArgument($digestCredential)
$digestClients = @()
$digestAsyncResult = $null
$digestRequests = @()
try {
    $digestAsyncResult = $digestPowerShell.BeginInvoke()
    for ($requestIndex = 0; $requestIndex -lt 2; $requestIndex++) {
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        while (-not $digestListener.Pending() -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 50
        }
        if (-not $digestListener.Pending()) {
            throw 'Timed out waiting for the local Digest authentication test request.'
        }

        $digestClient = $digestListener.AcceptTcpClient()
        $digestClients += $digestClient
        $digestStream = $digestClient.GetStream()
        $digestReader = [System.IO.StreamReader]::new($digestStream)
        $requestLinesForDigest = @()
        while (($requestLine = $digestReader.ReadLine()) -ne '') {
            $requestLinesForDigest += $requestLine
        }
        $digestRequests += ,$requestLinesForDigest

        if ($requestIndex -eq 0) {
            $statusLine = 'HTTP/1.1 401 Unauthorized'
            $headers = 'WWW-Authenticate: Digest realm="GCTTest", qop="auth", nonce="test-nonce", opaque=""'
            $body = ''
        }
        else {
            $authorization = @($requestLinesForDigest | Where-Object { $_ -match '^Authorization:\s*Digest\s+' })
            if ($authorization.Count -gt 0 -and $authorization[0] -match 'username="test-user"') {
                $statusLine = 'HTTP/1.1 200 OK'
                $headers = ''
                $body = 'OK'
            }
            else {
                $statusLine = 'HTTP/1.1 401 Unauthorized'
                $headers = 'WWW-Authenticate: Digest realm="GCTTest", qop="auth", nonce="test-nonce", opaque=""'
                $body = ''
            }
        }

        $bodyBytes = [System.Text.Encoding]::ASCII.GetBytes($body)
        $headerText = if ([string]::IsNullOrEmpty($headers)) { '' } else { "$headers`r`n" }
        $responseBytes = [System.Text.Encoding]::ASCII.GetBytes(
            "$statusLine`r`n${headerText}Content-Length: $($bodyBytes.Length)`r`nConnection: close`r`n`r`n"
        ) + $bodyBytes
        $digestStream.Write($responseBytes, 0, $responseBytes.Length)
        $digestStream.Close()
        $digestClient.Close()
    }

    $digestResult = @($digestPowerShell.EndInvoke($digestAsyncResult))
    $authorizationLine = @($digestRequests[1] | Where-Object { $_ -match '^Authorization:\s*Digest\s+' })
    if ($authorizationLine.Count -eq 1) {
        $authorizationParameters = @{}
        foreach ($match in [regex]::Matches($authorizationLine[0], '([a-zA-Z]+)=(?:"([^"]*)"|([^,\s]+))')) {
            $parameterValue = if ($match.Groups[2].Success) { $match.Groups[2].Value } else { $match.Groups[3].Value }
            $authorizationParameters[$match.Groups[1].Value] = $parameterValue
        }
        $md5 = [System.Security.Cryptography.MD5]::Create()
        try {
            $ha1Bytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes('test-user:GCTTest:test-only-password'))
            $ha2Bytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes(
                'GET:/cgi-bin/configManager.cgi?action=getConfig&name=VideoInOptions'
            ))
        }
        finally {
            $md5.Dispose()
        }
        $ha1 = [System.BitConverter]::ToString($ha1Bytes).Replace('-', '').ToLowerInvariant()
        $ha2 = [System.BitConverter]::ToString($ha2Bytes).Replace('-', '').ToLowerInvariant()
        $expectedResponseText = '{0}:{1}:{2}:{3}:{4}:{5}' -f `
            $ha1, $authorizationParameters.nonce, $authorizationParameters.nc,
            $authorizationParameters.cnonce, $authorizationParameters.qop, $ha2
        $md5 = [System.Security.Cryptography.MD5]::Create()
        try {
            $expectedResponseBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($expectedResponseText))
        }
        finally {
            $md5.Dispose()
        }
        $expectedResponse = [System.BitConverter]::ToString($expectedResponseBytes).Replace('-', '').ToLowerInvariant()
    }

    $validDigestResponse = $authorizationParameters.response -eq $expectedResponse
    if ($digestResult.Count -ne 1 -or $digestResult[0].StatusCode -ne 200 -or
        $digestResult[0].Body -ne 'OK' -or $authorizationLine.Count -ne 1 -or
        $authorizationParameters.username -ne 'test-user' -or
        $authorizationParameters.uri -ne '/cgi-bin/configManager.cgi?action=getConfig&name=VideoInOptions' -or
        -not $validDigestResponse) {
        $errorText = ($digestPowerShell.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '
        throw "Digest challenge validation failed: status=$($digestResult[0].StatusCode), authHeaderCount=$($authorizationLine.Count), usernameMatched=$($authorizationParameters.username -eq 'test-user'), uriMatched=$($authorizationParameters.uri -eq '/cgi-bin/configManager.cgi?action=getConfig&name=VideoInOptions'), digestMatched=$validDigestResponse. Errors: $errorText"
    }
    Write-Output 'Digest challenge-response test passed (local loopback only; no camera was contacted).'
}
finally {
    foreach ($digestClient in $digestClients) {
        $digestClient.Close()
    }
    if ($null -ne $digestAsyncResult -and -not $digestAsyncResult.IsCompleted) {
        $digestPowerShell.Stop()
    }
    $digestPowerShell.Dispose()
    $digestRunspace.Close()
    $digestRunspace.Dispose()
    $digestListener.Stop()
}
