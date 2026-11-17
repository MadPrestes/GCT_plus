# Changelog

Alterações relevantes devem ser registradas em ordem cronológica inversa. Usar uma data ou versão somente quando definida pelo projeto; não inferir números de versão.

## Não versionado

### CGI Digest e tabela VideoInOptions

- Corrigida a resposta ao desafio HTTP Digest para incluir o caminho e a query CGI no `uri` de autenticação; teste de loopback valida a resposta Digest completa.
- A leitura `VideoInOptions` agora fornece todos os pares parâmetro/valor e a interface exibe-os em uma tabela somente de leitura.
- A leitura autorizada na unidade iM7+ retornou HTTP 400 antes da correção e HTTP 200 com 285 campos depois dela; nenhuma escrita foi enviada.

### CGI Flip

- Preservada a sintaxe literal `VideoInOptions[0]` ao enviar alterações de Flip/Mirror, conforme URL informada para a interface web da câmera.
- Se a escrita responder `OK`, mas a leitura CGI de confirmação falhar, a interface agora informa que a operação foi aceita mas não confirmada, em vez de reportar uma falha total.
- Adicionado teste local de loopback para validar os colchetes na linha HTTP; não houve conexão nem alteração em câmera.

### Ajuda PowerShell

- Reposicionados os marcadores `DOC:` após os blocos de ajuda para que `Get-Help` reconheça `.SYNOPSIS` e `.DESCRIPTION` nas funções dos módulos.

### Correção da interface

- Exportados e disponibilizados no escopo do launcher os helpers de log/redação usados pelos callbacks Windows Forms, corrigindo `Write-GctUiLog` não encontrado.
- Preparada a codificação UTF-8 com BOM dos scripts PowerShell para preservar acentos no Windows PowerShell 5.1.
- Capturados explicitamente o estado da interface e os caminhos dos módulos nos callbacks, corrigindo `Join-Path` com `Path` nulo e a atualização de `ActiveOperation` ao clicar em ATUALIZAR.
- Enter na caixa Senha aciona ATUALIZAR explicitamente (sem depender apenas do botão padrão do formulário). Respostas CGI de erro podem ser inspecionadas em DEBUG sem persistir o corpo no log.
- Erros de operações em runspace agora exibem a mensagem da exceção interna, sem o invólucro confuso de `EndInvoke`; detalhes completos permanecem no DEBUG.
- A seleção inicial da câmera agora preenche usuário e endpoint antes do primeiro teste.
- DEBUG confirmou HTTP 400 com corpo `Error | Bad Request!` na leitura CGI e em tentativa Flip da unidade selecionada como iM7+; a URL de escrita exibiu o índice codificado como `%5B0%5D`, mas a causa e o estado final continuam não confirmados.

### MVP inicial (integração física pendente)

- Criados o launcher STA, GUI Windows Forms, módulos de rede/CGI/armazenamento e configuração inicial.
- Implementados testes TCP/HTTP, parser VideoInOptions, alterações manuais com confirmação e releitura, montagem RTSP, abertura VLC e persistência DPAPI.
- Adicionado teste local do parser; não foram executadas alterações em câmeras. Compatibilidade HTTP/CGI, VLC e operações por modelo ainda precisam de validação física.
- Validação somente de leitura na unidade de teste: TCP 80/554 disponível, GET `/` HTTP 404 e CGI sem credenciais HTTP 401; detalhes sanitizados em `CAMERA-RESEARCH.md`. Nenhum `setConfig` foi enviado.

### Documentação inicial

- Criada a estrutura inicial de documentação técnica a partir dos caminhos e requisitos informados.
- Marcados como pendentes de confirmação os detalhes que dependem do código-fonte, que não estava disponível durante a criação.
- Adicionado o caderno de descobertas com o resultado informado para Intelbras iM7+ / `VideoInOptions`, distinguindo comportamento observado, documentado e hipóteses.
- Registrada a regra de entrega conjunta de código e documentação e o procedimento PowerShell para verificar destinos de comentários `DOC:`.
