Set-StrictMode -Version 2.0

<#
.SYNOPSIS
Lê e valida a lista de câmeras do cameras.json.

.DESCRIPTION
Carrega o JSON localizado na raiz do projeto e verifica os campos necessários
para testes HTTP, RTSP e CGI. Credenciais protegidas permanecem criptografadas.

.PARAMETER ProjectRoot
Raiz do projeto que contém cameras.json.

.OUTPUTS
Array de objetos de câmera.

.EXAMPLE
$cameras = Read-GctCameraStore -ProjectRoot $PSScriptRoot

.NOTES
Documentação: docs/ARCHITECTURE.md#persistencia

.LINK
docs/ARCHITECTURE.md
#>
# DOC: docs/ARCHITECTURE.md#persistencia
function Read-GctCameraStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectRoot
    )

    $path = Join-Path $ProjectRoot 'cameras.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Arquivo de câmeras não encontrado: $path"
    }
    $jsonText = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    try {
        $data = ConvertFrom-Json -InputObject $jsonText -ErrorAction Stop
    }
    catch {
        throw "Não foi possível ler cameras.json: $($_.Exception.Message)"
    }

    $cameras = @($data)
    if ($cameras.Count -eq 0) {
        throw 'cameras.json não contém câmeras.'
    }
    $ids = @{}
    foreach ($camera in $cameras) {
        foreach ($field in @('Id', 'Name', 'Ip', 'HttpPort', 'RtspPort')) {
            if ($null -eq $camera.PSObject.Properties[$field]) {
                throw "Registro de câmera sem o campo obrigatório '$field'."
            }
        }
        if ([string]::IsNullOrWhiteSpace([string]$camera.Id) -or
            [string]::IsNullOrWhiteSpace([string]$camera.Name)) {
            throw 'Id e Name não podem estar vazios.'
        }
        if ($ids.ContainsKey([string]$camera.Id)) {
            throw "Id de câmera duplicado: $($camera.Id)"
        }
        $ids[[string]$camera.Id] = $true

        $parsedAddress = $null
        if (-not [System.Net.IPAddress]::TryParse([string]$camera.Ip, [ref]$parsedAddress) -or
            $parsedAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
            throw "Endereço IPv4 inválido em cameras.json: $($camera.Ip)"
        }
        if ([int]$camera.HttpPort -lt 1 -or [int]$camera.HttpPort -gt 65535 -or
            [int]$camera.RtspPort -lt 1 -or [int]$camera.RtspPort -gt 65535) {
            throw "Porta inválida para a câmera $($camera.Name)."
        }
        if ($null -eq $camera.PSObject.Properties['Username']) {
            $camera | Add-Member -NotePropertyName Username -NotePropertyValue ''
        }
        if ($null -eq $camera.PSObject.Properties['PasswordProtected']) {
            $camera | Add-Member -NotePropertyName PasswordProtected -NotePropertyValue ''
        }
    }
    return $cameras
}

<#
.SYNOPSIS
Grava a lista de câmeras em cameras.json.

.DESCRIPTION
Valida os campos de conexão e grava JSON UTF-8 sem BOM por meio de um arquivo
temporário. A estrutura aceita somente PasswordProtected, nunca senha em claro.

.PARAMETER Cameras
Lista de objetos de câmera.

.PARAMETER ProjectRoot
Raiz do projeto que contém cameras.json.

.OUTPUTS
Nenhum.

.EXAMPLE
Write-GctCameraStore -Cameras $cameras -ProjectRoot $PSScriptRoot

.NOTES
Documentação: docs/ARCHITECTURE.md#persistencia

.LINK
docs/ARCHITECTURE.md
#>
# DOC: docs/ARCHITECTURE.md#persistencia
function Write-GctCameraStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object[]]$Cameras,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectRoot
    )

    if ($Cameras.Count -eq 0) {
        throw 'Não é permitido gravar uma lista de câmeras vazia.'
    }

    $normalized = @()
    $ids = @{}
    foreach ($camera in $Cameras) {
        if ($null -ne $camera.PSObject.Properties['Password']) {
            throw 'Não grave senhas em claro. Use PasswordProtected com DPAPI.'
        }
        foreach ($field in @('Id', 'Name', 'Ip', 'HttpPort', 'RtspPort')) {
            if ($null -eq $camera.PSObject.Properties[$field]) {
                throw "Registro de câmera sem o campo obrigatório '$field'."
            }
        }
        if ([string]::IsNullOrWhiteSpace([string]$camera.Id) -or
            [string]::IsNullOrWhiteSpace([string]$camera.Name)) {
            throw 'Id e Name não podem estar vazios.'
        }
        if ($ids.ContainsKey([string]$camera.Id)) {
            throw "Id de câmera duplicado: $($camera.Id)"
        }
        $ids[[string]$camera.Id] = $true
        $parsedAddress = $null
        if (-not [System.Net.IPAddress]::TryParse([string]$camera.Ip, [ref]$parsedAddress) -or
            $parsedAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
            throw "Endereço IPv4 inválido: $($camera.Ip)"
        }

        $normalized += [pscustomobject]@{
            Id                = [string]$camera.Id
            Name              = [string]$camera.Name
            Manufacturer      = [string]$camera.Manufacturer
            Model             = [string]$camera.Model
            Ip                = [string]$camera.Ip
            HttpPort          = [int]$camera.HttpPort
            RtspPort          = [int]$camera.RtspPort
            Username          = [string]$camera.Username
            PasswordProtected = [string]$camera.PasswordProtected
        }
    }

    $targetPath = Join-Path $ProjectRoot 'cameras.json'
    $temporaryPath = Join-Path $ProjectRoot ('cameras.json.{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    $json = ConvertTo-Json -InputObject @($normalized) -Depth 5
    $encoding = New-Object System.Text.UTF8Encoding($false)
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $json, $encoding)
        Move-Item -LiteralPath $temporaryPath -Destination $targetPath -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

<#
.SYNOPSIS
Protege uma senha usando DPAPI do Windows.

.DESCRIPTION
Converte uma SecureString para o formato criptografado pelo usuário atual,
adequado para persistência local no cameras.json.

.PARAMETER Password
Senha fornecida como SecureString.

.OUTPUTS
String criptografada por DPAPI.

.EXAMPLE
$protected = Protect-CameraPassword -Password $securePassword

.NOTES
Documentação: docs/SECURITY.md#dpapi
A saída não é portátil para outro usuário ou computador.

.LINK
docs/SECURITY.md
#>
# DOC: docs/SECURITY.md#dpapi
function Protect-CameraPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$Password
    )

    ConvertFrom-SecureString -SecureString $Password
}

<#
.SYNOPSIS
Desprotege uma senha local criptografada por DPAPI.

.DESCRIPTION
Converte o valor salvo por Protect-CameraPassword em SecureString no contexto
do mesmo usuário Windows que o protegeu.

.PARAMETER ProtectedPassword
Texto criptografado pelo usuário atual.

.OUTPUTS
SecureString.

.EXAMPLE
$securePassword = Unprotect-CameraPassword -ProtectedPassword $camera.PasswordProtected

.NOTES
Documentação: docs/SECURITY.md#dpapi

.LINK
docs/SECURITY.md
#>
# DOC: docs/SECURITY.md#dpapi
function Unprotect-CameraPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProtectedPassword
    )

    try {
        ConvertTo-SecureString -String $ProtectedPassword -ErrorAction Stop
    }
    catch {
        throw 'Não foi possível descriptografar a senha neste usuário Windows.'
    }
}

Export-ModuleMember -Function Read-GctCameraStore, Write-GctCameraStore, `
    Protect-CameraPassword, Unprotect-CameraPassword
