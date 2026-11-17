Set-StrictMode -Version 2.0

<#
.SYNOPSIS
Faz uma requisição GET CGI à câmera sem incluir credenciais na URL.

.DESCRIPTION
Monta a URL com UriBuilder, envia a requisição com timeout e devolve o código
HTTP, corpo e duração. Credenciais são fornecidas apenas por PSCredential.

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

    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.Method = 'GET'
    $request.Timeout = $TimeoutMilliseconds
    $request.ReadWriteTimeout = $TimeoutMilliseconds
    $request.AllowAutoRedirect = $false
    $request.Proxy = $null
    if ($null -ne $Credential) {
        $request.Credentials = $Credential.GetNetworkCredential()
        $request.PreAuthenticate = $true
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $response = $null
    $statusCode = $null
    $body = ''
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
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        try {
            $body = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        if ($null -ne $response) {
            $response.Close()
        }
        $request.Abort()
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
Analisa somente as linhas table.VideoInOptions[0].Flip e Mirror, ignorando
outros parâmetros. Propriedades ausentes permanecem nulas.

.PARAMETER ResponseText
Texto retornado pelo endpoint CGI.

.OUTPUTS
PSCustomObject com Flip e Mirror booleanos ou nulos.

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
    foreach ($line in ($ResponseText -split "`r?`n")) {
        if ($line -match '^\s*table\.VideoInOptions\[0\]\.(Flip|Mirror)\s*=\s*(true|false)\s*$') {
            $key = $Matches[1]
            $values[$key] = [System.Boolean]::Parse($Matches[2])
        }
    }

    [pscustomobject]@{
        Flip   = $values.Flip
        Mirror = $values.Mirror
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
