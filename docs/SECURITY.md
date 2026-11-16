# Segurança

## Estado e princípios

O MVP protege senhas salvas usando DPAPI do usuário Windows atual. Isso protege o valor em repouso, mas não cifra o tráfego HTTP/RTSP nem impede acesso por malware executado como o mesmo usuário.

## Protecao de credenciais (DPAPI)

### `dpapi`

### `protecao-de-credenciais-dpapi`

`Protect-CameraPassword` usa `ConvertFrom-SecureString` no Windows PowerShell 5.1 sem chave fornecida, armazenando o valor DPAPI ligado ao usuário atual. `Unprotect-CameraPassword` exige o mesmo contexto Windows.

O valor criptografado fica em `PasswordProtected` no `cameras.json`. O username, IP e configuração não são criptografados. DPAPI não é substituto para ACLs de arquivo nem para proteção do endpoint.

- a descriptografia só funciona para o mesmo contexto de usuário Windows;
- o arquivo também contém usuário, IP e configuração em texto não criptografado;
- a senha é transformada em `NetworkCredential` durante a requisição e deve ser tratada como segredo em memória;
- erros de descriptografia são reportados sem imprimir o valor protegido.

Durante a autenticação, o valor é recuperado para memória e passado como `NetworkCredential` ao cliente HTTP. Isso é necessário para autenticar, mas significa que DPAPI protege apenas o armazenamento local, não a senha durante o uso.

## Logs e informações sensíveis

### `logs-e-informacoes-sensiveis`

**Requisito explícito:** nunca registrar credenciais ou cabeçalhos `Authorization`.

Revisar também mensagens de erro, traces HTTP, URIs RTSP, arquivos temporários e dumps para evitar exposição indireta de senhas, tokens, cookies ou dados de autenticação. Usar exemplos sanitizados na documentação. Definir nível, retenção, rotação e permissões dos logs a partir do comportamento efetivo da aplicação.

Detalhes de resposta CGI com erro são limitados a 1000 caracteres e exibidos somente na interface quando DEBUG está ativo; não são gravados no arquivo de log.

## Transporte e autenticação

O CGI é chamado por HTTP e o URI de stream é RTSP, sem TLS implementado. As credenciais podem trafegar em rede sem criptografia. Use rede confiável e não exponha os dispositivos à Internet. O método de autenticação efetivamente aceito pelo firmware ainda precisa ser confirmado.

## Revisão de mudanças

Ao adicionar logging, tratamento de exceções ou persistência, verificar que a falha continua visível sem produzir um resultado de sucesso enganoso e sem incluir segredos. Referências: [CGI Intelbras](INTELBRAS-CGI.md), [RTSP](RTSP.md) e [arquitetura de armazenamento](ARCHITECTURE.md).

O aplicativo não lê `.env`: variáveis nesse arquivo seriam texto simples. `.env` é ignorado pelo Git, mas isso não protege seu conteúdo no disco.
