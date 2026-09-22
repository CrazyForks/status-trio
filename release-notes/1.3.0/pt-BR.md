# Versão %VERSION% (compilação %BUILD%)

## Liquid Glass nativo no macOS 26 e posteriores
- O popover agora usa o material Liquid Glass do próprio sistema em vez do visual fosco herdado de versões anteriores do macOS, combinando com os menus e painéis ao redor.
- Esta é a aparência do sistema, não um estilo do app: ela segue os ajustes do seu sistema.
- O macOS 15 a 25 mantêm a aparência atual; a versão mínima do sistema não muda, então ninguém precisa atualizar o macOS para continuar usando o Status Trio.

## O painel abre sobre apps em tela cheia
- Clicar no ícone da barra de menus agora abre o painel de status mesmo quando outro app está em tela cheia. Antes, ele abria atrás desse app, então o clique parecia não fazer nada.

## Atualização em segundo plano mais econômica
- A atualização de reserva — o temporizador que captura uma mudança que o sistema não enviou ao app — agora ocorre a cada 15 segundos por padrão em vez de a cada 5, e o macOS pode deslocar esse temporizador para que ele dispare junto de outro trabalho. O ícone continua atualizando no momento em que o sistema informa uma mudança.
- A bateria é verificada a cada ciclo da atualização de reserva. Wi-Fi e volume são verificados com menos frequência enquanto o Painel de status e a janela de ajustes estiverem ambos fechados, e voltam ao seu “Intervalo de atualização” assim que um dos dois estiver na tela.
- O controle deslizante do “Intervalo de atualização” ainda vai até 5 segundos para quem quiser a cadência antiga.
- A linha de volume não redesenha mais o Painel de status quando a leitura de volume não mudou.

## O Bluetooth não faz mais consultas em segundo plano
- O painel de Bluetooth lia a lista de dispositivos pareados a cada 15 segundos enquanto o app estivesse em execução, mesmo depois de o painel ser fechado. Agora ele é atualizado quando um dispositivo se conecta ou se desconecta, e recorre a uma verificação lenta apenas enquanto uma visualização de Bluetooth estiver na tela.
- Dispositivos pareados e níveis de bateria agora vêm de um único relatório do sistema em vez de dois, o que reduz pela metade o trabalho de cada atualização.
- Os nomes dos dispositivos continuam vindo da mesma origem, e o comportamento de permissão não mudou: o app ainda pede Bluetooth apenas quando você abre uma visualização de Bluetooth.

## A busca por redes Wi-Fi é interrompida quando você para de olhar
- A página de Wi-Fi costumava varrer cada canal a cada cinco segundos, aproximadamente, enquanto estivesse aberta, mesmo depois de você voltar ao resumo. Agora ela busca quando você abre a página, quando você clica em atualizar e quando você alterna o rádio, e mantém o último resultado entre uma busca e outra.
- Sair da página de Wi-Fi interrompe o ciclo de busca em vez de deixá-lo rodando em segundo plano.
- Em Macs sem interface Wi-Fi — um Mac mini ou Mac Studio em Ethernet, por exemplo — o app não reconstrói mais o monitoramento de Wi-Fi a cada 30 segundos; agora ele tenta algumas vezes e depois espera um despertar ou uma mudança de rede.
- Nada na própria lista muda: as mesmas redes, os mesmos detalhes e o mesmo botão de atualização manual.

## A troca de Wi-Fi continua no sistema
- O popover não entra mais em uma rede nem alterna entre elas. Escolher uma rede abre o painel de Wi-Fi dos Ajustes do Sistema, e a página de Wi-Fi diz isso acima do botão que a abre.
- O Status Trio não lê nem armazena mais senhas de Wi-Fi. O comportamento antigo não podia ser confiável: o macOS guarda para si a senha de uma rede salva, e uma cópia armazenada que ficou desatualizada acabava em falhas de conexão e repetidas solicitações das Chaves, sem nenhuma forma de avisar que a senha estava errada.
- Se você marcou **Lembrar a senha nas Chaves** em uma versão anterior, esse item das Chaves ainda existe e não é mais usado. Você pode excluí-lo no “Acesso às Chaves” procurando por `com.lingsmbp.StatusTrio.wifi-password`.
- Nada mais na página mudou: as mesmas redes, os mesmos detalhes de sinal e link, o mesmo interruptor de Wi-Fi e o mesmo botão que abre os Ajustes do Sistema.

## Níveis de bateria Bluetooth vêm ativados por padrão
- **Mostrar níveis de bateria Bluetooth** em **Ajustes › Bluetooth** agora vem ativado por padrão: com o painel de Bluetooth ativado, um dispositivo conectado informa seu nível sem precisar ativar este interruptor separadamente. Desativá-lo continua interrompendo a leitura.
- A página de dispositivos Bluetooth não exibe mais **Indisponível** em cada linha: um dispositivo que não informa bateria não exibe nenhum texto de bateria, e um relatório que não pode ser lido é avisado uma vez abaixo da lista.

## Dispositivos emparelhados no painel de status
- **Ajustes › Bluetooth** agora pode listar os dispositivos emparelhados sob a linha Bluetooth: os primeiros ficam sempre visíveis, o restante aparece atrás do controle Expandir, e o máximo é você quem define. Os dispositivos conectados aparecem sempre primeiro.
- Arraste os dispositivos em Ajustes para definir a ordem mostrada no painel. Dispositivos novos aparecem no final.
