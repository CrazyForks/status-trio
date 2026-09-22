# Versione %VERSION% (build %BUILD%)

## Liquid Glass nativo su macOS 26
- Il popover ora usa il materiale Liquid Glass di macOS 26 e si armonizza con i menu di sistema; impostazioni come Riduci trasparenza continuano ad avere effetto.
- macOS da 15 a 25 mantengono l’aspetto attuale; la versione minima del sistema resta invariata, quindi nessuno deve aggiornare macOS per continuare a usare Status Trio.

## Il Bluetooth funziona meglio
- Il pannello di stato ora elenca subito i tuoi dispositivi abbinati: tocca uno per connetterlo, toccalo di nuovo per disconnetterlo; disconnettere una tastiera o un mouse chiede prima conferma, nella riga stessa.
- Trascina i dispositivi in Impostazioni per cambiarne l’ordine; i dispositivi connessi sono sempre elencati per primi.
- I livelli batteria Bluetooth ora vengono mostrati per impostazione predefinita, senza alcun interruttore da attivare.

## Il cambio di Wi-Fi resta nel sistema
- L’app non si unisce più alle reti al tuo posto: toccare una rete apre il pannello Wi-Fi delle Impostazioni di Sistema, dove sei tu a cambiare rete.
- Status Trio non legge né salva più le password Wi-Fi.
- Una password salvata da una versione precedente potrebbe ancora essere presente nel Portachiavi, ma non viene più usata.
- Vedere le tue reti, i dettagli del segnale e l’interruttore Wi-Fi funziona come prima.

## Consuma meno energia
- Molto meno lavoro in background: Bluetooth non interroga più i dispositivi con un timer, la scansione Wi-Fi si ferma quando lasci la pagina, e l’aggiornamento di riserva è passato da ogni 5 secondi a ogni 15.
- Gli aggiornamenti arrivano comunque nel momento in cui il sistema segnala una modifica, e l’impostazione dell’intervallo di aggiornamento resta invariata.

## Correzioni e miglioramenti
- Facendo clic sull’icona della barra dei menu, il pannello di stato ora si apre anche quando un’altra app è a schermo intero.
- Le letture di potenza nei dettagli batteria sono più precise: "Consumo sistema (stimato)" con l’alimentazione collegata, "Scarica batteria (stimata)" a batteria.
- Un’autorizzazione della posizione rifiutata per il Wi-Fi può essere richiesta di nuovo, invece di restare bloccati con i nomi delle reti non disponibili.
- Con l’impostazione di sistema Riduci movimento attivata, l’interfaccia delle impostazioni non riproduce più le animazioni di transizione.

## Grazie
- Grazie a @hhh2210 per i contributi al codice di questa versione.
