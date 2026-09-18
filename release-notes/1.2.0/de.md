# Version %VERSION% (Build %BUILD%)

## Highlights: Bluetooth-Audio
- Die Bluetooth-Zeile im Popover zeigt jetzt den Live-Status: die Namen verbundener Geräte sowie bei AirPods den Batteriestand von links, rechts und Case. Andere Geräte zeigen nur ihren Namen.
- Während Audio über Bluetooth läuft, kann das mittlere Netzwerksymbol zum passenden Gerätesymbol wechseln (AirPods, Kopfhörer, Lautsprecher und so weiter) und blau dargestellt werden; auch die Lautstärkepunkte oder der Bogen werden blau, sodass die aktive Ausgabe sofort erkennbar ist.
- Neue Seite „Einstellungen > Bluetooth“: Schalter zum Ersetzen des Netzwerksymbols, für blaue Bluetooth-Lautstärke, für den Vorrang von Netzwerkfehlern und zum Anzeigen der Bluetooth-Batteriestände, plus eine Bluetooth-Symbolgröße von 100 %–180 %.
- Behoben: Ein in den Systemeinstellungen umbenanntes Gerät zeigte weiterhin seinen alten Namen.
- Behoben: Bluetooth-Batteriestände blieben auf „Nicht verfügbar“, nachdem zwischen Übersicht und Geräteseite gewechselt wurde.

## Batteriedetails
- Ein Klick auf die Batteriezeile im Popover öffnet eine eigene Seite mit Nennleistung des Netzteils, Restzeit, Energie sparendem Modus, Spannung, Strom, Messzeitpunkt und Ladezyklen.
- Neue Schätzung der Batterie-Nettoleistung: Beim Laden grün als „Laden (Schätzung)“ beschriftet, beim Entladen als „Entladen (Schätzung)“.
- Diese Werte sind bestmögliche Schätzungen und nicht der Gesamtverbrauch des Mac. Nach einem Wechsel der Stromquelle kann macOS bis zu einer Minute brauchen, um neue Werte zu melden; in dieser Zeit steht dort „Wird gemessen“ statt „Nicht verfügbar“.

## Wi-Fi-Übersicht
- Bei verbundenem Wi-Fi verwendet das Popover den Netzwerknamen (SSID) als Titel und zeigt darunter das aktuelle Frequenzband und die Signalstärke, zum Beispiel 5 GHz / -52 dBm.
- Fehlende Messwerte werden weggelassen statt als 0 angezeigt; Ethernet, offline und andere Nicht-Wi-Fi-Pfade zeigen sie nicht.

## Dein Symbol kennenlernen
- Eine Neuinstallation öffnet beim ersten Start die Anleitung „Lerne dein Symbol kennen“. Wähle den Batteriebogen, das mittlere Netzwerksymbol oder die Lautstärkeanzeige, um die jeweilige Bedeutung zu lesen; die Lautstärkeerklärung folgt deiner aktuellen Einstellung für Punkte oder Bogen.
- Die Anleitung enthält eine Galerie häufiger Zustandskombinationen: Laden, niedriger Batteriestand, Ethernet, kein Internet und stumm, Hotspot mit Energie sparendem Modus, schwaches Wi-Fi bei 25 % Lautstärke, Wi-Fi aus, Bluetooth-Kopfhörer, AirPods und Wi-Fi mit blauer Lautstärke.
- Ein Update auf diese Version, ein Neustart und bestehende Installationen öffnen sie nicht automatisch. Du kannst sie jederzeit über „Einstellungen“, „App-Symbol“, „Anleitung öffnen“ erneut aufrufen.

## Lautstärke
- Neuer Schalter „Natürliches Scrollen“: Ist er an, erhöht Scrollen nach oben mit Maus oder Trackpad die Lautstärke, unabhängig von der systemweiten Einstellung für natürliches Scrollen; ist er aus, folgt die Lautstärke der Scrollrichtung des Systems.
- Neue Auswahl „Anpassungsbereich“: überall im Panel scrollen oder nur auf dem Lautstärkeregler.
- Wenn Scrollen nach oben bei aktivierter Option die Lautstärke weiterhin senkt, kehrt ein Scroll-Werkzeug wie MOS, Scroll Reverser oder LinearMouse die Ereignisse um; nimm Status Trio in die Ausnahme- oder Ignorierliste dieser App auf.

## Einstellungen und Erscheinungsbild
- Lautstärkestil (Punkte oder Bogen), Symbolplatzierung und Ringstrichbreite sind jetzt visuelle Kartenauswahlen: Die Auswahl wird mit einem konzentrischen Ring markiert und direkt in der Karte angezeigt.
- Neue Einstellung „Ringstrichbreite“: Dünn, Standard oder Fett, angewendet auf den äußeren Batteriering, den Lautstärkebogen und die Lautstärkepunkte für ein schärferes Ergebnis auf Retina-Displays.
- Die Wahl „Nur Menüleiste“ warnt jetzt, dass das Dock-Symbol verschwindet, wenn das Einstellungsfenster geschlossen wird.
- Die Audio-Steuerelemente und die Fußzeile des Popovers sind kompakter: Der Stummschalter wandert in die Kopfzeile, doppelte Lautsprechersymbole entfallen, der Name des Ausgabegeräts wird zur Unterzeile und ein Eintrag „Weitere Aktionen“ kommt hinzu.
- Die Zeilen des Popovers teilen sich jetzt Symbolgröße und Abstände; das Standard-Symbol in der Menüleiste ist 24 pt und die Wi-Fi-Symbolskalierung beträgt standardmäßig 160 %.

## Korrekturen
- Das Ändern einer Symboloption zeichnet Menüleisten- und Dock-Symbol jetzt sofort neu statt einen Schritt später.
- Die Menüleisten-Vorschau in den Einstellungen bleibt oben auf der Seite fixiert, statt mit den Optionen zu scrollen.
- Ein Klick auf ein bekanntes Wi-Fi-Netzwerk öffnet direkt die Wi-Fi-Einstellungen des Systems.
- Das Wi-Fi-Symbol ist im Status-Symbol zentriert (issue #30).

## Danksagung
- Danke an @ReffWu und @hhh2210 für ihre Code-Beiträge zu dieser Version.
