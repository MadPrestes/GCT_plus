# Caderno de descobertas de câmeras

Este caderno registra resultados de testes e engenharia reversa. Cada registro deve separar evidência observada diretamente na câmera de informação encontrada em documentação do fabricante e de hipóteses ainda não testadas.

## Como registrar descobertas

Para cada registro, preencher os campos abaixo. Não registrar senhas reais, tokens, cookies ou cabeçalhos `Authorization`. Usar apenas IPs de exemplo reservados para documentação; nunca publicar o endereço real da câmera.

- Data da descoberta; se não fornecida, escrever **não informada**. A data em que o registro foi escrito não substitui a data do teste.
- Fabricante, modelo e firmware (ou **desconhecido**).
- Recurso e IP de exemplo (explicitamente não real).
- Método utilizado, endpoint e método HTTP.
- Requisito de autenticação conhecido ou **não informado**.
- Comando/requisição executada e resposta observada, sanitizados.
- Interpretação, risco de alteração e status.
- Tipo de evidência: **COMPORTAMENTO OBSERVADO**, **COMPORTAMENTO DOCUMENTADO** e/ou **HIPÓTESE**.

### Significado dos status

- **CONFIRMADO** — resultado observado diretamente no equipamento identificado neste registro. Não implica suporte em outros modelos ou firmwares.
- **PROVÁVEL** — sustentado por evidência indireta, mas ainda não validado diretamente.
- **EXPERIMENTAL** — tentativa em andamento ou resultado sujeito a validação adicional.
- **NÃO SUPORTADO** — testado e não suportado no equipamento/configuração identificados; registrar as condições do teste.

O status classifica a conclusão do registro; o tipo de evidência indica de onde veio a informação. Uma hipótese nunca deve ser descrita como capacidade confirmada da câmera.

## Intelbras iM7 VideoInOptions

### Identificação

- **Data da descoberta:** não informada. Registro incluído no caderno em 2026-11-16; essa data não representa a data do teste.
- **Fabricante:** Intelbras.
- **Modelo:** iM7+.
- **Firmware:** não informado.
- **Recurso:** `VideoInOptions`.
- **IP de exemplo:** `192.0.2.10` — endereço reservado para documentação; não é o IP testado nem um endereço de câmera fornecido.
- **Status:** **CONFIRMADO** para a descoberta descrita e para o modelo informado.

### Evidência e procedimento

**Tipo de evidência: COMPORTAMENTO OBSERVADO.** Os endpoints, parâmetros e resposta abaixo foram fornecidos como observados em testes na câmera. A data, firmware, IP real, autenticação e comando de shell usado não foram informados.

- **Método utilizado:** requisições HTTP CGI à câmera; ferramenta/comando de shell não informado.
- **Endpoint de consulta:** `/cgi-bin/configManager.cgi?action=getConfig&name=VideoInOptions`
- **Método HTTP:** `GET`
- **Autenticação necessária:** não informada. Não inferir que o endpoint seja anônimo.
- **Comando executado:** requisição HTTP `GET` para o endpoint de consulta acima. O host/IP e eventuais cabeçalhos foram omitidos por não terem sido informados.
- **Parâmetros observados na consulta:**

  ```text
  table.VideoInOptions[0].Flip=true|false
  table.VideoInOptions[0].Mirror=true|false
  ```

- **Endpoints de alteração do parâmetro `Flip`:**

  ```http
  GET /cgi-bin/configManager.cgi?action=setConfig&VideoInOptions[0].Flip=true
  GET /cgi-bin/configManager.cgi?action=setConfig&VideoInOptions[0].Flip=false
  ```

- **Resposta de sucesso observada para as alterações:** `OK`

### Interpretação

No Intelbras iM7+ testado, a consulta `VideoInOptions` retornou parâmetros `Flip` e `Mirror` com valores booleanos textuais. As requisições `setConfig` indicadas para `Flip=true` e `Flip=false` tiveram resposta de sucesso `OK`, conforme o resultado fornecido.

Esse registro não estabelece a semântica visual exata de `Flip`, o estado inicial, se a alteração persiste após reinicialização, nem compatibilidade com outras câmeras, firmwares ou parâmetros. Verificar esses pontos separadamente antes de documentá-los como capacidades confirmadas.

### Risco de alteracao

`setConfig` altera a configuração de vídeo da câmera. **Hipótese de risco, não validada neste registro:** mudar `Flip` pode alterar a orientação exibida e afetar a visualização esperada pelo operador. Consultar e registrar o valor atual antes de alterar; confirmar a imagem após a alteração e restaurar o valor anterior se necessário. Os comandos apresentados demonstram os dois valores testados, mas não determinam qual valor é apropriado para uma instalação.

### Comportamento documentado

Nenhuma referência ou citação de documentação do fabricante foi fornecida para esta descoberta. Portanto, os resultados acima estão classificados como observados em teste, não como comportamento documentado pelo fabricante.

### Hipóteses

Compatibilidade com outros modelos/firmwares e persistência após reinicialização permanecem **não verificadas**, não confirmadas. O fato de uma função existir no código não confirma suporte da câmera.

## Referências

- [Integração CGI Intelbras](INTELBRAS-CGI.md)
- [Segurança e informações sensíveis](SECURITY.md#logs-e-informacoes-sensiveis)

## Estado das operações no MVP

- `Flip=false`: registro de comportamento observado recebido para o iM7+.
- `Flip=true`: também consta entre as requisições observadas no registro original.
- Escritas `Mirror=true/false`: endpoint de escrita e resposta não foram observados neste registro. A implementação é experimental e não comprova suporte da câmera.
- Persistência após reinicialização e efeito visual exato de Flip/Mirror: não verificados.

## Intelbras iM7+ — autenticação da consulta

- **Data:** 2026-11-16.
- **Fabricante/modelo:** Intelbras iM7+; firmware não informado.
- **IP de exemplo:** `192.0.2.10` (reservado para documentação; o endereço real foi omitido).
- **Método:** chamada HTTP sem credenciais, somente leitura.
- **Endpoint:** `/cgi-bin/configManager.cgi?action=getConfig&name=VideoInOptions`.
- **Método HTTP:** `GET`.
- **Autenticação:** nenhuma credencial enviada.
- **Comando executado:** chamada a `Get-IntelbrasVideoOptions` sem parâmetro `Credential`.
- **Resposta observada:** HTTP `401 Unauthorized`; o corpo não foi registrado.
- **Interpretação:** a consulta anônima foi recusada nessa unidade. Isso não identifica o esquema de autenticação aceito nem confirma consulta bem-sucedida com credenciais.
- **Risco de alteração:** nenhum; a operação foi somente leitura.
- **Status:** **CONFIRMADO** para a resposta 401 sem credenciais na unidade testada.
- **Tipo de evidência:** **COMPORTAMENTO OBSERVADO**.

Na mesma validação, `Test-CameraTcpPort` conectou às portas TCP 80 (42 ms) e 554 (2 ms). Um GET sem credenciais à raiz `/` retornou HTTP 404. O teste RTSP limitou-se a TCP; nenhuma sessão RTSP foi aberta.

## Intelbras iM7 HTTP 400 em VideoInOptions

- **Data:** 2026-11-16, conforme horário da captura da interface.
- **Fabricante/modelo:** Intelbras iM7+; firmware não informado.
- **IP de exemplo:** `192.0.2.10` (reservado para documentação; o endereço real foi omitido).
- **Recurso:** consulta `VideoInOptions` e tentativa de alteração `Flip`.
- **Método utilizado:** botões ATUALIZAR e Flip na GUI; nenhuma ferramenta externa.
- **Endpoints:** `/cgi-bin/configManager.cgi?action=getConfig&name=VideoInOptions` e `/cgi-bin/configManager.cgi?action=setConfig&VideoInOptions[0].Flip={true|false}`.
- **Método HTTP:** `GET`.
- **Autenticação:** usuário e senha foram preenchidos na interface; esquema aceito não confirmado. Nenhuma senha foi registrada.
- **Comando executado:** ATUALIZAR; tentativas de `Flip=true` e `Flip=false`, cada uma com confirmação na GUI.
- **Resposta observada:** HTTP 400 na leitura CGI e na tentativa de `Flip=true`. Com DEBUG habilitado, o corpo foi `Error | Bad Request!` nos dois casos.
- **URL observada para a leitura:** `http://<IP-DE-EXEMPLO>/cgi-bin/configManager.cgi?action=getConfig&name=VideoInOptions`.
- **URL observada para a escrita:** `http://<IP-DE-EXEMPLO>/cgi-bin/configManager.cgi?action=setConfig&VideoInOptions%5B0%5D.Flip=true`. O índice `[0]` aparece codificado como `%5B0%5D` na URL exibida pela aplicação.
- **Interpretação:** o serviço HTTP respondeu e o CGI rejeitou ambas as requisições. A codificação dos colchetes é uma diferença observada na escrita e pode ser investigada, mas não explica o HTTP 400 da consulta, cuja URL não contém colchetes. A evidência não determina se a causa é autenticação, firmware ou formato do pedido e não confirma o estado atual do Flip. O corpo observado não é uma resposta de sucesso.
- **Risco de alteração:** como nenhuma resposta de sucesso/releitura foi obtida, consultar o estado atual na câmera antes de repetir qualquer escrita.
- **Status:** **CONFIRMADO** somente para as respostas HTTP 400 observadas nesta unidade; suporte ou alteração bem-sucedida não confirmados.
- **Tipo de evidência:** **COMPORTAMENTO OBSERVADO** na captura fornecida pelo usuário.

### Complemento — interface web aceita Flip

- **Data:** 2026-11-17.
- **Firmware informado:** `V2.800.00IB00L.0.R`; versão fornecida pelo usuário, não verificada diretamente.
- **Relato:** o usuário confirmou que conseguiu alterar Flip pela interface web da câmera.
- **URL informada:** `/cgi-bin/configManager.cgi?action=setConfig&VideoInOptions[0].Flip=false`, com colchetes literais. Método, status HTTP e corpo de resposta da chamada do navegador não foram fornecidos.
- **Diferença identificada:** o GCT+ enviava o índice como `%5B0%5D`; um teste local de loopback confirmou que `HttpWebRequest` o codificava mesmo quando a URL de entrada tinha colchetes literais.
- **Correção no GCT+:** preservar `[0]` literal nas escritas de Flip/Mirror. O teste de loopback confirma o formato da linha HTTP enviada, mas não confirma a resposta nem a compatibilidade desta câmera.
- **Limite restante:** a consulta `getConfig&name=VideoInOptions` do GCT+ também havia retornado HTTP 400 e não usa colchetes. A escrita pode ser aceita sem que o GCT+ consiga verificar o valor; nesse caso, a interface apresenta aviso e recomenda conferir o estado na câmera antes de repetir.
- **Status:** diferença de codificação identificada; correção ainda pendente de validação física no iM7+ com esse firmware.
- **Tipo de evidência:** relato do usuário e teste local de loopback; sem nova requisição enviada à câmera.

### Complemento — autenticação Digest e erro de leitura no GCT+

- **Data:** 2026-11-17.
- **Endpoint:** `GET /cgi-bin/configManager.cgi?action=getConfig&name=VideoInOptions`.
- **Evidência do navegador:** o usuário confirmou uma sequência HTTP 401 seguida de HTTP 200 com autenticação Digest; nenhum cookie foi observado. Valores de `Authorization`, nonce e resposta Digest não são registrados aqui.
- **Teste autorizado no GCT+:** uma consulta de leitura usando a credencial salva por DPAPI retornou HTTP 400 e corpo `Error | Bad Request!`. Nenhuma escrita foi enviada nesse teste.
- **Diagnóstico local:** um teste de loopback mostrou que o `HttpWebRequest` do Windows PowerShell formava o campo `uri` do Digest sem a query CGI, diferente da requisição do navegador, que inclui a query.
- **Correção no GCT+:** a resposta Digest agora é calculada com o caminho e a query completos. O teste de loopback valida o campo `uri` e o hash Digest.
- **Resultado pós-correção:** uma única leitura autorizada retornou HTTP 200 e 285 campos. Os valores da configuração não foram registrados neste caderno; nenhuma escrita foi enviada.
- **Status:** leitura `VideoInOptions` confirmada nesta unidade e firmware; não generalizar para outros modelos/firmwares. As escritas seguem sem validação física pela aplicação.
- **Tipo de evidência:** captura do navegador e logs fornecidos pelo usuário, uma leitura autorizada pré-correção e teste local de loopback pós-diagnóstico.
