# Version %VERSION% (Build %BUILD%)

## Natives Liquid Glass unter macOS 26 und neuer
- Das Popover verwendet jetzt das systemeigene Liquid-Glass-Material statt der von früheren macOS-Versionen übernommenen Milchglas-Optik und passt damit zu den Menüs und Panels um es herum.
- Dies ist die Systemdarstellung und kein app-eigener Stil: Sie folgt deinen Systemeinstellungen.
- macOS 15 bis 25 behalten ihr bisheriges Erscheinungsbild; die Mindestsystemversion bleibt unverändert, niemand muss macOS aktualisieren, um Status Trio weiter zu nutzen.

## Panel öffnet sich über Vollbild-Apps
- Ein Klick auf das Menüleisten-Symbol öffnet den Statusbereich jetzt auch dann, wenn eine andere App im Vollbild läuft. Bisher öffnete er sich hinter dieser App, sodass der Klick wirkungslos erschien.

## Günstigere Hintergrundaktualisierung
- Die Ersatzaktualisierung, also der Timer, der eine Änderung erfasst, die das System nicht an die App gepusht hat, läuft jetzt standardmäßig alle 15 Sekunden statt alle 5 Sekunden, und macOS kann diesen Timer verschieben, damit er zusammen mit anderen Aufgaben ausgeführt wird. Das Symbol wird weiterhin sofort aktualisiert, sobald das System eine Änderung meldet.
- Die Batterie wird bei jedem Durchlauf der Ersatzaktualisierung geprüft. Wi-Fi und Lautstärke werden seltener geprüft, solange Statusbereich und Einstellungsfenster beide geschlossen sind, und kehren zu deinem Aktualisierungsintervall zurück, sobald eines von beiden auf dem Bildschirm ist.
- Der Schieberegler für das Aktualisierungsintervall geht weiterhin bis auf 5 Sekunden herunter, falls jemand den alten Rhythmus möchte.
- Die Lautstärkezeile zeichnet den Statusbereich nicht mehr neu, wenn sich der Lautstärkewert nicht geändert hat.

## Bluetooth fragt nicht mehr im Hintergrund ab
- Der Bluetooth-Bereich hat früher alle 15 Sekunden die Liste der gekoppelten Geräte gelesen, solange die App lief, auch nachdem der Bereich geschlossen wurde. Jetzt aktualisiert er sich, wenn sich ein Gerät verbindet oder trennt, und greift nur dann auf eine langsame Prüfung zurück, während eine Bluetooth-Ansicht auf dem Bildschirm ist.
- Gekoppelte Geräte und Batteriestände stammen jetzt aus einem einzigen Systembericht statt aus zwei, was den Aufwand jeder Aktualisierung halbiert.
- Die Übersichtszeile und die Geräteseite sind unverändert: dieselben Namen, dieselben Stände und dasselbe Berechtigungsverhalten. Die App fragt weiterhin nur dann nach Bluetooth, wenn du eine Bluetooth-Ansicht öffnest.

## Wi-Fi-Suche endet, wenn du nicht mehr hinsiehst
- Die Wi-Fi-Seite hat früher etwa alle fünf Sekunden jeden Kanal durchsucht, solange sie geöffnet war, auch nachdem du zur Übersicht zurückgekehrt bist. Jetzt sucht sie, wenn du die Seite öffnest, wenn du auf Aktualisieren tippst und wenn du den Wi-Fi-Schalter umlegst, und behält dazwischen das letzte Ergebnis.
- Das Verlassen der Wi-Fi-Seite beendet ihre Suchschleife, statt sie im Hintergrund weiterlaufen zu lassen.
- Auf Macs ohne Wi-Fi-Schnittstelle, zum Beispiel einem Mac mini oder Mac Studio am Ethernet, baut die App ihre Wi-Fi-Überwachung nicht mehr alle 30 Sekunden neu auf; sie versucht es jetzt ein paar Mal und wartet dann auf ein Aufwachen oder eine Netzwerkänderung.
- An der Liste selbst ändert sich nichts: dieselben Netzwerke, dieselben Details und dieselbe Schaltfläche zum manuellen Aktualisieren.

## Wi-Fi-Wechsel bleibt im System
- Das Popover verbindet sich nicht mehr mit einem Netzwerk und wechselt auch nicht mehr zwischen Netzwerken. Die Auswahl eines Netzwerks öffnet den Wi-Fi-Bereich der Systemeinstellungen, und die Wi-Fi-Seite weist oberhalb der Schaltfläche, die ihn öffnet, darauf hin.
- Status Trio liest und speichert keine Wi-Fi-Passwörter mehr. Das frühere Verhalten ließ sich nicht zuverlässig umsetzen: macOS behält das Passwort eines gespeicherten Netzwerks für sich, und eine gespeicherte Kopie, die veraltet war, endete in fehlgeschlagenen Verbindungen und wiederholten Abfragen des Schlüsselbunds, ohne dir sagen zu können, dass das Passwort falsch war.
- Wenn du in einer früheren Version **Passwort im Schlüsselbund merken** aktiviert hast, ist dieser Eintrag im Schlüsselbund noch vorhanden und wird nicht mehr verwendet. Du kannst ihn in der Schlüsselbundverwaltung löschen, indem du nach `com.lingsmbp.StatusTrio.wifi-password` suchst.
- Sonst hat sich an der Seite nichts geändert: dieselben Netzwerke, dieselben Signal- und Verbindungsdetails, derselbe Wi-Fi-Schalter und dieselbe Schaltfläche, die die Systemeinstellungen öffnet.
