# CGI Intelbras

## Escopo e estado

`Modules/IntelbrasCGI.psm1` implementa a consulta CGI e preserva todos os campos `VideoInOptions` para exibição; `Flip` e `Mirror` também são convertidos para booleanos para as ações existentes. A leitura Digest foi confirmada na unidade iM7+ configurada; outras câmeras/firmwares ainda precisam de validação.

Na unidade iM7+ configurada, a interface web confirmou autenticação HTTP Digest. Antes da correção, o GCT+ recebeu HTTP 400 e `Error | Bad Request!`. O loopback identificou que o `HttpWebRequest` do Windows PowerShell montava o campo `uri` do Digest sem a query. O GCT+ agora responde manualmente ao desafio incluindo caminho e query. A leitura pós-correção retornou HTTP 200 e 285 campos `VideoInOptions`; nenhuma escrita foi enviada. Não generalizar para outros modelos/firmwares.

Uma tentativa pela interface do GCT+ na unidade selecionada como iM7+ retornou HTTP 400 tanto para a leitura `VideoInOptions` quanto para comandos de Flip. Com DEBUG habilitado, o corpo observado foi `Error | Bad Request!`. A interface web da câmera, por outro lado, foi reportada como capaz de alterar Flip; a URL informada usa colchetes literais em `VideoInOptions[0]`. O cliente HTTP do Windows PowerShell escapava esses colchetes como `%5B0%5D`; o GCT+ agora preserva a forma literal para essas escritas. A correção foi testada somente em loopback, não na câmera. A falha de leitura `VideoInOptions` ainda precisa de diagnóstico separado. Consulte [CAMERA-RESEARCH.md](CAMERA-RESEARCH.md#intelbras-im7-http-400-em-videoinoptions) e não repita escritas sem confirmar o estado atual.

## Consulta de configuração

### `consulta-de-configuracao`

`Get-IntelbrasVideoOptions` consulta `configManager.cgi?action=getConfig&name=VideoInOptions` e converte as duas propriedades conhecidas para booleano ou nulo.

O cliente usa GET e timeout padrão de 4 segundos. Para o desafio Digest, calcula a resposta com o método e o caminho completo mais a query CGI; outros esquemas continuam usando a negociação do cliente HTTP do Windows. Para respostas diferentes de HTTP 200, URL e corpo limitado são disponibilizados somente no painel DEBUG, sem persistência:

O endereço e a porta vêm do registro selecionado em `cameras.json`. A URL CGI não contém credenciais. Respostas diferentes de HTTP 200 são apresentadas como falha, e propriedades ausentes permanecem nulas.

Não generalizar os campos observados para outros modelos ou firmwares.

## Flip

### `flip`

`Set-IntelbrasFlip` implementa os valores booleanos e exige ShouldProcess. A escrita usa `VideoInOptions[0].Flip` com colchetes literais, conforme a URL informada para a interface web; o cliente HTTP envia a requisição sem recodificar esse índice. Para o Intelbras iM7+, o [caderno de descobertas](CAMERA-RESEARCH.md#intelbras-im7-videoinoptions) registra a escrita de `Flip=false` como observada. Não generalizar esse resultado para outros modelos ou firmwares.

A interface apresenta confirmação explícita, exige resposta `OK` e faz releitura antes de anunciar sucesso. Alterar `Flip` modifica configuração da câmera; consulte também a seção de [risco de alteração](CAMERA-RESEARCH.md#risco-de-alteracao).

## Mirror

### `mirror`

`Set-IntelbrasMirror` implementa escrita experimental e releitura do parâmetro. O [caderno de descobertas](CAMERA-RESEARCH.md#intelbras-im7-videoinoptions) registra apenas a presença de `Mirror` na consulta; a escrita ainda não foi confirmada em câmera.

Não apresentar a implementação como evidência de que o firmware aceita a alteração. Até teste direto, `Mirror` write permanece experimental.

## Resposta e conversao

`ConvertFrom-IntelbrasVideoOptions` transforma cada linha `table.VideoInOptions[0].Nome=valor` em um par de parâmetro e valor, incluindo propriedades indexadas, para a tabela da interface. Também converte `Flip` e `Mirror` para booleanos sem confundir propriedade ausente com `false`. A GUI apresenta os pares em uma tabela somente de leitura. A resposta bruta é retornada para DEBUG e não deve conter credenciais. Os testes automatizados usam respostas simuladas/loopback e não contatam a câmera.

## Segurança e diagnóstico

Falhas HTTP/CGI devem ser distintas de falhas de conectividade quando a implementação permitir essa distinção. Mensagens de erro e logs não devem registrar credenciais nem cabeçalhos `Authorization`. Ver [credenciais](SECURITY.md#protecao-de-credenciais-dpapi) e [rede](NETWORK.md).

Resultados de testes por modelo devem ser registrados separadamente no [caderno de descobertas de câmeras](CAMERA-RESEARCH.md), distinguindo observações diretas de documentação do fabricante e hipóteses.

## Implementação do MVP

`Set-IntelbrasFlip` e `Set-IntelbrasMirror` enviam uma escrita somente após ShouldProcess permitir. A GUI exige confirmação explícita. A requisição precisa responder HTTP 200 e corpo `OK`; em seguida o app consulta novamente `VideoInOptions`. Sucesso é mostrado somente quando a releitura confirma o valor. Se a câmera aceitar a escrita mas a leitura de verificação falhar, o app informa que o comando foi aceito mas não confirmado, com o erro da releitura.

O caderno registra `Flip=false` como observado no Intelbras iM7+. `Flip=true` também está listada entre as requisições observadas na descoberta original. As escritas de `Mirror` estão implementadas, mas ainda não testadas em câmera neste ambiente; não as considerar confirmadas.
