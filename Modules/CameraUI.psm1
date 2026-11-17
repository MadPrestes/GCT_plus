Set-StrictMode -Version 2.0
$script:CameraUiState = $null

Import-Module -Name (Join-Path $PSScriptRoot 'CameraNetwork.psm1') -Global -Force -ErrorAction Stop
Import-Module -Name (Join-Path $PSScriptRoot 'IntelbrasCGI.psm1') -Global -Force -ErrorAction Stop
Import-Module -Name (Join-Path $PSScriptRoot 'CameraStorage.psm1') -Global -Force -ErrorAction Stop

<#
.SYNOPSIS
Monta o URI RTSP principal ou secundário de uma câmera.

.DESCRIPTION
Gera o endpoint Intelbras realmonitor com channel=1 e subtype 0 (principal)
ou 1 (substream). Credenciais só são incluídas quando fornecidas.

.PARAMETER Camera
Objeto com Ip e RtspPort.

.PARAMETER Subtype
0 para o stream principal ou 1 para o substream.

.PARAMETER Credential
Credencial opcional para inserir no URI, caso o equipamento exija.

.OUTPUTS
System.Uri do stream solicitado.

.EXAMPLE
$uri = Get-CameraRtspUri -Camera $camera -Subtype 0

.NOTES
Documentação: docs/RTSP.md
Não registrar o URI retornado se ele contiver credenciais.

.LINK
docs/RTSP.md
#>
# DOC: docs/RTSP.md
function Get-CameraRtspUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Camera,

        [Parameter(Mandatory = $true)]
        [ValidateSet(0, 1)]
        [int]$Subtype,

        [System.Management.Automation.PSCredential]$Credential
    )

    $userInfo = ''
    if ($null -ne $Credential) {
        $networkCredential = $Credential.GetNetworkCredential()
        if (-not [string]::IsNullOrEmpty($networkCredential.UserName) -or
            -not [string]::IsNullOrEmpty($networkCredential.Password)) {
            $encodedUser = [Uri]::EscapeDataString($networkCredential.UserName)
            $encodedPassword = [Uri]::EscapeDataString($networkCredential.Password)
            $userInfo = '{0}:{1}@' -f $encodedUser, $encodedPassword
        }
    }
    $uriText = 'rtsp://{0}{1}:{2}/cam/realmonitor?channel=1&subtype={3}' -f `
        $userInfo, $Camera.Ip, $Camera.RtspPort, $Subtype
    $uri = $null
    if (-not [Uri]::TryCreate($uriText, [UriKind]::Absolute, [ref]$uri)) {
        throw 'Não foi possível construir o URI RTSP.'
    }
    $uri
}

<#
.SYNOPSIS
Localiza e inicia o VLC com o stream RTSP selecionado.

.DESCRIPTION
Procura VLC no PATH e nos diretórios comuns de instalação do Windows. Inicia o
processo sem Invoke-Expression e devolve somente PID e URI sem credenciais.

.PARAMETER Camera
Objeto com Ip e RtspPort.

.PARAMETER Subtype
0 para o stream principal ou 1 para o substream.

.PARAMETER Credential
Credencial opcional para o endpoint RTSP.

.OUTPUTS
PSCustomObject com ProcessId, Stream e SanitizedUri.

.EXAMPLE
Start-CameraVlc -Camera $camera -Subtype 0

.NOTES
Documentação: docs/RTSP.md#vlc
Não registrar credenciais ou URI autenticado.

.LINK
docs/RTSP.md
#>
# DOC: docs/RTSP.md#vlc
function Start-CameraVlc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Camera,

        [Parameter(Mandatory = $true)]
        [ValidateSet(0, 1)]
        [int]$Subtype,

        [System.Management.Automation.PSCredential]$Credential
    )

    $vlcPath = Get-VlcExecutable
    if ([string]::IsNullOrWhiteSpace($vlcPath)) {
        throw 'VLC não foi encontrado. Instale o VLC ou adicione vlc.exe ao PATH.'
    }

    $uri = Get-CameraRtspUri -Camera $Camera -Subtype $Subtype -Credential $Credential
    $arguments = '"{0}"' -f $uri.AbsoluteUri
    $process = Start-Process -FilePath $vlcPath -ArgumentList $arguments -PassThru -ErrorAction Stop
    $safeUri = Get-CameraRtspUri -Camera $Camera -Subtype $Subtype
    [pscustomobject]@{
        ProcessId    = $process.Id
        Stream       = if ($Subtype -eq 0) { 'principal' } else { 'substream' }
        SanitizedUri = $safeUri.AbsoluteUri
    }
}

<#
.SYNOPSIS
Localiza o executável VLC no PATH ou em caminhos usuais.

.DESCRIPTION
Verifica o PATH e diretórios conhecidos de instalação sem procurar em todo o
sistema de arquivos.

.OUTPUTS
String com o caminho do VLC ou nulo se não encontrado.

.EXAMPLE
$vlcPath = Get-VlcExecutable

.NOTES
Documentação: docs/RTSP.md#vlc

.LINK
docs/RTSP.md
#>
# DOC: docs/RTSP.md#vlc
function Get-VlcExecutable {
    [CmdletBinding()]
    param()

    $command = Get-Command -Name 'vlc.exe' -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidates += Join-Path $env:ProgramFiles 'VideoLAN\VLC\vlc.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} 'VideoLAN\VLC\vlc.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates += Join-Path $env:LOCALAPPDATA 'Programs\VideoLAN\VLC\vlc.exe'
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return $null
}

<#
.SYNOPSIS
Cria credencial para uma operação usando entrada ou segredo DPAPI salvo.

.DESCRIPTION
Usa a senha digitada na interface quando fornecida; caso contrário, recupera a
senha protegida pelo usuário Windows. A senha nunca é escrita no log.

.PARAMETER UserName
Nome de usuário da câmera.

.PARAMETER PasswordText
Senha digitada no campo mascarado da interface.

.PARAMETER ProtectedPassword
Senha DPAPI salva no arquivo local.

.OUTPUTS
PSCredential ou nulo quando não há credencial configurada.

.EXAMPLE
$credential = Get-CameraCredential -UserName $user -ProtectedPassword $saved

.NOTES
Documentação: docs/SECURITY.md#dpapi
O texto simples existe apenas transitoriamente em memória para autenticação.

.LINK
docs/SECURITY.md
#>
# DOC: docs/SECURITY.md#dpapi
function Get-CameraCredential {
    [CmdletBinding()]
    param(
        [string]$UserName,
        [string]$PasswordText,
        [string]$ProtectedPassword
    )

    $securePassword = $null
    if (-not [string]::IsNullOrEmpty($PasswordText)) {
        $securePassword = ConvertTo-SecureString -String $PasswordText -AsPlainText -Force
    }
    elseif (-not [string]::IsNullOrEmpty($ProtectedPassword)) {
        $securePassword = Unprotect-CameraPassword -ProtectedPassword $ProtectedPassword
    }
    elseif ([string]::IsNullOrEmpty($UserName)) {
        return $null
    }
    else {
        $securePassword = ConvertTo-SecureString -String '' -AsPlainText -Force
    }

    $credential = New-Object System.Management.Automation.PSCredential([string]$UserName, $securePassword)
    if ($null -ne $script:CameraUiState) {
        $plainPassword = $credential.GetNetworkCredential().Password
        if (-not [string]::IsNullOrEmpty($plainPassword)) {
            $script:CameraUiState.Secrets += $plainPassword
        }
    }
    $credential
}

<#
.SYNOPSIS
Remove segredos conhecidos de um texto antes de exibi-lo.

.DESCRIPTION
Substitui senhas usadas nesta sessão por um marcador antes de mensagens,
exceções ou respostas serem exibidas no log da interface.

.PARAMETER Text
Texto potencialmente sensível.

.OUTPUTS
String sanitizada.

.EXAMPLE
$safe = Protect-GctSensitiveText -Text $exception.ToString()

.NOTES
Documentação: docs/GUI.md#logs

.LINK
docs/GUI.md
#>
# DOC: docs/GUI.md#logs
function Protect-GctSensitiveText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ($null -ne $script:CameraUiState) {
        foreach ($secret in $script:CameraUiState.Secrets) {
            if (-not [string]::IsNullOrEmpty($secret)) {
                $Text = $Text.Replace($secret, '[REDACTED]')
            }
        }
    }
    $Text
}

<#
.SYNOPSIS
Adiciona uma linha de log à interface e ao arquivo local.

.DESCRIPTION
Formata e escreve uma mensagem sem credenciais. Mensagens de depuração podem
ser exibidas apenas na interface, sem persistir respostas CGI no arquivo.

.PARAMETER Level
Severidade apresentada no log.

.PARAMETER CameraIp
IP da câmera associado à operação.

.PARAMETER Message
Texto do evento.

.PARAMETER Persist
Quando falso, a mensagem é exibida somente na interface.

.OUTPUTS
Nenhum.

.EXAMPLE
Write-GctUiLog -Level INFO -CameraIp $ip -Message 'Consultando VideoInOptions'

.NOTES
Documentação: docs/GUI.md#logs
Nunca registrar senha, cabeçalho Authorization ou URI RTSP autenticado.

.LINK
docs/GUI.md
#>
# DOC: docs/GUI.md#logs
function Write-GctUiLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'SUCESSO', 'AVISO', 'ERRO', 'DEBUG')]
        [string]$Level,

        [string]$CameraIp = '-',

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [bool]$Persist = $true
    )

    if ($null -eq $script:CameraUiState) {
        return
    }
    $Message = Protect-GctSensitiveText -Text $Message
    $line = '{0} | {1,-7} | {2} | {3}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $CameraIp, $Message
    $box = $script:CameraUiState.LogBox
    $box.AppendText($line + [Environment]::NewLine)
    $box.SelectionStart = $box.TextLength
    $box.ScrollToCaret()

    if ($Persist) {
        try {
            $logDirectory = Join-Path $script:CameraUiState.ProjectRoot 'logs'
            [System.IO.Directory]::CreateDirectory($logDirectory) | Out-Null
            $logPath = Join-Path $logDirectory 'gctplus.log'
            $encoding = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::AppendAllText($logPath, $line + [Environment]::NewLine, $encoding)
        }
        catch {
            $box.AppendText(('AVISO | Não foi possível gravar o arquivo de log: {0}' -f $_.Exception.Message) + [Environment]::NewLine)
        }
    }
}

<#
.SYNOPSIS
Inicia a interface Windows Forms do GCT+.

.DESCRIPTION
Carrega cameras.json, apresenta os registros e oferece testes manuais HTTP/RTSP,
consulta CGI, alteração confirmada de Flip/Mirror e abertura de streams no VLC.
As operações de rede são executadas em runspace separado para manter a GUI
responsiva; os callbacks capturam o estado da interface e usam caminhos de
módulos resolvidos antes da execução. Enter no campo Senha aciona ATUALIZAR.
Nenhuma alteração é enviada ao iniciar.

.PARAMETER ProjectRoot
Raiz do projeto contendo cameras.json, Modules e logs.

.OUTPUTS
Nenhum.

.EXAMPLE
Start-GCTPlusUI -ProjectRoot $PSScriptRoot

.NOTES
Documentação: docs/GUI.md

.LINK
docs/GUI.md
#>
# DOC: docs/GUI.md
function Start-GCTPlusUI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectRoot
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $cameras = @(Read-GctCameraStore -ProjectRoot $ProjectRoot)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'GCT+ — Gorgeous Camera Tool'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(1100, 760)
    $form.MinimumSize = New-Object System.Drawing.Size(900, 650)

    $cameraLabel = New-Object System.Windows.Forms.Label
    $cameraLabel.Text = 'Câmera'
    $cameraLabel.Location = New-Object System.Drawing.Point(16, 16)
    $cameraLabel.AutoSize = $true
    $cameraCombo = New-Object System.Windows.Forms.ComboBox
    $cameraCombo.Location = New-Object System.Drawing.Point(16, 38)
    $cameraCombo.Size = New-Object System.Drawing.Size(250, 28)
    $cameraCombo.DropDownStyle = 'DropDownList'

    $ipLabel = New-Object System.Windows.Forms.Label
    $ipLabel.Text = 'IP / portas'
    $ipLabel.Location = New-Object System.Drawing.Point(280, 16)
    $ipLabel.AutoSize = $true
    $endpointText = New-Object System.Windows.Forms.TextBox
    $endpointText.Location = New-Object System.Drawing.Point(280, 38)
    $endpointText.Size = New-Object System.Drawing.Size(170, 24)
    $endpointText.ReadOnly = $true

    $userLabel = New-Object System.Windows.Forms.Label
    $userLabel.Text = 'Usuário'
    $userLabel.Location = New-Object System.Drawing.Point(465, 16)
    $userLabel.AutoSize = $true
    $userBox = New-Object System.Windows.Forms.TextBox
    $userBox.Location = New-Object System.Drawing.Point(465, 38)
    $userBox.Size = New-Object System.Drawing.Size(145, 24)

    $passwordLabel = New-Object System.Windows.Forms.Label
    $passwordLabel.Text = 'Senha'
    $passwordLabel.Location = New-Object System.Drawing.Point(620, 16)
    $passwordLabel.AutoSize = $true
    $passwordBox = New-Object System.Windows.Forms.TextBox
    $passwordBox.Location = New-Object System.Drawing.Point(620, 38)
    $passwordBox.Size = New-Object System.Drawing.Size(145, 24)
    $passwordBox.UseSystemPasswordChar = $true

    $savePasswordCheck = New-Object System.Windows.Forms.CheckBox
    $savePasswordCheck.Text = 'Salvar senha via DPAPI'
    $savePasswordCheck.Location = New-Object System.Drawing.Point(780, 38)
    $savePasswordCheck.AutoSize = $true
    $debugCheck = New-Object System.Windows.Forms.CheckBox
    $debugCheck.Text = 'DEBUG'
    $debugCheck.Location = New-Object System.Drawing.Point(955, 38)
    $debugCheck.AutoSize = $true

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Text = 'Salvar configurações'
    $saveButton.Location = New-Object System.Drawing.Point(16, 76)
    $saveButton.Size = New-Object System.Drawing.Size(170, 30)

    $updateButton = New-Object System.Windows.Forms.Button
    $updateButton.Text = 'ATUALIZAR'
    $updateButton.Location = New-Object System.Drawing.Point(16, 126)
    $updateButton.Size = New-Object System.Drawing.Size(130, 38)
    $form.AcceptButton = $updateButton
    $flipTrueButton = New-Object System.Windows.Forms.Button
    $flipTrueButton.Text = 'Flip = true'
    $flipTrueButton.Location = New-Object System.Drawing.Point(160, 126)
    $flipTrueButton.Size = New-Object System.Drawing.Size(105, 38)
    $flipFalseButton = New-Object System.Windows.Forms.Button
    $flipFalseButton.Text = 'Flip = false'
    $flipFalseButton.Location = New-Object System.Drawing.Point(275, 126)
    $flipFalseButton.Size = New-Object System.Drawing.Size(105, 38)
    $mirrorTrueButton = New-Object System.Windows.Forms.Button
    $mirrorTrueButton.Text = 'Mirror = true'
    $mirrorTrueButton.Location = New-Object System.Drawing.Point(390, 126)
    $mirrorTrueButton.Size = New-Object System.Drawing.Size(115, 38)
    $mirrorFalseButton = New-Object System.Windows.Forms.Button
    $mirrorFalseButton.Text = 'Mirror = false'
    $mirrorFalseButton.Location = New-Object System.Drawing.Point(515, 126)
    $mirrorFalseButton.Size = New-Object System.Drawing.Size(115, 38)
    $vlcMainButton = New-Object System.Windows.Forms.Button
    $vlcMainButton.Text = 'Abrir VLC — principal'
    $vlcMainButton.Location = New-Object System.Drawing.Point(645, 126)
    $vlcMainButton.Size = New-Object System.Drawing.Size(175, 38)
    $vlcSubButton = New-Object System.Windows.Forms.Button
    $vlcSubButton.Text = 'Abrir VLC — substream'
    $vlcSubButton.Location = New-Object System.Drawing.Point(830, 126)
    $vlcSubButton.Size = New-Object System.Drawing.Size(185, 38)

    $statusGroup = New-Object System.Windows.Forms.GroupBox
    $statusGroup.Text = 'Estado da câmera'
    $statusGroup.Location = New-Object System.Drawing.Point(16, 180)
    $statusGroup.Size = New-Object System.Drawing.Size(1045, 95)
    $httpStatus = New-Object System.Windows.Forms.Label
    $httpStatus.Text = 'HTTP: —'
    $httpStatus.Location = New-Object System.Drawing.Point(18, 30)
    $httpStatus.AutoSize = $true
    $rtspStatus = New-Object System.Windows.Forms.Label
    $rtspStatus.Text = 'RTSP: —'
    $rtspStatus.Location = New-Object System.Drawing.Point(235, 30)
    $rtspStatus.AutoSize = $true
    $flipStatus = New-Object System.Windows.Forms.Label
    $flipStatus.Text = 'Flip: —'
    $flipStatus.Location = New-Object System.Drawing.Point(455, 30)
    $flipStatus.AutoSize = $true
    $mirrorStatus = New-Object System.Windows.Forms.Label
    $mirrorStatus.Text = 'Mirror: —'
    $mirrorStatus.Location = New-Object System.Drawing.Point(650, 30)
    $mirrorStatus.AutoSize = $true
    $statusText = New-Object System.Windows.Forms.Label
    $statusText.Text = 'Pronto. Selecione uma câmera e clique em ATUALIZAR.'
    $statusText.Location = New-Object System.Drawing.Point(18, 58)
    $statusText.AutoSize = $true
    $statusGroup.Controls.AddRange(@($httpStatus, $rtspStatus, $flipStatus, $mirrorStatus, $statusText))

    $viewTabs = New-Object System.Windows.Forms.TabControl
    $viewTabs.Location = New-Object System.Drawing.Point(16, 290)
    $viewTabs.Size = New-Object System.Drawing.Size(1045, 399)
    $viewTabs.Anchor = 'Top, Bottom, Left, Right'

    $optionsTab = New-Object System.Windows.Forms.TabPage
    $optionsTab.Text = 'VideoInOptions'
    $videoOptionsTable = New-Object System.Data.DataTable
    [void]$videoOptionsTable.Columns.Add('Parâmetro', [string])
    [void]$videoOptionsTable.Columns.Add('Valor', [string])
    $videoOptionsGrid = New-Object System.Windows.Forms.DataGridView
    $videoOptionsGrid.Dock = 'Fill'
    $videoOptionsGrid.ReadOnly = $true
    $videoOptionsGrid.AllowUserToAddRows = $false
    $videoOptionsGrid.AllowUserToDeleteRows = $false
    $videoOptionsGrid.AutoGenerateColumns = $true
    $videoOptionsGrid.AutoSizeColumnsMode = 'Fill'
    $videoOptionsGrid.RowHeadersVisible = $false
    $videoOptionsGrid.SelectionMode = 'FullRowSelect'
    $videoOptionsGrid.DataSource = $videoOptionsTable
    $optionsTab.Controls.Add($videoOptionsGrid)

    $logTab = New-Object System.Windows.Forms.TabPage
    $logTab.Text = 'Log'
    $logBox = New-Object System.Windows.Forms.RichTextBox
    $logBox.Location = New-Object System.Drawing.Point(8, 8)
    $logBox.Size = New-Object System.Drawing.Size(1015, 350)
    $logBox.Anchor = 'Top, Bottom, Left, Right'
    $logBox.ReadOnly = $true
    $logBox.WordWrap = $false
    $logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
    $logTab.Controls.Add($logBox)
    [void]$viewTabs.TabPages.Add($optionsTab)
    [void]$viewTabs.TabPages.Add($logTab)

    $form.Controls.AddRange(@(
        $cameraLabel, $cameraCombo, $ipLabel, $endpointText, $userLabel, $userBox,
        $passwordLabel, $passwordBox, $savePasswordCheck, $debugCheck, $saveButton,
        $updateButton, $flipTrueButton, $flipFalseButton, $mirrorTrueButton,
        $mirrorFalseButton, $vlcMainButton, $vlcSubButton, $statusGroup, $viewTabs
    ))

    $script:CameraUiState = @{
        ProjectRoot = $ProjectRoot
        Cameras = $cameras
        CameraCombo = $cameraCombo
        EndpointText = $endpointText
        UserBox = $userBox
        PasswordBox = $passwordBox
        SavePasswordCheck = $savePasswordCheck
        DebugCheck = $debugCheck
        LogBox = $logBox
        VideoOptionsTable = $videoOptionsTable
        VideoOptionsGrid = $videoOptionsGrid
        HttpStatus = $httpStatus
        RtspStatus = $rtspStatus
        FlipStatus = $flipStatus
        MirrorStatus = $mirrorStatus
        StatusText = $statusText
        Buttons = @($saveButton, $updateButton, $flipTrueButton, $flipFalseButton,
            $mirrorTrueButton, $mirrorFalseButton, $vlcMainButton, $vlcSubButton, $cameraCombo)
        Secrets = @()
        ActiveOperation = $null
    }
    $uiState = $script:CameraUiState

    foreach ($camera in $cameras) {
        [void]$cameraCombo.Items.Add([string]$camera.Name)
    }

    $operationTimer = New-Object System.Windows.Forms.Timer
    $operationTimer.Interval = 100
    $uiState.Timer = $operationTimer
    # Resolve module paths before callbacks run in a different script scope.
    $workerModulePaths = @(
        (Join-Path -Path $ProjectRoot -ChildPath 'Modules\CameraNetwork.psm1'),
        (Join-Path -Path $ProjectRoot -ChildPath 'Modules\IntelbrasCGI.psm1')
    )

    $getSelectedCamera = {
        $index = $uiState.CameraCombo.SelectedIndex
        if ($index -lt 0 -or $index -ge $uiState.Cameras.Count) {
            throw 'Selecione uma câmera.'
        }
        $uiState.Cameras[$index]
    }.GetNewClosure()

    $getOperationCamera = {
        $sourceCamera = & $getSelectedCamera
        $credential = Get-CameraCredential -UserName $uiState.UserBox.Text `
            -PasswordText $uiState.PasswordBox.Text `
            -ProtectedPassword $sourceCamera.PasswordProtected
        [pscustomobject]@{
            Id         = $sourceCamera.Id
            Name       = $sourceCamera.Name
            Ip         = $sourceCamera.Ip
            HttpPort   = [int]$sourceCamera.HttpPort
            RtspPort   = [int]$sourceCamera.RtspPort
            Credential = $credential
        }
    }.GetNewClosure()

    $setBusy = {
        param([bool]$Busy)
        foreach ($button in $uiState.Buttons) {
            $button.Enabled = -not $Busy
        }
        $uiState.StatusText.Text = if ($Busy) { 'Operação em andamento…' } else { 'Pronto.' }
    }.GetNewClosure()

    $startOperation = {
        param(
            [string]$Operation,
            [psobject]$Camera,
            [string]$Property,
            [bool]$Value
        )
        if ($null -ne $uiState.ActiveOperation) {
            return
        }
        $scriptText = @'
param($ModulePaths, $Operation, $Camera, $Property, $Value)
foreach ($modulePath in $ModulePaths) {
    $null = Import-Module -Name $modulePath -Force -ErrorAction Stop
}
if ($Operation -eq 'Refresh') {
    $httpTcp = Test-CameraTcpPort -Address $Camera.Ip -Port $Camera.HttpPort -TimeoutMilliseconds 1800
    $rtspTcp = Test-CameraTcpPort -Address $Camera.Ip -Port $Camera.RtspPort -TimeoutMilliseconds 1800
    $http = $null
    $options = $null
    $cgiError = $null
    $cgiErrorDetails = $null
    $cgiErrorUri = $null
    $cgiErrorBody = $null
    if ($httpTcp.Success) {
        $http = Test-CameraHttp -Camera $Camera -Credential $Camera.Credential -TimeoutMilliseconds 2500
        if ($http.IsAvailable) {
            try {
                $options = Get-IntelbrasVideoOptions -Camera $Camera -Credential $Camera.Credential -TimeoutMilliseconds 4000
            }
            catch {
                $cgiError = $_.Exception.Message
                $cgiErrorDetails = $_.Exception.ToString()
                $cgiErrorUri = [string]$_.Exception.Data['RequestUri']
                $cgiErrorBody = [string]$_.Exception.Data['ResponseBody']
            }
        }
    }
    [pscustomobject]@{
        Operation = 'Refresh'
        Camera = $Camera
        HttpTcp = $httpTcp
        RtspTcp = $rtspTcp
        Http = $http
        Options = $options
        CgiError = $cgiError
        CgiErrorDetails = $cgiErrorDetails
        CgiErrorUri = $cgiErrorUri
        CgiErrorBody = $cgiErrorBody
    }
}
elseif ($Operation -eq 'Set') {
    if ($Property -eq 'Flip') {
        $result = Set-IntelbrasFlip -Camera $Camera -Value $Value -Credential $Camera.Credential -TimeoutMilliseconds 4000 -Confirm:$false
    }
    else {
        $result = Set-IntelbrasMirror -Camera $Camera -Value $Value -Credential $Camera.Credential -TimeoutMilliseconds 4000 -Confirm:$false
    }
    [pscustomobject]@{
        Operation = 'Set'
        Camera = $Camera
        Property = $Property
        Result = $result
    }
}
'@
        $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $runspace.ApartmentState = [System.Threading.ApartmentState]::MTA
        $runspace.Open()
        $powershell = [System.Management.Automation.PowerShell]::Create()
        $powershell.Runspace = $runspace
        $null = $powershell.AddScript($scriptText).
            AddArgument($workerModulePaths).
            AddArgument($Operation).
            AddArgument($Camera).
            AddArgument($Property).
            AddArgument($Value)
        $asyncResult = $powershell.BeginInvoke()
        $uiState.ActiveOperation = @{
            PowerShell = $powershell
            Runspace = $runspace
            Async = $asyncResult
            Operation = $Operation
            Camera = $Camera
            Property = $Property
            Value = $Value
        }
        & $setBusy $true
        $uiState.Timer.Start()
    }.GetNewClosure()

    $cameraCombo.add_SelectedIndexChanged({
        if ($uiState.CameraCombo.SelectedIndex -lt 0) {
            return
        }
        $camera = $uiState.Cameras[$uiState.CameraCombo.SelectedIndex]
        $uiState.EndpointText.Text = '{0}  HTTP:{1}  RTSP:{2}' -f $camera.Ip, $camera.HttpPort, $camera.RtspPort
        $uiState.UserBox.Text = [string]$camera.Username
        $uiState.PasswordBox.Clear()
        $uiState.SavePasswordCheck.Checked = -not [string]::IsNullOrEmpty([string]$camera.PasswordProtected)
        $uiState.HttpStatus.Text = 'HTTP: —'
        $uiState.RtspStatus.Text = 'RTSP: —'
        $uiState.FlipStatus.Text = 'Flip: —'
        $uiState.MirrorStatus.Text = 'Mirror: —'
        $uiState.VideoOptionsTable.Rows.Clear()
        $uiState.Secrets = @()
    }.GetNewClosure())
    $cameraCombo.SelectedIndex = 0

    $saveButton.add_Click({
        try {
            $index = $uiState.CameraCombo.SelectedIndex
            $source = $uiState.Cameras[$index]
            $updated = @()
            for ($cameraIndex = 0; $cameraIndex -lt $uiState.Cameras.Count; $cameraIndex++) {
                $camera = $uiState.Cameras[$cameraIndex]
                $protectedPassword = [string]$camera.PasswordProtected
                $userName = [string]$camera.Username
                if ($cameraIndex -eq $index) {
                    $userName = $uiState.UserBox.Text
                    if ($uiState.SavePasswordCheck.Checked) {
                        if (-not [string]::IsNullOrEmpty($uiState.PasswordBox.Text)) {
                            $secure = ConvertTo-SecureString -String $uiState.PasswordBox.Text -AsPlainText -Force
                            $protectedPassword = Protect-CameraPassword -Password $secure
                        }
                    }
                    else {
                        $protectedPassword = ''
                    }
                }
                $updated += [pscustomobject]@{
                    Id = $camera.Id
                    Name = $camera.Name
                    Manufacturer = $camera.Manufacturer
                    Model = $camera.Model
                    Ip = $camera.Ip
                    HttpPort = [int]$camera.HttpPort
                    RtspPort = [int]$camera.RtspPort
                    Username = $userName
                    PasswordProtected = $protectedPassword
                }
            }
            Write-GctCameraStore -Cameras $updated -ProjectRoot $uiState.ProjectRoot
            $uiState.Cameras = @(Read-GctCameraStore -ProjectRoot $uiState.ProjectRoot)
            $uiState.PasswordBox.Clear()
            $uiState.StatusText.Text = 'Configurações salvas.'
            Write-GctUiLog -Level SUCESSO -CameraIp $source.Ip -Message 'Configurações da câmera salvas; senha protegida por DPAPI quando selecionado.'
        }
        catch {
            $uiState.StatusText.Text = 'Falha ao salvar configurações.'
            Write-GctUiLog -Level ERRO -Message $_.Exception.Message
            $safeError = Protect-GctSensitiveText -Text $_.Exception.Message
            [System.Windows.Forms.MessageBox]::Show($safeError, 'Erro ao salvar', 'OK', 'Error') | Out-Null
        }
    }.GetNewClosure())

    $updateButton.add_Click({
        try {
            $camera = & $getOperationCamera
            $source = & $getSelectedCamera
            $uiState.VideoOptionsTable.Rows.Clear()
            Write-GctUiLog -Level INFO -CameraIp $camera.Ip -Message ('Testando HTTP:{0}' -f $camera.HttpPort)
            Write-GctUiLog -Level INFO -CameraIp $camera.Ip -Message ('Testando RTSP:{0}' -f $camera.RtspPort)
            & $startOperation 'Refresh' $camera '' $false
        }
        catch {
            Write-GctUiLog -Level ERRO -Message $_.Exception.Message
            $safeError = Protect-GctSensitiveText -Text $_.Exception.Message
            [System.Windows.Forms.MessageBox]::Show($safeError, 'Erro', 'OK', 'Error') | Out-Null
        }
    }.GetNewClosure())
    $passwordBox.add_KeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $eventArgs.Handled = $true
            $eventArgs.SuppressKeyPress = $true
            $updateButton.PerformClick()
        }
    }.GetNewClosure())

    $setHandler = {
        param($sender, $eventArgs)
        $property = [string]$sender.Tag.Split('|')[0]
        $value = [System.Boolean]::Parse([string]$sender.Tag.Split('|')[1])
        try {
            $camera = & $getOperationCamera
            $confirmation = [System.Windows.Forms.MessageBox]::Show(
                ('Confirmar alteração em {0} ({1})?{2}{3}={4}' -f $camera.Name, $camera.Ip, [Environment]::NewLine, $property, $value.ToString().ToLowerInvariant()),
                'Confirmar alteração da câmera',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) {
                Write-GctUiLog -Level INFO -CameraIp $camera.Ip -Message ('Alteração {0}={1} cancelada pelo usuário.' -f $property, $value.ToString().ToLowerInvariant())
                return
            }
            Write-GctUiLog -Level INFO -CameraIp $camera.Ip -Message ('Solicitando {0}={1}' -f $property, $value.ToString().ToLowerInvariant())
            & $startOperation 'Set' $camera $property $value
        }
        catch {
            Write-GctUiLog -Level ERRO -Message $_.Exception.Message
            $safeError = Protect-GctSensitiveText -Text $_.Exception.Message
            [System.Windows.Forms.MessageBox]::Show($safeError, 'Erro', 'OK', 'Error') | Out-Null
        }
    }.GetNewClosure()
    $flipTrueButton.Tag = 'Flip|true'
    $flipFalseButton.Tag = 'Flip|false'
    $mirrorTrueButton.Tag = 'Mirror|true'
    $mirrorFalseButton.Tag = 'Mirror|false'
    $flipTrueButton.add_Click($setHandler)
    $flipFalseButton.add_Click($setHandler)
    $mirrorTrueButton.add_Click($setHandler)
    $mirrorFalseButton.add_Click($setHandler)

    $vlcHandler = {
        param($sender, $eventArgs)
        $subtype = [int]$sender.Tag
        try {
            $camera = & $getOperationCamera
            $safeUri = Get-CameraRtspUri -Camera $camera -Subtype $subtype
            Write-GctUiLog -Level INFO -CameraIp $camera.Ip -Message ('Abrindo VLC ({0}) {1}' -f $(if ($subtype -eq 0) { 'principal' } else { 'substream' }), $safeUri.AbsoluteUri)
            $result = Start-CameraVlc -Camera $camera -Subtype $subtype -Credential $camera.Credential
            Write-GctUiLog -Level SUCESSO -CameraIp $camera.Ip -Message ('VLC iniciado (PID {0}).' -f $result.ProcessId)
        }
        catch {
            Write-GctUiLog -Level ERRO -Message $_.Exception.Message
            $safeError = Protect-GctSensitiveText -Text $_.Exception.Message
            [System.Windows.Forms.MessageBox]::Show($safeError, 'Erro ao iniciar VLC', 'OK', 'Error') | Out-Null
        }
    }.GetNewClosure()
    $vlcMainButton.Tag = '0'
    $vlcSubButton.Tag = '1'
    $vlcMainButton.add_Click($vlcHandler)
    $vlcSubButton.add_Click($vlcHandler)

    $operationTimer.add_Tick({
        $operation = $uiState.ActiveOperation
        if ($null -eq $operation -or -not $operation.Async.IsCompleted) {
            return
        }
        $uiState.Timer.Stop()
        try {
            $output = @($operation.PowerShell.EndInvoke($operation.Async))
            if ($operation.PowerShell.Streams.Error.Count -gt 0) {
                throw $operation.PowerShell.Streams.Error[0].Exception
            }
            if ($output.Count -eq 0) {
                throw 'A operação terminou sem resultado.'
            }
            $result = $output[$output.Count - 1]
            if ($result.Operation -eq 'Refresh') {
                $uiState.HttpStatus.Text = if ($result.HttpTcp.Success) {
                    if ($null -ne $result.Http -and $result.Http.IsAvailable) { 'HTTP: disponível (HTTP {0})' -f $result.Http.StatusCode } else { 'HTTP: TCP disponível, sem resposta HTTP' }
                } else { 'HTTP: indisponível' }
                $uiState.RtspStatus.Text = if ($result.RtspTcp.Success) { 'RTSP: TCP disponível' } else { 'RTSP: indisponível' }
                if ($result.HttpTcp.Success) {
                    Write-GctUiLog -Level SUCESSO -CameraIp $result.Camera.Ip -Message ('TCP HTTP:{0} disponível | {1} ms' -f $result.HttpTcp.Port, $result.HttpTcp.ElapsedMilliseconds)
                }
                else {
                    Write-GctUiLog -Level AVISO -CameraIp $result.Camera.Ip -Message ('TCP HTTP:{0} indisponível: {1}' -f $result.HttpTcp.Port, $result.HttpTcp.Error)
                }
                if ($null -ne $result.Http -and $result.Http.IsAvailable) {
                    Write-GctUiLog -Level SUCESSO -CameraIp $result.Camera.Ip -Message ('HTTP respondeu {0} | {1} ms' -f $result.Http.StatusCode, $result.Http.ElapsedMilliseconds)
                }
                elseif ($result.HttpTcp.Success) {
                    Write-GctUiLog -Level AVISO -CameraIp $result.Camera.Ip -Message ('Serviço HTTP não respondeu: {0}' -f $result.Http.Error)
                }
                if ($result.RtspTcp.Success) {
                    Write-GctUiLog -Level SUCESSO -CameraIp $result.Camera.Ip -Message ('TCP RTSP:{0} disponível | {1} ms' -f $result.RtspTcp.Port, $result.RtspTcp.ElapsedMilliseconds)
                }
                else {
                    Write-GctUiLog -Level AVISO -CameraIp $result.Camera.Ip -Message ('TCP RTSP:{0} indisponível: {1}' -f $result.RtspTcp.Port, $result.RtspTcp.Error)
                }
                if ($null -ne $result.Options) {
                    $uiState.VideoOptionsTable.Rows.Clear()
                    foreach ($parameter in @($result.Options.Parameters)) {
                        if ($null -eq $parameter) {
                            continue
                        }
                        $row = $uiState.VideoOptionsTable.NewRow()
                        $row['Parâmetro'] = [string]$parameter.Name
                        $row['Valor'] = [string]$parameter.Value
                        [void]$uiState.VideoOptionsTable.Rows.Add($row)
                    }
                    $uiState.FlipStatus.Text = 'Flip: {0}' -f $(if ($null -eq $result.Options.Flip) { 'não encontrado' } else { $result.Options.Flip.ToString().ToLowerInvariant() })
                    $uiState.MirrorStatus.Text = 'Mirror: {0}' -f $(if ($null -eq $result.Options.Mirror) { 'não encontrado' } else { $result.Options.Mirror.ToString().ToLowerInvariant() })
                    Write-GctUiLog -Level SUCESSO -CameraIp $result.Camera.Ip -Message ('VideoInOptions: Flip={0} | Mirror={1} | {2} ms' -f $result.Options.Flip, $result.Options.Mirror, $result.Options.ElapsedMilliseconds)
                    if ($uiState.DebugCheck.Checked) {
                        Write-GctUiLog -Level DEBUG -CameraIp $result.Camera.Ip -Message ('URL CGI: {0}' -f $result.Options.Uri) -Persist:$false
                        Write-GctUiLog -Level DEBUG -CameraIp $result.Camera.Ip -Message ('HTTP {0}; duração {1} ms' -f $result.Options.StatusCode, $result.Options.ElapsedMilliseconds) -Persist:$false
                        Write-GctUiLog -Level DEBUG -CameraIp $result.Camera.Ip -Message ('Resposta CGI: {0}' -f ($result.Options.RawResponse -replace "`r?`n", ' | ')) -Persist:$false
                        Write-GctUiLog -Level DEBUG -CameraIp $result.Camera.Ip -Message ('Parser: Flip={0}; Mirror={1}' -f $result.Options.Flip, $result.Options.Mirror) -Persist:$false
                    }
                    $uiState.StatusText.Text = 'Leitura concluída: {0} parâmetro(s).' -f $uiState.VideoOptionsTable.Rows.Count
                }
                else {
                    $reason = if (-not $result.HttpTcp.Success) { 'TCP HTTP indisponível.' }
                        elseif ($null -eq $result.Http -or -not $result.Http.IsAvailable) { 'Serviço HTTP não respondeu.' }
                        else { 'CGI VideoInOptions falhou: {0}' -f $result.CgiError }
                    Write-GctUiLog -Level AVISO -CameraIp $result.Camera.Ip -Message $reason
                    if ($uiState.DebugCheck.Checked) {
                        if ($result.CgiErrorDetails) {
                            Write-GctUiLog -Level DEBUG -CameraIp $result.Camera.Ip -Message ('Exception completa: {0}' -f $result.CgiErrorDetails) -Persist:$false
                        }
                        if ($result.CgiErrorUri) {
                            Write-GctUiLog -Level DEBUG -CameraIp $result.Camera.Ip -Message ('URL CGI com erro: {0}' -f $result.CgiErrorUri) -Persist:$false
                        }
                        if ($result.CgiErrorBody) {
                            $errorBody = $result.CgiErrorBody -replace "`r?`n", ' | '
                            Write-GctUiLog -Level DEBUG -CameraIp $result.Camera.Ip -Message ('Resposta CGI com erro: {0}' -f $errorBody) -Persist:$false
                        }
                        if ($null -ne $result.Http -and $result.Http.ErrorDetails) {
                            Write-GctUiLog -Level DEBUG -CameraIp $result.Camera.Ip -Message ('HTTP exception completa: {0}' -f $result.Http.ErrorDetails) -Persist:$false
                        }
                    }
                    $uiState.StatusText.Text = $reason
                }
            }
            else {
                $propertyLabel = $operation.Property
                $requested = $result.Result.RequestedValue.ToString().ToLowerInvariant()
                if ($result.Result.Verified) {
                    $uiState.StatusText.Text = 'SUCESSO — {0}={1} confirmado pela câmera.' -f $propertyLabel, $requested
                    if ($propertyLabel -eq 'Flip') {
                        $uiState.FlipStatus.Text = 'Flip: {0}' -f $requested
                    }
                    else {
                        $uiState.MirrorStatus.Text = 'Mirror: {0}' -f $requested
                    }
                    Write-GctUiLog -Level SUCESSO -CameraIp $result.Camera.Ip -Message ('CGI respondeu OK; {0}={1} confirmado pela releitura.' -f $propertyLabel, $requested)
                    if ($uiState.DebugCheck.Checked) {
                        Write-GctUiLog -Level DEBUG -CameraIp $result.Camera.Ip -Message ('URL CGI: {0}' -f $result.Result.Uri) -Persist:$false
                        Write-GctUiLog -Level DEBUG -CameraIp $result.Camera.Ip -Message ('HTTP {0}; duração {1} ms' -f $result.Result.StatusCode, $result.Result.ElapsedMilliseconds) -Persist:$false
                        Write-GctUiLog -Level DEBUG -CameraIp $result.Camera.Ip -Message ('Resposta CGI: {0}; releitura: {1}={2}' -f $result.Result.Response, $propertyLabel, $result.Result.ActualValue) -Persist:$false
                    }
                }
                elseif ($result.Result.Accepted) {
                    $actualText = if ($null -eq $result.Result.ActualValue) { 'desconhecido' } else { $result.Result.ActualValue.ToString().ToLowerInvariant() }
                    if (-not [string]::IsNullOrWhiteSpace($result.Result.VerificationError)) {
                        $uiState.StatusText.Text = 'AVISO — comando aceito; falha ao confirmar. Confira a câmera antes de repetir.'
                        Write-GctUiLog -Level AVISO -CameraIp $result.Camera.Ip -Message ('Comando {0}={1} aceito, mas a releitura falhou: {2}' -f $propertyLabel, $requested, $result.Result.VerificationError)
                        if ($uiState.DebugCheck.Checked) {
                            if ($result.Result.VerificationUri) {
                                Write-GctUiLog -Level DEBUG -CameraIp $result.Camera.Ip -Message ('URL CGI da releitura: {0}' -f $result.Result.VerificationUri) -Persist:$false
                            }
                            if ($result.Result.VerificationResponseBody) {
                                Write-GctUiLog -Level DEBUG -CameraIp $result.Camera.Ip -Message ('Resposta CGI da releitura: {0}' -f ($result.Result.VerificationResponseBody -replace "`r?`n", ' | ')) -Persist:$false
                            }
                        }
                    }
                    else {
                        $uiState.StatusText.Text = 'AVISO — comando aceito, alteração não confirmada.'
                        Write-GctUiLog -Level AVISO -CameraIp $result.Camera.Ip -Message ('Comando aceito, mas {0}={1} não foi confirmado; leitura atual: {2}.' -f $propertyLabel, $requested, $actualText)
                    }
                }
                else {
                    $uiState.StatusText.Text = 'Alteração cancelada.'
                    Write-GctUiLog -Level INFO -CameraIp $result.Camera.Ip -Message 'Alteração cancelada.'
                }
            }
        }
        catch {
            $errorException = $_.Exception
            while ($errorException -is [System.Management.Automation.MethodInvocationException] -and
                $null -ne $errorException.InnerException) {
                $errorException = $errorException.InnerException
            }
            $errorMessage = $errorException.Message
            $uiState.StatusText.Text = 'Operação falhou.'
            Write-GctUiLog -Level ERRO -CameraIp $operation.Camera.Ip -Message $errorMessage
            if ($uiState.DebugCheck.Checked) {
                Write-GctUiLog -Level DEBUG -CameraIp $operation.Camera.Ip -Message ('Exception: {0}' -f $_.Exception.ToString()) -Persist:$false
                $diagnosticException = $_.Exception
                while ($null -ne $diagnosticException) {
                    if ($diagnosticException.Data.Contains('RequestUri')) {
                        Write-GctUiLog -Level DEBUG -CameraIp $operation.Camera.Ip -Message ('URL CGI com erro: {0}' -f $diagnosticException.Data['RequestUri']) -Persist:$false
                    }
                    if ($diagnosticException.Data.Contains('ResponseBody')) {
                        $errorBody = ([string]$diagnosticException.Data['ResponseBody']) -replace "`r?`n", ' | '
                        Write-GctUiLog -Level DEBUG -CameraIp $operation.Camera.Ip -Message ('Resposta CGI com erro: {0}' -f $errorBody) -Persist:$false
                    }
                    $diagnosticException = $diagnosticException.InnerException
                }
            }
            $safeError = Protect-GctSensitiveText -Text $errorMessage
            [System.Windows.Forms.MessageBox]::Show($safeError, 'Falha na operação', 'OK', 'Error') | Out-Null
        }
        finally {
            $operation.PowerShell.Dispose()
            $operation.Runspace.Close()
            $operation.Runspace.Dispose()
            $uiState.ActiveOperation = $null
            & $setBusy $false
        }
    }.GetNewClosure())

    $form.add_FormClosing({
        $operation = $uiState.ActiveOperation
        if ($null -ne $operation) {
            $uiState.Timer.Stop()
            if (-not $operation.Async.IsCompleted) {
                $operation.PowerShell.Stop()
            }
            $operation.PowerShell.Dispose()
            $operation.Runspace.Close()
            $operation.Runspace.Dispose()
            $uiState.ActiveOperation = $null
        }
        $uiState.Timer.Dispose()
    }.GetNewClosure())

    Write-GctUiLog -Level INFO -Message ('GCT+ iniciado. {0} câmera(s) carregada(s); nenhuma alteração automática foi enviada.' -f $cameras.Count)
    [void][System.Windows.Forms.Application]::Run($form)
    $form.Dispose()
}

Export-ModuleMember -Function Get-CameraRtspUri, Start-CameraVlc, Get-VlcExecutable, `
    Get-CameraCredential, Start-GCTPlusUI, Protect-GctSensitiveText, Write-GctUiLog
