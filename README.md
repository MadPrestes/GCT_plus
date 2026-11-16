# GCT+

GCT+ (Gorgeous Camera Tool) é um MVP Windows Forms para leitura e gerenciamento manual de câmeras Intelbras iM7+. O aplicativo usa Windows PowerShell 5.1 e não executa consultas de rede nem alterações de câmera automaticamente ao iniciar.

> **Estado do MVP:** parser, persistência, DPAPI, montagem RTSP e inicialização da GUI passaram em testes locais. Em uma câmera de teste (IP omitido), foram observados TCP 80/554 disponíveis, GET `/` com HTTP 404 e CGI sem credenciais com HTTP 401. Consulta autenticada, reprodução VLC e alterações CGI ainda precisam de validação no ambiente real.

## Estrutura prevista

- [GCT+.ps1](GCT+.ps1) e [Start-GCT+.bat](Start-GCT+.bat): inicialização Windows PowerShell em STA.
- [cameras.json](cameras.json): três câmeras de exemplo do ambiente informado; não contém senha.
- `Modules/CameraNetwork.psm1`: testes TCP e HTTP.
- `Modules/IntelbrasCGI.psm1`: consulta, parsing e alteração com releitura de `VideoInOptions`.
- `Modules/CameraStorage.psm1`: persistência JSON e proteção DPAPI.
- `Modules/CameraUI.psm1`: GUI, operações assíncronas e abertura do VLC.
- `logs/`: logs locais, ignorados pelo Git.
- [tests/Test-IntelbrasParser.ps1](tests/Test-IntelbrasParser.ps1): teste local sem contato com câmera.
- `docs/`: documentação técnica.

Os módulos e seus papéis estão implementados; limites de suporte por modelo/firmware continuam sujeitos a validação física.

## Documentação técnica

- [Índice e mapa da documentação](docs/INDEX.md)
- [Arquitetura](docs/ARCHITECTURE.md)
- [Rede e conectividade](docs/NETWORK.md)
- [CGI Intelbras](docs/INTELBRAS-CGI.md)
- [Caderno de descobertas de câmeras](docs/CAMERA-RESEARCH.md)
- [RTSP](docs/RTSP.md)
- [Segurança](docs/SECURITY.md)
- [Interface gráfica](docs/GUI.md)
- [Changelog](docs/CHANGELOG.md)

## Requisitos para contribuições

Cada função PowerShell deve ter ajuda baseada em comentário compatível com `Get-Help`, incluindo sinopse, descrição, parâmetros, saídas, exemplo e link para a seção técnica relacionada. As partes importantes do código devem apontar para a documentação com comentários `DOC:` e âncoras Markdown relativas ao projeto. Consulte [como manter o código e a documentação sincronizados](docs/INDEX.md#documentacao-em-linha-e-no-codigo).

## Próximos passos de documentação

Para executar e realizar o primeiro teste somente de leitura na câmera 10.3.29.230, consulte [GUI.md](docs/GUI.md#execucao-e-primeiro-teste). Nenhuma alteração deve ser feita antes de conferir os estados lidos.
