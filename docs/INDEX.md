# Documentação técnica do GCT+

Este diretório documenta a implementação atual do GCT+. A compatibilidade com modelos/firmwares específicos e tudo que ainda não foi testado em uma câmera física deve permanecer identificado como pendente ou experimental.

## Páginas

| Documento | Conteúdo |
|---|---|
| [Arquitetura](ARCHITECTURE.md) | Componentes, persistência e fluxo implementado |
| [Rede](NETWORK.md) | Testes TCP e HTTP e seus limites |
| [CGI Intelbras](INTELBRAS-CGI.md) | Consulta, parser e alterações com releitura |
| [Descobertas de câmeras](CAMERA-RESEARCH.md) | Caderno de testes, evidências e hipóteses por modelo |
| [RTSP](RTSP.md) | Montagem de URI e abertura via VLC |
| [Segurança](SECURITY.md) | DPAPI, autenticação e exposição de credenciais |
| [Interface gráfica](GUI.md) | Fluxos, logs e teste inicial |
| [Changelog](CHANGELOG.md) | Histórico de alterações documentadas |

O [README](../README.md) é a visão geral e ponto de entrada do projeto.

## Índice de componentes e funções

Os nomes abaixo apontam para componentes implementados. A presença no índice não confirma suporte da câmera: capacidades CGI não testadas continuam marcadas como experimentais em suas páginas.

| Componente | Função/Arquivo | Documentação |
|------------|----------------|--------------|
| Inicialização | `GCT+.ps1` | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Teste TCP | `Test-CameraTcpPort` | [NETWORK.md#teste-tcp](NETWORK.md#teste-tcp) |
| Teste HTTP | `Test-CameraHttp` | [NETWORK.md#teste-http](NETWORK.md#teste-http) |
| CGI Intelbras | `Get-IntelbrasVideoOptions` | [INTELBRAS-CGI.md#consulta-de-configuracao](INTELBRAS-CGI.md#consulta-de-configuracao) |
| Requisição CGI | `Invoke-IntelbrasCgiRequest` | [INTELBRAS-CGI.md#consulta-de-configuracao](INTELBRAS-CGI.md#consulta-de-configuracao) |
| Parser CGI | `ConvertFrom-IntelbrasVideoOptions` | [INTELBRAS-CGI.md#resposta-e-conversao](INTELBRAS-CGI.md#resposta-e-conversao) |
| Flip | `Set-IntelbrasFlip` | [INTELBRAS-CGI.md#flip](INTELBRAS-CGI.md#flip) |
| Mirror | `Set-IntelbrasMirror` | [INTELBRAS-CGI.md#mirror](INTELBRAS-CGI.md#mirror) |
| RTSP | `Get-CameraRtspUri` | [RTSP.md](RTSP.md) |
| VLC | `Start-CameraVlc` | [RTSP.md#vlc](RTSP.md#vlc) |
| Localização VLC | `Get-VlcExecutable` | [RTSP.md#vlc](RTSP.md#vlc) |
| Logs da GUI | `Write-GctUiLog` | [GUI.md#logs](GUI.md#logs) |
| Redação de mensagens | `Protect-GctSensitiveText` | [GUI.md#logs](GUI.md#logs) |
| Credenciais | `Protect-CameraPassword` | [SECURITY.md#dpapi](SECURITY.md#dpapi) |
| Recuperação DPAPI | `Unprotect-CameraPassword` | [SECURITY.md#dpapi](SECURITY.md#dpapi) |
| Credencial de sessão | `Get-CameraCredential` | [SECURITY.md#dpapi](SECURITY.md#dpapi) |
| GUI | `CameraUI.psm1` | [GUI.md](GUI.md) |
| Persistência | `Read-GctCameraStore`, `Write-GctCameraStore` | [ARCHITECTURE.md#persistencia](ARCHITECTURE.md#persistencia) |

### Manutenção do índice

Atualizar esta tabela sempre que uma função importante for adicionada, removida ou renomeada. Manter o nome sincronizado com o código, verificar o destino e a âncora da documentação e incluir referência `DOC:` na implementação correspondente. Não manter no índice uma capacidade como confirmada apenas porque seu nome aparece na tabela.

## Regra de entrega: código e documentação

Código e documentação fazem parte da mesma entrega. Sempre que um comportamento do GCT+ for modificado:

1. Alterar o código.
2. Atualizar `.SYNOPSIS` e `.DESCRIPTION` da função afetada, mantendo a ajuda compatível com `Get-Help`.
3. Atualizar o documento técnico correspondente.
4. Atualizar [CAMERA-RESEARCH.md](CAMERA-RESEARCH.md) se houver uma nova descoberta sobre câmera ou protocolo.
5. Atualizar [CHANGELOG.md](CHANGELOG.md).
6. Atualizar este índice se a estrutura ou as funções importantes tiverem mudado.

Não considerar a funcionalidade concluída enquanto código, ajuda inline e documentação técnica estiverem divergentes.

### Verificação dos destinos `DOC:`

Ao final de cada implementação, procurar comentários `DOC: docs/arquivo.md#secao` nos arquivos PowerShell e resolver o caminho do arquivo relativo à raiz do projeto. Informar cada destino inexistente com o arquivo e a linha da referência; a verificação deve falhar se houver algum destino ausente. As âncoras também devem ser conferidas durante a revisão, embora a checagem abaixo valide somente a existência do arquivo.

Exemplo de verificação em PowerShell:

```powershell
$projectRoot = (Get-Location).Path
$sourceFiles = Get-ChildItem -Path $projectRoot -Recurse -File -Include *.ps1, *.psm1, *.psd1
$missingTargets = @()

foreach ($sourceFile in $sourceFiles) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $sourceFile.FullName) {
        $lineNumber++
        foreach ($match in [regex]::Matches($line, 'DOC:\s*(docs/[^\s#]+\.md)(?:#[^\s]+)?')) {
            $relativeTarget = $match.Groups[1].Value.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $targetPath = Join-Path $projectRoot $relativeTarget
            if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
                $missingTargets += '{0}:{1}: {2}' -f $sourceFile.FullName, $lineNumber, $match.Groups[1].Value
            }
        }
    }
}

if ($missingTargets.Count -gt 0) {
    $missingTargets
    throw 'Há destinos DOC: cujo arquivo não existe.'
}
```

Se não houver arquivos PowerShell ou referências `DOC:`, registrar que nenhuma referência foi encontrada; isso não equivale a validar destinos.

## Estado das informações

- **Informado:** diretamente especificado nos requisitos recebidos, como os nomes de arquivos e a referência a `configManager.cgi`.
- **A confirmar:** comportamento inferido a partir de nomes, exemplos ou convenções, que deve ser comparado ao código antes de ser tratado como descrição factual.
- **Recomendação:** orientação técnica que não afirma que o comportamento já esteja implementado.

Os documentos de domínio descrevem os contratos atuais e identificam separadamente o que ainda depende de teste físico. Atualizar os parâmetros e comportamentos quando o código mudar.

As descobertas de engenharia reversa devem seguir a classificação de evidência e status em [CAMERA-RESEARCH.md](CAMERA-RESEARCH.md). Resultado observado em um modelo não confirma suporte em outro.

## Documentacao em linha e no codigo

Cada função PowerShell deve possuir comentário de ajuda compatível com `Get-Help`. Use `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` para cada parâmetro, `.OUTPUTS`, `.EXAMPLE`, `.NOTES` e `.LINK` conforme aplicável. O bloco deve apontar para a página e a âncora que explicam a função.

As partes importantes da implementação também devem apontar para sua seção técnica com um comentário `DOC:`. Para preservar a associação da ajuda ao comando em `Get-Help`, colocar o bloco de ajuda primeiro e a linha `# DOC:` imediatamente depois dele, antes da declaração da função. Exemplos de destinos, conforme a estrutura especificada:

```powershell
# DOC: docs/NETWORK.md#teste-tcp
# DOC: docs/INTELBRAS-CGI.md#consulta-de-configuracao
# DOC: docs/SECURITY.md#protecao-de-credenciais-dpapi
```

Os destinos devem apontar para funções e seções existentes. Comentários de implementação devem explicar decisões não óbvias; não repetir literalmente o que o código já deixa claro.

## Atualização

Ao alterar um comportamento, atualizar a seção técnica correspondente, a ajuda da função, as referências `DOC:` e o changelog quando a mudança for relevante para usuários ou mantenedores. Evitar afirmar suporte, compatibilidade ou garantias sem validação.
