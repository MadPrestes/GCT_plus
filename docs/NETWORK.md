# Rede e conectividade

## Escopo

`Modules/CameraNetwork.psm1` implementa `Test-CameraTcpPort` e `Test-CameraHttp`. Os testes são manuais, por câmera selecionada, e não usam ping nem fazem descoberta da rede.

## Teste TCP

### `teste-tcp`

`Test-CameraTcpPort` abre uma conexão TCP para um IPv4 literal e uma porta selecionada:

O timeout padrão é 2 segundos (configurável entre 100 e 30000 ms). O resultado contém sucesso, endereço, porta, duração e mensagem de erro. Uma falha de ICMP não interfere no teste.

## Teste HTTP

### `teste-http`

`Test-CameraHttp` faz um GET à raiz HTTP configurada, com timeout padrão de 2,5 segundos. Respostas HTTP como 401/403 confirmam que o servidor respondeu, não que a autenticação foi aceita. As credenciais são fornecidas à pilha HTTP quando existem; não são colocadas na URL.

No fluxo ATUALIZAR, o app testa primeiro TCP HTTP, depois HTTP e somente então chama o CGI se o serviço HTTP responder. O teste RTSP verifica apenas a conexão TCP à porta configurada e não confirma a sessão ou a mídia.

Na validação somente de leitura de 2026-11-16, a unidade de teste respondeu TCP nas portas 80 e 554; GET `/` retornou HTTP 404. Isso confirma resposta do serviço HTTP, não autenticação nem funcionamento do fluxo RTSP. Detalhes sem IP real estão em [CAMERA-RESEARCH.md](CAMERA-RESEARCH.md).

## ICMP e portas TCP

Uma falha de ping não é usada como prova de que a câmera está indisponível. ICMP pode estar bloqueado enquanto uma porta TCP continua acessível.

As portas HTTP/RTSP vêm do registro selecionado em `cameras.json`. Uma conexão TCP bem-sucedida confirma apenas que houve conexão à porta naquele momento; não confirma a autenticação, CGI ou fluxo RTSP.

## Falhas e diagnósticos

Registrar os tipos de erro efetivamente produzidos (por exemplo, timeout ou conexão recusada), sem expor senhas, tokens ou cabeçalhos de autenticação. Evitar transformar timeout em sucesso ou em resultado ambíguo. Documentar comportamento de cancelamento se existir.

Consulte também [segurança e logs](SECURITY.md#logs-e-informacoes-sensiveis) e [RTSP](RTSP.md).
