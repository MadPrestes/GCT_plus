# Interface gráfica

## Escopo e estado

`Modules/CameraUI.psm1` implementa uma GUI Windows Forms. Ainda não foi validada visualmente em um computador com as câmeras e VLC reais.

## Comportamentos a documentar

O MVP fornece:

- inicialização por `Start-GCT+.bat` em STA e leitura de `cameras.json`;
- seleção entre as três câmeras configuradas e campos de usuário/senha mascarada;
- botões ATUALIZAR, Flip/Mirror true/false e abertura dos streams VLC;
- painel de estado e log visual;
- execução de operações de rede em runspace de trabalho.

## Tratamento de resultados

O botão ATUALIZAR apresenta estados TCP HTTP, HTTP, TCP RTSP, Flip e Mirror. Testes não dependem de ICMP. Alterações CGI exigem confirmação e releitura; nenhuma escrita ocorre na inicialização.

Consultar [rede](NETWORK.md), [CGI Intelbras](INTELBRAS-CGI.md), [RTSP](RTSP.md) e [segurança](SECURITY.md).

## Execucao e primeiro teste

Execute `Start-GCT+.bat` com duplo clique. O aplicativo carrega a primeira câmera da lista e não inicia conexão automaticamente.

1. Se necessário, informe usuário e senha; marque **Salvar senha via DPAPI** apenas para persistir a senha criptografada.
2. Clique **Salvar configurações** se alterou usuário/credenciais.
3. Na caixa Senha, pressione **Enter** ou clique **ATUALIZAR** para testar HTTP/RTSP TCP e ler `VideoInOptions`. O evento Enter da própria caixa aciona o botão explicitamente.
4. Confira visualmente os estados antes de qualquer escrita. O primeiro teste deve ser somente leitura em um equipamento autorizado.

## Logs

`logs/gctplus.log` e o painel registram horário, severidade, IP, resultado e duração. Senhas, cabeçalhos Authorization e URI autenticado são excluídos. DEBUG pode exibir URL CGI sem credenciais, código HTTP, duração, respostas CGI, resultado do parser e exceções completas; detalhes de erro CGI são limitados a 1000 caracteres e somente visuais, não persistidos.

Os helpers de log e redação são exportados pelo módulo e carregados no escopo global pelo launcher porque os callbacks de Windows Forms podem ser executados fora do escopo privado do módulo.

## Concorrencia

As operações de rede não bloqueiam a thread de interface: são executadas em runspace separado e acompanhadas por timer. Os callbacks capturam explicitamente o estado da interface, e os caminhos dos módulos do worker são resolvidos antes da execução, sem depender do escopo de script do evento. Apenas uma operação ocorre por vez e os botões ficam desabilitados durante o trabalho.

Falhas vindas do runspace mostram a mensagem da exceção interna em vez do invólucro `EndInvoke`; com DEBUG, a cadeia completa e os detalhes CGI continuam disponíveis somente no painel.
