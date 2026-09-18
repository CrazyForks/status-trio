# Versione %VERSION% (build %BUILD%)

## In evidenza: audio Bluetooth
- La riga Bluetooth del popover ora mostra lo stato in tempo reale: i nomi dei dispositivi connessi e, per gli AirPods, la batteria di sinistro, destro e custodia. Gli altri dispositivi mostrano solo il nome.
- Mentre l’audio viene riprodotto via Bluetooth, l’icona di rete centrale può passare al glifo del dispositivo corrispondente (AirPods, cuffie, altoparlanti e così via) e viene mostrata in blu, con i punti o l’arco del volume che diventano blu, così l’uscita attiva si riconosce a colpo d’occhio.
- Nuova pagina «Impostazioni > Bluetooth»: interruttori per sostituire l’icona di rete, usare il volume Bluetooth in blu, dare priorità agli errori di rete e mostrare i livelli della batteria Bluetooth, oltre a una dimensione dell’icona Bluetooth dal 100% al 180%.
- Risolto il problema per cui un dispositivo rinominato in Impostazioni di Sistema continuava a mostrare il vecchio nome.
- Risolto il problema per cui i livelli della batteria Bluetooth restavano su «Non disponibile» passando dal riepilogo alla pagina del dispositivo.

## Dettagli batteria
- Toccando la riga della batteria nel popover si apre una pagina dedicata con potenza nominale dell’alimentatore, tempo rimanente, risparmio energetico, tensione, corrente, ora di campionamento e numero di cicli.
- Nuova stima della potenza netta della batteria: in carica è etichettata in verde come «In carica (stima)», in scarica come «In scarica (stima)».
- Questi valori sono stime del miglior sforzo possibile, non il consumo totale del Mac. Dopo un cambio di alimentazione macOS può impiegare fino a un minuto per comunicare i nuovi valori; in quel periodo viene mostrato «Campionamento» invece di «Non disponibile».

## Riepilogo Wi-Fi
- Quando il Wi-Fi è connesso, il popover usa il nome della rete (SSID) come titolo e mostra sotto la banda e l’intensità del segnale, per esempio 5 GHz / -52 dBm.
- Le misurazioni mancanti vengono omesse invece di essere mostrate come 0; Ethernet, offline e gli altri percorsi non Wi-Fi non le mostrano.

## Scopri la tua icona
- Una nuova installazione apre la guida «Conosci la tua icona» al primo avvio. Seleziona l’arco della batteria, il glifo di rete centrale o l’indicatore del volume per leggere cosa significa ciascuno; la spiegazione del volume segue l’impostazione attuale di punti o arco.
- La guida include una galleria delle combinazioni di stato più comuni: in carica, batteria scarica, Ethernet, senza Internet e muto, hotspot con risparmio energetico, Wi-Fi debole al 25% del volume, Wi-Fi disattivato, cuffie Bluetooth, AirPods e Wi-Fi con volume blu.
- L’aggiornamento a questa versione, il riavvio e le installazioni esistenti non la aprono automaticamente. Puoi riaprirla in qualsiasi momento da «Impostazioni», «Icona dell’app», «Apri guida».

## Volume
- Nuovo interruttore «Scorrimento naturale»: quando è attivo, scorrendo verso l’alto con mouse o trackpad il volume aumenta, indipendentemente dalla preferenza di scorrimento naturale del sistema; quando è disattivato, il volume segue la direzione di scorrimento del sistema.
- Nuova scelta «Area di regolazione»: scorrere ovunque nel pannello oppure solo sul controllo del volume.
- Se con questa opzione attiva lo scorrimento verso l’alto abbassa ancora il volume, un’utility di scorrimento come MOS, Scroll Reverser o LinearMouse sta invertendo gli eventi; aggiungi Status Trio alla sua lista di eccezioni o di esclusioni.

## Impostazioni e aspetto
- Lo stile del volume (punti o arco), la posizione dell’icona e lo spessore del tratto dell’anello sono ora selettori visivi: la selezione è contrassegnata da un anello concentrico e l’anteprima appare nella scheda.
- Nuova impostazione «Spessore del tratto dell’anello»: sottile, standard o spesso, applicata all’anello esterno della batteria, all’arco del volume e ai punti del volume per un risultato più nitido sui display Retina.
- Scegliendo «Solo barra dei menu» ora viene avvisato che l’icona nel Dock scompare alla chiusura della finestra delle impostazioni.
- I controlli audio e il piè di pagina del popover sono più compatti: l’interruttore del silenzio passa nell’intestazione, le icone degli altoparlanti duplicate vengono rimosse, il nome del dispositivo di uscita diventa un sottotitolo e viene aggiunta una voce «Altre azioni».
- Le righe del popover ora condividono la stessa dimensione delle icone e la stessa spaziatura; l’icona predefinita nella barra dei menu è di 24 pt e la scala del simbolo Wi-Fi è del 160% per impostazione predefinita.

## Correzioni
- Modificando un’opzione dell’icona, le icone della barra dei menu e del Dock vengono ridisegnate subito, senza ritardo.
- L’anteprima della barra dei menu nelle impostazioni resta fissa in cima alla pagina invece di scorrere con le opzioni.
- Facendo clic su una rete Wi-Fi conosciuta si aprono direttamente le impostazioni Wi-Fi del sistema.
- Il simbolo Wi-Fi è centrato nell’icona di stato (issue #30).

## Ringraziamenti
- Grazie a @ReffWu e @hhh2210 per i loro contributi di codice a questa versione.
