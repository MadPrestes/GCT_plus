#requires -Version 5.1
# DOC: docs/INTELBRAS-CGI.md#resposta-e-conversao
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot 'Modules\IntelbrasCGI.psm1'
Import-Module -Name $modulePath -Force -ErrorAction Stop

$mockResponse = @'
table.VideoInOptions[0].DayNightColor=1
table.VideoInOptions[0].Mirror=true
table.VideoInOptions[0].Flip=true
table.VideoInOptions[0].InfraRed=false
table.VideoInOptions[0].PartWhiteBalanceRegions[0][0]=3096
'@
$parsed = ConvertFrom-IntelbrasVideoOptions -ResponseText $mockResponse
if ($parsed.Flip -ne $true -or $parsed.Mirror -ne $true) {
    throw 'Parser test failed: Flip/Mirror were not parsed as true.'
}
if ($parsed.Flip -isnot [bool] -or $parsed.Mirror -isnot [bool]) {
    throw 'Parser test failed: values are not Boolean.'
}
if ($parsed.Parameters.Count -ne 5) {
    throw 'Parser test failed: all VideoInOptions fields were not retained.'
}
$nestedParameter = @($parsed.Parameters | Where-Object { $_.Name -eq 'PartWhiteBalanceRegions[0][0]' })
if ($nestedParameter.Count -ne 1 -or $nestedParameter[0].Value -ne '3096') {
    throw 'Parser test failed: nested parameter name/value was not retained.'
}
Write-Output 'Parser test passed (simulated response only; no camera was contacted).'
