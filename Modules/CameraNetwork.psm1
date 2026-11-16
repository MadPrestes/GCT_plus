Set-StrictMode -Version 2.0

<#
.SYNOPSIS
Testa uma porta TCP de um endereço IPv4.

.DESCRIPTION
Abre uma conexão TCP com timeout limitado e devolve o resultado e a duração.
Não depende de ICMP; uma falha de ping não interfere neste teste.

.PARAMETER Address
Endereço IPv4 da câmera.

.PARAMETER Port
Porta TCP a testar.

.PARAMETER TimeoutMilliseconds
Tempo máximo de espera pela conexão.

.OUTPUTS
PSCustomObject com Success, Address, Port, ElapsedMilliseconds e Error.

.EXAMPLE
Test-CameraTcpPort -Address '10.3.29.230' -Port 80

.NOTES
Documentação: docs/NETWORK.md#teste-tcp

.LINK
docs/NETWORK.md
#>
# DOC: docs/NETWORK.md#teste-tcp
function Test-CameraTcpPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Address,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [ValidateRange(100, 30000)]
        [int]$TimeoutMilliseconds = 2000
    )

    $parsedAddress = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsedAddress) -or
        $parsedAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Endereço IPv4 inválido: $Address"
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $client = New-Object System.Net.Sockets.TcpClient
    $asyncResult = $null
    $success = $false
    $errorMessage = $null
    $errorDetails = $null
    try {
        $asyncResult = $client.BeginConnect($parsedAddress, $Port, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) {
            $errorMessage = "Timeout após $TimeoutMilliseconds ms."
        }
        else {
            $client.EndConnect($asyncResult)
            $success = $true
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        $errorDetails = $_.Exception.ToString()
    }
    finally {
        if ($null -ne $asyncResult -and $null -ne $asyncResult.AsyncWaitHandle) {
            $asyncResult.AsyncWaitHandle.Close()
        }
        $client.Close()
        $stopwatch.Stop()
    }

    [pscustomobject]@{
        Success             = $success
        Address             = $Address
        Port                = $Port
        ElapsedMilliseconds = $stopwatch.ElapsedMilliseconds
        Error               = $errorMessage
        ErrorDetails        = $errorDetails
    }
}

<#
.SYNOPSIS
Verifica se o serviço HTTP da câmera responde.

.DESCRIPTION
Executa um GET limitado por timeout na raiz HTTP. Respostas HTTP, inclusive
401/403, indicam que o serviço respondeu; não significam autenticação válida.

.PARAMETER Camera
Objeto com Ip e HttpPort.

.PARAMETER Credential
Credencial opcional para câmeras que exigem autenticação.

.PARAMETER TimeoutMilliseconds
Tempo máximo de espera pela resposta.

.OUTPUTS
PSCustomObject com IsAvailable, StatusCode, ElapsedMilliseconds e Error.

.EXAMPLE
Test-CameraHttp -Camera $camera

.NOTES
Documentação: docs/NETWORK.md#teste-http

.LINK
docs/NETWORK.md
#>
# DOC: docs/NETWORK.md#teste-http
function Test-CameraHttp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Camera,

        [System.Management.Automation.PSCredential]$Credential,

        [ValidateRange(100, 30000)]
        [int]$TimeoutMilliseconds = 2500
    )

    $uri = 'http://{0}:{1}/' -f $Camera.Ip, $Camera.HttpPort
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
    $statusCode = $null
    $errorMessage = $null
    $errorDetails = $null
    try {
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        try {
            $statusCode = [int]$response.StatusCode
        }
        finally {
            $response.Close()
        }
    }
    catch [System.Net.WebException] {
        if ($null -ne $_.Exception.Response) {
            $response = [System.Net.HttpWebResponse]$_.Exception.Response
            try {
                $statusCode = [int]$response.StatusCode
            }
            finally {
                $response.Close()
            }
        }
        else {
            $errorMessage = $_.Exception.Message
            $errorDetails = $_.Exception.ToString()
        }
    }
    finally {
        $request.Abort()
        $stopwatch.Stop()
    }

    [pscustomobject]@{
        IsAvailable         = ($null -ne $statusCode)
        StatusCode          = $statusCode
        ElapsedMilliseconds = $stopwatch.ElapsedMilliseconds
        Error               = $errorMessage
        ErrorDetails        = $errorDetails
    }
}

Export-ModuleMember -Function Test-CameraTcpPort, Test-CameraHttp
