Set-StrictMode -Version 2.0

function Get-IntelbrasDigestAuthorizationHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Challenge,

        [Parameter(Mandatory = $true)]
        [System.Uri]$Uri,

        [Parameter(Mandatory = $true)]
        [System.Net.NetworkCredential]$Credential
    )

    if ($Challenge -notmatch '^\s*Digest\s+(?<Parameters>.*)$') {
        throw 'A câmera retornou um desafio Digest inválido.'
    }

    $parameters = @{}
    $parameterPattern = '([a-zA-Z][a-zA-Z0-9_-]*)\s*=\s*(?:"((?:\\.|[^"])*)"|([^,\s]+))'
    foreach ($match in [regex]::Matches($Matches.Parameters, $parameterPattern)) {
        $value = if ($match.Groups[2].Success) {
            $match.Groups[2].Value -replace '\\(["\\])', '$1'
        }
        else {
            $match.Groups[3].Value
        }
        $parameters[$match.Groups[1].Value] = $value
    }

    if (-not $parameters.ContainsKey('realm') -or -not $parameters.ContainsKey('nonce')) {
        throw 'O desafio Digest da câmera não contém realm ou nonce.'
    }

    $algorithm = 'MD5'
    if ($parameters.ContainsKey('algorithm')) {
        $algorithm = [string]$parameters['algorithm']
    }
    if ($algorithm -notin @('MD5', 'MD5-sess')) {
        throw "Algoritmo Digest não suportado pela câmera: $algorithm."
    }

    $qop = $null
    if ($parameters.ContainsKey('qop')) {
        $qopOptions = @(([string]$parameters['qop']) -split '\s*,\s*')
        if ($qopOptions -contains 'auth') {
            $qop = 'auth'
        }
        else {
            throw 'O desafio Digest da câmera não oferece qop=auth.'
        }
    }

    $encoding = if ($parameters.ContainsKey('charset') -and $parameters['charset'] -eq 'UTF-8') {
        [System.Text.Encoding]::UTF8
    }
    else {
        [System.Text.Encoding]::GetEncoding(28591)
    }
    $hashText = {
        param([string]$Text)
        $md5 = [System.Security.Cryptography.MD5]::Create()
        try {
            $hash = $md5.ComputeHash($encoding.GetBytes($Text))
            [System.BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $md5.Dispose()
        }
    }

    $username = [string]$Credential.UserName
    $ha1 = & $hashText ('{0}:{1}:{2}' -f $username, $parameters['realm'], $Credential.Password)
    $cnonce = $null
    $nonceCount = $null
    if ($null -ne $qop -or $algorithm -eq 'MD5-sess') {
        $randomBytes = New-Object 'System.Byte[]' 16
        $randomGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $randomGenerator.GetBytes($randomBytes)
        }
        finally {
            $randomGenerator.Dispose()
        }
        $cnonce = [System.BitConverter]::ToString($randomBytes).Replace('-', '').ToLowerInvariant()
    }
    if ($algorithm -eq 'MD5-sess') {
        $ha1 = & $hashText ('{0}:{1}:{2}' -f $ha1, $parameters['nonce'], $cnonce)
    }

    $requestTarget = $Uri.PathAndQuery
    $ha2 = & $hashText ('{0}:{1}' -f 'GET', $requestTarget)
    if ($null -ne $qop) {
        $nonceCount = '00000001'
        $responseHash = & $hashText ('{0}:{1}:{2}:{3}:{4}:{5}' -f `
            $ha1, $parameters['nonce'], $nonceCount, $cnonce, $qop, $ha2)
    }
    else {
        $responseHash = & $hashText ('{0}:{1}:{2}' -f $ha1, $parameters['nonce'], $ha2)
    }

    $quote = {
        param([string]$Value)
        $Value.Replace('\', '\\').Replace('"', '\"')
    }
    $parts = @(
        ('username="{0}"' -f (& $quote $username)),
        ('realm="{0}"' -f (& $quote ([string]$parameters['realm']))),
        ('nonce="{0}"' -f (& $quote ([string]$parameters['nonce']))),
        ('uri="{0}"' -f (& $quote $requestTarget)),
        ('response="{0}"' -f $responseHash)
    )
    if ($parameters.ContainsKey('algorithm')) {
        $parts += 'algorithm={0}' -f $algorithm
    }
    if ($null -ne $qop) {
        $parts += @(
            ('qop={0}' -f $qop),
            ('nc={0}' -f $nonceCount),
            ('cnonce="{0}"' -f $cnonce)
        )
    }
    if ($parameters.ContainsKey('opaque')) {
        $parts += 'opaque="{0}"' -f (& $quote ([string]$parameters['opaque']))
    }

    'Digest {0}' -f ($parts -join ', ')
}

<#
.SYNOPSIS
Faz uma requisição GET CGI à câmera sem incluir credenciais na URL.

.DESCRIPTION
Monta a URL com UriBuilder, envia a requisição com timeout e devolve o código
HTTP, corpo e duração. Responde manualmente a desafios Digest para garantir
que o URI autenticado inclua a query CGI; outras autenticações usam o cliente
HTTP do Windows.

.PARAMETER Camera
Objeto com Ip e HttpPort.

.PARAMETER Query
Query CGI sem ponto de interrogação inicial.

.PARAMETER Credential
Credencial opcional para autenticação HTTP.

.PARAMETER TimeoutMilliseconds
Tempo máximo de espera pela resposta.

.OUTPUTS
PSCustomObject com StatusCode, Body, Uri e ElapsedMilliseconds.

.EXAMPLE
Invoke-IntelbrasCgiRequest -Camera $camera -Query 'action=getConfig&name=VideoInOptions'

.NOTES
Documentação: docs/INTELBRAS-CGI.md#consulta-de-configuracao
Nunca registrar credenciais nem cabeçalhos Authorization.

.LINK
docs/INTELBRAS-CGI.md
#>
# DOC: docs/INTELBRAS-CGI.md#consulta-de-configuracao
function Invoke-IntelbrasCgiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Camera,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Query,

        [System.Management.Automation.PSCredential]$Credential,

        [ValidateRange(100, 30000)]
        [int]$TimeoutMilliseconds = 4000
    )

    $builder = New-Object System.UriBuilder
    $builder.Scheme = 'http'
    $builder.Host = [string]$Camera.Ip
    $builder.Port = [int]$Camera.HttpPort
    $builder.Path = '/cgi-bin/configManager.cgi'
    $builder.Query = $Query
    $uriText = $builder.Uri.AbsoluteUri
    if ($Query -match '^action=setConfig&VideoInOptions\[0\]\.(Flip|Mirror)=(true|false)$') {
        # Preserve the CGI index syntax required by the camera firmware.
        $uriText = $uriText.Replace('VideoInOptions%5B0%5D.', 'VideoInOptions[0].')
    }
    $uri = [System.Uri]::new($uriText, $true)

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $response = $null
    $statusCode = $null
    $body = ''
    try {
        $authorizationHeader = $null
        $useCredentialFallback = $false
        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            $request = [System.Net.HttpWebRequest]::Create($uri)
            $request.Method = 'GET'
            $request.Timeout = $TimeoutMilliseconds
            $request.ReadWriteTimeout = $TimeoutMilliseconds
            $request.AllowAutoRedirect = $false
            $request.Proxy = $null
            if ($null -ne $authorizationHeader) {
                $request.Headers['Authorization'] = $authorizationHeader
            }
            elseif ($useCredentialFallback -and $null -ne $Credential) {
                $request.Credentials = $Credential.GetNetworkCredential()
                $request.PreAuthenticate = $true
            }

            $response = $null
            try {
                try {
                    $response = [System.Net.HttpWebResponse]$request.GetResponse()
                }
                catch [System.Net.WebException] {
                    if ($null -eq $_.Exception.Response) {
                        throw
                    }
                    $response = [System.Net.HttpWebResponse]$_.Exception.Response
                }

                $statusCode = [int]$response.StatusCode
                if ($statusCode -eq 401 -and $null -ne $Credential -and $attempt -lt 2) {
                    $digestChallenge = @($response.Headers.GetValues('WWW-Authenticate') |
                        Where-Object { $_ -match '^\s*Digest\s+' } |
                        Select-Object -First 1)
                    if ($digestChallenge.Count -gt 0) {
                        $authorizationHeader = Get-IntelbrasDigestAuthorizationHeader `
                            -Challenge $digestChallenge[0] -Uri $uri `
                            -Credential $Credential.GetNetworkCredential()
                        $useCredentialFallback = $false
                    }
                    elseif (-not $useCredentialFallback) {
                        $authorizationHeader = $null
                        $useCredentialFallback = $true
                    }
                    else {
                        $digestChallenge = @()
                    }

                    if ($digestChallenge.Count -gt 0 -or $useCredentialFallback) {
                        $response.Close()
                        $response = $null
                        $request.Abort()
                        continue
                    }
                }

                $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
                try {
                    $body = $reader.ReadToEnd()
                }
                finally {
                    $reader.Dispose()
                }
                break
            }
            finally {
                if ($null -ne $response) {
                    $response.Close()
                }
                $request.Abort()
            }
        }
    }
    finally {
        $stopwatch.Stop()
    }

    [pscustomobject]@{
        StatusCode          = $statusCode
        Body                = $body
        Uri                 = $uri.AbsoluteUri
        ElapsedMilliseconds = $stopwatch.ElapsedMilliseconds
    }
}

<#
.SYNOPSIS
Interpreta os parâmetros Flip e Mirror de uma resposta VideoInOptions.

.DESCRIPTION
Analisa todas as linhas table.VideoInOptions[0] para exibição e converte
Flip e Mirror para booleano. Propriedades ausentes permanecem nulas.

.PARAMETER ResponseText
Texto retornado pelo endpoint CGI.

.OUTPUTS
PSCustomObject com Flip e Mirror booleanos ou nulos, além da lista Parameters
com todos os nomes e valores recebidos.

.EXAMPLE
$options = ConvertFrom-IntelbrasVideoOptions -ResponseText $response

.NOTES
Documentação: docs/INTELBRAS-CGI.md#resposta-e-conversao

.LINK
docs/INTELBRAS-CGI.md
#>
# DOC: docs/INTELBRAS-CGI.md#resposta-e-conversao
function ConvertFrom-IntelbrasVideoOptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ResponseText
    )

    $values = @{
        Flip   = $null
        Mirror = $null
    }
    $parameters = @()
    foreach ($line in ($ResponseText -split "`r?`n")) {
        if ($line -match '^\s*table\.VideoInOptions\[0\]\.(?<Name>[^=]+?)\s*=\s*(?<Value>.*)\s*$') {
            $name = $Matches.Name
            $value = $Matches.Value
            $parameters += [pscustomobject]@{
                Name  = $name
                Value = $value
            }
            if ($name -in @('Flip', 'Mirror') -and $value -match '^(true|false)$') {
                $values[$name] = [System.Boolean]::Parse($value)
            }
        }
    }

    [pscustomobject]@{
        Flip       = $values.Flip
        Mirror     = $values.Mirror
        Parameters = @($parameters)
    }
}

<#
.SYNOPSIS
Consulta os parâmetros VideoInOptions de uma câmera Intelbras.

.DESCRIPTION
Executa configManager.cgi?action=getConfig&name=VideoInOptions e converte
Flip e Mirror para valores booleanos. Em erros HTTP, preserva URL e corpo da
resposta para diagnóstico somente visual em modo DEBUG.

.PARAMETER Camera
Objeto com Ip e HttpPort.

.PARAMETER Credential
Credencial HTTP opcional.

.PARAMETER TimeoutMilliseconds
Tempo máximo da requisição.

.OUTPUTS
PSCustomObject com Flip, Mirror, RawResponse, StatusCode, Uri e duração.

.EXAMPLE
$options = Get-IntelbrasVideoOptions -Camera $camera

.NOTES
Documentação: docs/INTELBRAS-CGI.md#consulta-de-configuracao
Nunca registrar credenciais nem cabeçalhos Authorization.

.LINK
docs/INTELBRAS-CGI.md
#>
# DOC: docs/INTELBRAS-CGI.md#consulta-de-configuracao
function Get-IntelbrasVideoOptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Camera,

        [System.Management.Automation.PSCredential]$Credential,

        [ValidateRange(100, 30000)]
        [int]$TimeoutMilliseconds = 4000
    )

    $response = Invoke-IntelbrasCgiRequest -Camera $Camera `
        -Query 'action=getConfig&name=VideoInOptions' `
        -Credential $Credential -TimeoutMilliseconds $TimeoutMilliseconds
    if ($response.StatusCode -ne 200) {
        $exception = New-Object System.InvalidOperationException(
            "CGI VideoInOptions retornou HTTP $($response.StatusCode)."
        )
        $responseBody = [string]$response.Body
        if ($responseBody.Length -gt 1000) {
            $responseBody = $responseBody.Substring(0, 1000) + '...'
        }
        $exception.Data['RequestUri'] = $response.Uri
        $exception.Data['ResponseBody'] = $responseBody
        throw $exception
    }

    $parsed = ConvertFrom-IntelbrasVideoOptions -ResponseText $response.Body
    [pscustomobject]@{
        Flip                = $parsed.Flip
        Mirror              = $parsed.Mirror
        Parameters          = $parsed.Parameters
        RawResponse         = $response.Body
        StatusCode          = $response.StatusCode
        Uri                 = $response.Uri
        ElapsedMilliseconds = $response.ElapsedMilliseconds
    }
}

<#
.SYNOPSIS
Define Flip e confirma o valor lendo novamente a configuração.

.DESCRIPTION
Envia setConfig somente se ShouldProcess permitir, exige resposta OK e depois
consulta VideoInOptions. Sucesso só é confirmado se a releitura corresponder.
Erros HTTP preservam detalhes da resposta para diagnóstico visual em DEBUG.

.PARAMETER Camera
Objeto com Ip e HttpPort.

.PARAMETER Value
Valor booleano solicitado para Flip.

.PARAMETER Credential
Credencial HTTP opcional.

.PARAMETER TimeoutMilliseconds
Tempo máximo por requisição.

.OUTPUTS
PSCustomObject com Accepted, Verified, RequestedValue, ActualValue e resposta.

.EXAMPLE
Set-IntelbrasFlip -Camera $camera -Value $false -Confirm

.NOTES
Documentação: docs/INTELBRAS-CGI.md#flip

.LINK
docs/INTELBRAS-CGI.md
#>
# DOC: docs/INTELBRAS-CGI.md#flip
function Set-IntelbrasFlip {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Camera,

        [Parameter(Mandatory = $true)]
        [bool]$Value,

        [System.Management.Automation.PSCredential]$Credential,

        [ValidateRange(100, 30000)]
        [int]$TimeoutMilliseconds = 4000
    )

    $target = '{0} (Flip)' -f $Camera.Ip
    $approved = $PSCmdlet.ShouldProcess($target, ("Definir Flip={0}" -f $Value.ToString().ToLowerInvariant()))
    Set-IntelbrasVideoOption -Camera $Camera -Name 'Flip' -Value $Value `
        -Credential $Credential -TimeoutMilliseconds $TimeoutMilliseconds -Approved $approved
}

<#
.SYNOPSIS
Define Mirror e confirma o valor lendo novamente a configuração.

.DESCRIPTION
Envia setConfig somente se ShouldProcess permitir, exige resposta OK e depois
consulta VideoInOptions. A escrita de Mirror é experimental e deve ser
confirmada em cada modelo; sucesso só é informado após a releitura.

.PARAMETER Camera
Objeto com Ip e HttpPort.

.PARAMETER Value
Valor booleano solicitado para Mirror.

.PARAMETER Credential
Credencial HTTP opcional.

.PARAMETER TimeoutMilliseconds
Tempo máximo por requisição.

.OUTPUTS
PSCustomObject com Accepted, Verified, RequestedValue, ActualValue e resposta.

.EXAMPLE
Set-IntelbrasMirror -Camera $camera -Value $false -Confirm

.NOTES
Documentação: docs/INTELBRAS-CGI.md#mirror

.LINK
docs/INTELBRAS-CGI.md
#>
# DOC: docs/INTELBRAS-CGI.md#mirror
function Set-IntelbrasMirror {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Camera,

        [Parameter(Mandatory = $true)]
        [bool]$Value,

        [System.Management.Automation.PSCredential]$Credential,

        [ValidateRange(100, 30000)]
        [int]$TimeoutMilliseconds = 4000
    )

    $target = '{0} (Mirror)' -f $Camera.Ip
    $approved = $PSCmdlet.ShouldProcess($target, ("Definir Mirror={0}" -f $Value.ToString().ToLowerInvariant()))
    Set-IntelbrasVideoOption -Camera $Camera -Name 'Mirror' -Value $Value `
        -Credential $Credential -TimeoutMilliseconds $TimeoutMilliseconds -Approved $approved
}

<#
.SYNOPSIS
Executa uma alteração VideoInOptions e verifica o valor relido.

.DESCRIPTION
Função interna compartilhada pelos comandos de Flip e Mirror. Não anuncia
sucesso confirmado quando a câmera aceita o comando mas mantém o valor anterior.

.PARAMETER Camera
Objeto com Ip e HttpPort.

.PARAMETER Name
Nome do único parâmetro de vídeo que será atualizado.

.PARAMETER Value
Valor booleano solicitado.

.PARAMETER Credential
Credencial HTTP opcional.

.PARAMETER TimeoutMilliseconds
Tempo máximo por requisição.

.PARAMETER Approved
Indica se o ShouldProcess do comando público autorizou a alteração.

.OUTPUTS
PSCustomObject com Accepted, Verified, RequestedValue, ActualValue e resposta.

.EXAMPLE
Set-IntelbrasVideoOption -Camera $camera -Name Flip -Value $false

.NOTES
Documentação: docs/INTELBRAS-CGI.md#flip

.LINK
docs/INTELBRAS-CGI.md
#>
# DOC: docs/INTELBRAS-CGI.md#flip
function Set-IntelbrasVideoOption {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Camera,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Flip', 'Mirror')]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [bool]$Value,

        [System.Management.Automation.PSCredential]$Credential,

        [int]$TimeoutMilliseconds = 4000,

        [Parameter(Mandatory = $true)]
        [bool]$Approved
    )

    if (-not $Approved) {
        return [pscustomobject]@{
            Accepted       = $false
            Verified       = $false
            RequestedValue = $Value
            ActualValue    = $null
            Response       = $null
            Uri            = $null
            StatusCode     = $null
            ElapsedMilliseconds = $null
        }
    }

    $setting = "VideoInOptions[0].$Name"
    $valueText = $Value.ToString().ToLowerInvariant()
    $response = Invoke-IntelbrasCgiRequest -Camera $Camera `
        -Query ("action=setConfig&{0}={1}" -f $setting, $valueText) `
        -Credential $Credential -TimeoutMilliseconds $TimeoutMilliseconds
    if ($response.StatusCode -ne 200 -or $response.Body.Trim() -ne 'OK') {
        $exception = New-Object System.InvalidOperationException(
            "A alteração de $Name não foi aceita (HTTP $($response.StatusCode))."
        )
        $responseBody = [string]$response.Body
        if ($responseBody.Length -gt 1000) {
            $responseBody = $responseBody.Substring(0, 1000) + '...'
        }
        $exception.Data['RequestUri'] = $response.Uri
        $exception.Data['ResponseBody'] = $responseBody
        throw $exception
    }

    $actual = $null
    $actualValue = $null
    $verificationError = $null
    $verificationUri = $null
    $verificationResponseBody = $null
    try {
        $actual = Get-IntelbrasVideoOptions -Camera $Camera -Credential $Credential `
            -TimeoutMilliseconds $TimeoutMilliseconds
        $actualValue = $actual.$Name
    }
    catch {
        $verificationError = $_.Exception.Message
        if ($_.Exception.Data.Contains('RequestUri')) {
            $verificationUri = [string]$_.Exception.Data['RequestUri']
        }
        if ($_.Exception.Data.Contains('ResponseBody')) {
            $verificationResponseBody = [string]$_.Exception.Data['ResponseBody']
        }
    }
    [pscustomobject]@{
        Accepted       = $true
        Verified       = ($null -ne $actualValue -and [bool]$actualValue -eq $Value)
        RequestedValue = $Value
        ActualValue    = $actualValue
        VerificationError = $verificationError
        VerificationUri = $verificationUri
        VerificationResponseBody = $verificationResponseBody
        Response       = $response.Body.Trim()
        Uri            = $response.Uri
        StatusCode     = $response.StatusCode
        ElapsedMilliseconds = $response.ElapsedMilliseconds
        Readback       = $actual
    }
}

Export-ModuleMember -Function Invoke-IntelbrasCgiRequest, ConvertFrom-IntelbrasVideoOptions, `
    Get-IntelbrasVideoOptions, Set-IntelbrasFlip, Set-IntelbrasMirror
