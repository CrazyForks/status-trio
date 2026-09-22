# Version %VERSION% (Build %BUILD%)

## Natives Liquid Glass unter macOS 26 und neuer
- Das Popover verwendet jetzt das systemeigene Liquid-Glass-Material von macOS 26 und passt damit zu den Menüs und Panels um es herum; Einstellungen wie Transparenz reduzieren greifen weiterhin.
- macOS 15 bis 25 behalten ihr bisheriges Erscheinungsbild; die Mindestsystemversion bleibt unverändert, niemand muss macOS aktualisieren, um Status Trio weiter zu nutzen.

## Bluetooth funktioniert besser
- Der Statusbereich listet deine gekoppelten Geräte jetzt sofort auf: Ein Tippen auf ein Gerät verbindet es, ein erneutes Tippen trennt es; das Trennen einer Tastatur oder Maus fragt zuerst in der Zeile selbst nach.
- Ziehe Geräte in den Einstellungen, um ihre Reihenfolge zu ändern; verbundene Geräte stehen immer zuerst.
- **Bluetooth-Batteriestände anzeigen** ist jetzt standardmäßig aktiviert, ohne dass dieser Schalter einzeln eingeschaltet werden muss.

## Wi-Fi-Wechsel bleibt im System
- Die App verbindet sich nicht mehr für dich mit Netzwerken: Die Auswahl eines Netzwerks öffnet den Wi-Fi-Bereich der Systemeinstellungen, wo du den Wechsel vornimmst.
- Status Trio liest und speichert keine Wi-Fi-Passwörter mehr.
- Wenn du in einer früheren Version **Passwort im Schlüsselbund merken** aktiviert hast, ist dieser Eintrag im Schlüsselbund noch vorhanden und wird nicht mehr verwendet.
- Deine Netzwerke, die Signaldetails und der Wi-Fi-Schalter funktionieren weiterhin wie zuvor.

## Verbraucht weniger Energie
- Deutlich weniger Hintergrundarbeit: Bluetooth fragt Geräte nicht mehr per Timer ab, die Wi-Fi-Suche endet, wenn du die Seite verlässt, und die Ersatzaktualisierung läuft jetzt alle 15 statt alle 5 Sekunden.
- Aktualisierungen kommen weiterhin an, sobald das System eine Änderung meldet, und dein Aktualisierungsintervall bleibt unverändert.

## Fehlerbehebungen und Verbesserungen
- Ein Klick auf das Menüleisten-Symbol öffnet den Statusbereich jetzt auch dann, wenn eine andere App im Vollbild läuft.
- Die Leistungswerte in den Batteriedetails sind genauer: „Systemleistung (geschätzt)“ bei Netzbetrieb, „Batterieentladung (geschätzt)“ im Batteriebetrieb.
- Eine für Wi-Fi verweigerte Standortberechtigung kann erneut angefragt werden, statt dauerhaft bei nicht verfügbaren Netzwerknamen zu bleiben.
- Wenn im System „Bewegung reduzieren“ aktiviert ist, läuft in der Einstellungsoberfläche keine Übergangsanimation mehr ab.

## Danke
- Danke an @hhh2210 für die Code-Beiträge zu dieser Version.
