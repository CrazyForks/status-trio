# Versão %VERSION% (compilação %BUILD%)

## Destaques: áudio Bluetooth
- A linha Bluetooth do popover agora mostra o estado ao vivo: os nomes dos dispositivos conectados e, nos AirPods, a bateria do esquerdo, do direito e do estojo. Os outros dispositivos mostram apenas o nome.
- Enquanto o áudio é reproduzido por Bluetooth, o ícone de rede central pode mudar para o glifo do dispositivo correspondente (AirPods, fones, alto-falantes e assim por diante) e aparecer em azul, com os pontos ou o arco de volume também em azul, deixando claro de imediato qual saída está ativa.
- Nova página “Ajustes > Bluetooth”: chaves para substituir o ícone de rede, usar o volume Bluetooth em azul, dar prioridade aos erros de rede e mostrar os níveis de bateria Bluetooth, além de um tamanho de ícone Bluetooth de 100% a 180%.
- Corrigido o caso em que um dispositivo renomeado nos Ajustes do Sistema continuava mostrando o nome antigo.
- Corrigido o caso em que os níveis de bateria Bluetooth ficavam em “Indisponível” ao alternar entre o resumo e a página do dispositivo.

## Detalhes da bateria
- Tocar na linha da bateria no popover abre uma página dedicada com a potência nominal do adaptador, o tempo restante, o modo de baixo consumo, a tensão, a corrente, o horário da amostra e a contagem de ciclos.
- Nova estimativa de potência líquida da bateria: ao carregar, aparece em verde como “Carregando (estimativa)”; ao descarregar, como “Descarregando (estimativa)”.
- Esses valores são estimativas de melhor esforço, não o consumo total do Mac. Após trocar a fonte de energia, o macOS pode levar até um minuto para informar novos valores; nesse intervalo é exibido “Amostrando” em vez de “Indisponível”.

## Resumo do Wi-Fi
- Com o Wi-Fi conectado, o popover usa o nome da rede (SSID) como título e mostra abaixo a faixa e a intensidade do sinal, por exemplo 5 GHz / -52 dBm.
- Medições ausentes são omitidas em vez de exibidas como 0; Ethernet, offline e outros caminhos que não são Wi-Fi não as mostram.

## Conheça seu ícone
- Uma instalação nova abre o guia “Conheça seu ícone” na primeira execução. Selecione o arco da bateria, o glifo de rede central ou o indicador de volume para ler o que cada um significa; a explicação do volume segue o seu ajuste atual de pontos ou arco.
- O guia inclui uma galeria de combinações de estado comuns: carregando, bateria fraca, Ethernet, sem Internet e sem som, ponto de acesso com modo de baixo consumo, Wi-Fi fraco com 25% de volume, Wi-Fi desativado, fones Bluetooth, AirPods e Wi-Fi com volume azul.
- Atualizar para esta versão, reiniciar e instalações existentes não o abrem automaticamente. Você pode reabri-lo a qualquer momento em “Ajustes”, “Ícone do app”, “Abrir guia”.

## Volume
- Nova chave “Rolagem natural”: quando ativada, rolar para cima com o mouse ou trackpad aumenta o volume, independentemente da preferência de rolagem natural do sistema; quando desativada, o volume segue a direção de rolagem do sistema.
- Nova opção “Área de ajuste”: rolar em qualquer lugar do painel ou apenas sobre o controle de volume.
- Se, com a opção ativada, rolar para cima ainda diminuir o volume, um utilitário de rolagem como MOS, Scroll Reverser ou LinearMouse está invertendo os eventos; adicione o Status Trio à lista de exceções ou de ignorados desse app.

## Ajustes e aparência
- O estilo do volume (pontos ou arco), a posição do ícone e a espessura do traço do anel agora são seletores visuais: a seleção é marcada com um anel concêntrico e a prévia aparece no próprio cartão.
- Novo ajuste “Espessura do traço do anel”: fina, padrão ou grossa, aplicada ao anel externo da bateria, ao arco de volume e aos pontos de volume para um resultado mais nítido em telas Retina.
- Escolher “Somente barra de menus” agora avisa que o ícone do Dock desaparece ao fechar a janela de ajustes.
- Os controles de áudio e o rodapé do popover estão mais compactos: a chave de mudo vai para o cabeçalho, os ícones de alto-falante duplicados são removidos, o nome do dispositivo de saída vira um subtítulo e é adicionada uma entrada “Mais ações”.
- As linhas do popover agora compartilham o mesmo tamanho de ícone e espaçamento; o ícone padrão da barra de menus é de 24 pt e a escala do símbolo de Wi-Fi é de 160% por padrão.

## Correções
- Alterar uma opção de ícone agora redesenha imediatamente os ícones da barra de menus e do Dock, sem atraso.
- A prévia da barra de menus nos Ajustes fica fixada no topo da página em vez de rolar com as opções.
- Clicar em uma rede Wi-Fi conhecida abre diretamente os ajustes de Wi-Fi do sistema.
- O símbolo de Wi-Fi está centralizado no ícone de status (issue #30).

## Agradecimentos
- Agradecemos a @ReffWu e @hhh2210 pelas contribuições de código a esta versão.
