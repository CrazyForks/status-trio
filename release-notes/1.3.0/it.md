# Versione %VERSION% (build %BUILD%)

## Liquid Glass nativo su macOS 26 e successivi
- Il popover ora usa il materiale Liquid Glass del sistema invece dell’aspetto smerigliato ereditato dalle versioni precedenti di macOS, così si armonizza con i menu e i pannelli circostanti.
- Questa è l’aspetto del sistema, non uno stile dell’app: segue le impostazioni di sistema.
- macOS da 15 a 25 mantengono l’aspetto attuale; la versione minima del sistema resta invariata, quindi nessuno deve aggiornare macOS per continuare a usare Status Trio.

## Il pannello si apre sopra le app a schermo intero
- Facendo clic sull’icona della barra dei menu, il pannello di stato ora si apre anche quando un’altra app è a schermo intero. Prima si apriva dietro quell’app, quindi il clic sembrava non fare nulla.

## Aggiornamento in background più economico
- L’aggiornamento di riserva, cioè il timer che intercetta una modifica che il sistema non ha inviato all’app, ora viene eseguito ogni 15 secondi per impostazione predefinita invece che ogni 5, e macOS può spostare quel timer in modo che scatti insieme ad altre attività. L’icona si aggiorna comunque nel momento in cui il sistema segnala una modifica.
- La batteria viene controllata a ogni ciclo dell’aggiornamento di riserva. Wi-Fi e volume vengono controllati meno spesso mentre il pannello di stato e la finestra Impostazioni sono entrambi chiusi, e tornano al tuo intervallo di aggiornamento non appena uno dei due è sullo schermo.
- Il cursore dell’intervallo di aggiornamento arriva ancora fino a 5 secondi per chi vuole la cadenza precedente.
- La riga del volume non ridisegna più il pannello di stato quando la lettura del volume non è cambiata.

## Bluetooth non interroga più in background
- Il pannello Bluetooth in precedenza leggeva l’elenco dei dispositivi abbinati ogni 15 secondi finché l’app era in esecuzione, anche dopo la chiusura del pannello. Ora si aggiorna quando un dispositivo si connette o si disconnette, e ricorre a un controllo lento solo mentre una vista Bluetooth è sullo schermo.
- I dispositivi abbinati e i livelli della batteria ora provengono da un unico report di sistema invece che da due, il che dimezza il lavoro di ogni aggiornamento.
- I nomi dei dispositivi provengono ancora dalla stessa fonte e il comportamento delle autorizzazioni è invariato: l’app chiede ancora Bluetooth solo quando apri una vista Bluetooth.

## La scansione Wi-Fi si ferma quando smetti di guardare
- La pagina Wi-Fi in precedenza analizzava ogni canale circa ogni cinque secondi finché restava aperta, anche dopo il ritorno al riepilogo. Ora esegue la scansione quando apri la pagina, quando tocchi Aggiorna e quando attivi l’interruttore Wi-Fi, e nel frattempo mantiene l’ultimo risultato.
- Uscire dalla pagina Wi-Fi arresta il suo ciclo di scansione invece di lasciarlo in esecuzione in background.
- Sui Mac senza interfaccia Wi-Fi, per esempio un Mac mini o un Mac Studio collegato via Ethernet, l’app non ricostruisce più il monitoraggio Wi-Fi ogni 30 secondi; ora prova qualche volta e poi attende un risveglio o un cambiamento di rete.
- Nulla cambia nell’elenco in sé: le stesse reti, gli stessi dettagli e lo stesso pulsante di aggiornamento manuale.

## Il cambio di Wi-Fi resta nel sistema
- Il popover non si unisce più a una rete né passa da una all’altra. Scegliere una rete apre il pannello Wi-Fi delle Impostazioni di Sistema, e la pagina Wi-Fi lo dice sopra il pulsante che lo apre.
- Status Trio non legge né salva più le password Wi-Fi. Il comportamento precedente non poteva essere reso affidabile: macOS tiene per sé la password di una rete salvata, e una copia memorizzata diventata obsoleta finiva in connessioni non riuscite e in richieste ripetute del Portachiavi, senza alcun modo di dirti che la password era sbagliata.
- Se in una versione precedente hai selezionato **Ricorda la password nel Portachiavi**, quella voce del Portachiavi è ancora presente e non viene più usata. Puoi eliminarla in Accesso Portachiavi cercando `com.lingsmbp.StatusTrio.wifi-password`.
- Nient’altro è cambiato nella pagina: le stesse reti, gli stessi dettagli di segnale e collegamento, lo stesso interruttore Wi-Fi e lo stesso pulsante che apre le Impostazioni di Sistema.

## I livelli batteria Bluetooth sono attivi per impostazione predefinita
- **Mostra i livelli batteria Bluetooth** in **Impostazioni › Bluetooth** ora è attivo per impostazione predefinita: una volta attivato il pannello Bluetooth, un dispositivo connesso indica il suo livello senza dover attivare questo interruttore a parte. Disattivarlo interrompe comunque la lettura.
- La pagina dei dispositivi Bluetooth non mostra più **Non disponibile** su ogni riga: un dispositivo che non indica la batteria non mostra alcun testo della batteria, e un report illeggibile viene segnalato una volta sotto l’elenco.
