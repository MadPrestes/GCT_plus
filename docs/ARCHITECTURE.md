# Arquitetura

## Escopo e estado

A árvore de arquivos abaixo corresponde ao MVP implementado. A validação de cada comportamento em câmera real é acompanhada separadamente em [CAMERA-RESEARCH.md](CAMERA-RESEARCH.md).

## Componentes previstos

| Caminho | Responsabilidade prevista | Situação |
|---|---|---|
| `GCT+.ps1` | Ponto de entrada/orquestração | Importa GUI e inicia a janela |
| `Start-GCT+.bat` | Inicialização PowerShell | Usa `-STA` para Windows Forms |
| `cameras.json` | Configuração de câmeras | Lista IPv4, portas, usuário e senha DPAPI opcional |
| `Modules/CameraNetwork.psm1` | Rede/conectividade | Testes TCP e GET HTTP com timeout |
| `Modules/IntelbrasCGI.psm1` | CGI Intelbras | Consulta, parser, Flip/Mirror com releitura |
| `Modules/CameraStorage.psm1` | Persistência | Valida JSON e protege senha com DPAPI |
| `Modules/CameraUI.psm1` | Interface e RTSP/VLC | Windows Forms; operações de rede em runspace |
| `logs/` | Saída de logs | `gctplus.log`; segredos e DEBUG não persistido são excluídos |

## Fluxo de execução

Na inicialização, o app carrega `cameras.json` e abre a GUI, sem testar câmeras ou enviar `setConfig`. Ao clicar em ATUALIZAR, testa TCP HTTP e RTSP, faz GET HTTP e, se o serviço responder, consulta `VideoInOptions`. Operações de rede são executadas em runspace separado para manter a janela responsiva. Alterações exigem clique, confirmação explícita, resposta `OK` e releitura CGI.

## Dependências entre componentes

`GCT+.ps1` importa `CameraUI.psm1`. Esse módulo carrega `CameraNetwork.psm1`, `IntelbrasCGI.psm1` e `CameraStorage.psm1`. A interface compartilha registros de câmera e `PSCredential` com o runspace de trabalho; os módulos de backend retornam objetos estruturados de estado e resultado.

## Persistencia

`Modules/CameraStorage.psm1` lê e grava a lista JSON na raiz do projeto. Cada registro contém `Id`, `Name`, `Manufacturer`, `Model`, `Ip`, `HttpPort`, `RtspPort`, `Username` e `PasswordProtected`. Senhas salvas são criptografadas via DPAPI para o usuário Windows atual; o arquivo não deve conter senha em claro.

A gravação valida registros e usa um arquivo temporário antes de substituir `cameras.json`. A interface só persiste alterações após clique em **Salvar configurações**.

## Inicializacao

`Start-GCT+.bat` inicia `GCT+.ps1` com Windows PowerShell 5.1 e `-STA`. O script importa `CameraUI.psm1`, que importa os módulos de rede, CGI e armazenamento. Falhas de importação ou de inicialização são exibidas e encerram o processo com erro.

## Execucao assíncrona

Testes HTTP/TCP/CGI e alterações são executados em runspace de trabalho. Um timer WinForms verifica sua conclusão e atualiza os controles na thread da interface. Apenas uma operação é executada por vez; os botões ficam desabilitados durante a operação.

## Contratos de dados e operação

- `cameras.json` deve conter IPv4 literal e portas válidas de HTTP/RTSP.
- Credenciais usam `Username` e `PasswordProtected`; nunca adicionar senha em claro ao JSON.
- Cada operação retorna falha/estado explícito; timeout TCP/HTTP/CGI é limitado.
- `logs/gctplus.log` é o log persistente; DEBUG detalhado é somente visual.
- Requisito de execução: Windows PowerShell 5.1, Windows Forms e sessão STA.

Referências relacionadas: [rede](NETWORK.md), [CGI Intelbras](INTELBRAS-CGI.md), [armazenamento e credenciais](SECURITY.md) e [GUI](GUI.md).
