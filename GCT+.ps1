#requires -Version 5.1

# DOC: docs/ARCHITECTURE.md#inicializacao
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$uiModule = Join-Path $projectRoot 'Modules\CameraUI.psm1'

try {
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne
        [System.Threading.ApartmentState]::STA) {
        throw 'A interface Windows Forms exige STA. Inicie pelo Start-GCT+.bat.'
    }
    if (-not (Test-Path -LiteralPath $uiModule -PathType Leaf)) {
        throw "Módulo da interface não encontrado: $uiModule"
    }
    # WinForms callbacks resolve their logging helpers from the global command scope.
    Import-Module -Name $uiModule -Force -Global -ErrorAction Stop
    Start-GCTPlusUI -ProjectRoot $projectRoot
}
catch {
    [Console]::Error.WriteLine(('Falha ao iniciar o GCT+: {0}' -f $_.Exception.Message))
    exit 1
}
