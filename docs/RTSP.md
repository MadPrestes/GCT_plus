# RTSP

## Escopo e estado

`Modules/CameraUI.psm1` monta os URIs RTSP usados pelo VLC. A conexão TCP pode ser verificada pelo app, mas sessão/mídia e compatibilidade de autenticação exigem teste real.

## Endereço do stream

`Get-CameraRtspUri` monta `rtsp://IP:porta/cam/realmonitor?channel=1&subtype=N`, onde `N=0` é stream principal e `N=1` é substream. Credenciais só são incluídas quando configuradas. Os caracteres de usuário e senha são escapados; o URI autenticado não deve ser registrado.

## Conexão e reprodução

`Start-CameraVlc` procura VLC no PATH e em locais comuns de instalação do Windows e inicia o processo diretamente.

Uma verificação de porta TCP não prova que o URI, a autenticação ou o transporte RTSP sejam válidos. Relatar separadamente a conectividade TCP e o resultado de uma tentativa de sessão RTSP, quando ambos existirem.

## VLC

### `vlc`

`Start-CameraVlc` passa a URL RTSP como argumento ao processo VLC sem `Invoke-Expression`. Se VLC não for localizado, a interface apresenta erro. A porta TCP disponível não garante que o stream será reproduzido.

## Diagnóstico

Documentar mensagens e códigos de falha reais sem expor senha, URI com credenciais ou outros segredos. Associar logs a identificadores de câmera não sensíveis, se esse padrão existir e for confirmado. Consultar [rede](NETWORK.md) e [segurança](SECURITY.md).

O userinfo do URI autenticado pode ficar visível em argumentos do processo VLC para outros processos locais. Use somente em computador confiável; se possível, prefira credenciais fornecidas pelo VLC sem userinfo na linha de comando.
