<p align="center">
  <img src="screenshots/status-trio-dock-state-strip-symmetric.png" width="1000" alt="Acht Status Trio Dock-Symbolzustände mit symmetrisch angeordneten dunklen und hellen Hintergründen, darunter Wi-Fi-, Bluetooth-Audio-, Batterie-, Punkte- und Bogen-Zustände">
</p>

<p align="center">
  <img src="Support/AppIcon.png" width="112" alt="Status Trio App-Symbol">
</p>

<h1 align="center">Status Trio</h1>

<p align="center">
  <a href="https://trendshift.io/repositories/234371?utm_source=trendshift-badge&utm_medium=badge&utm_campaign=badge-trendshift-234371" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/234371/daily?language=Swift" alt="lingyired/status-trio | Trendshift" width="250" height="55"/></a>
</p>

<p align="center"><strong>Drei Systemsignale. Ein natives macOS-Statussymbol — in Ihrer Menüleiste oder im Dock.</strong></p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/badge/Download%20for%20macOS-Universal%20%C2%B7%20macOS%2015%2B-000000?logo=apple&logoColor=white&style=for-the-badge" alt="Für macOS laden — Universal-Build, macOS 15 oder neuer"></a>
</p>

<p align="center">
  Möchten Sie es zuerst in Aktion sehen? Öffnen Sie <a href="https://statustrio.lingai.net/">statustrio.lingai.net</a>, um jeden Symbolzustand in Ihrem Browser zu simulieren.
</p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/github/v/release/lingyired/status-trio?label=release&color=blue" alt="Neueste Version"></a>
  <a href="https://github.com/lingyired/status-trio/actions/workflows/release.yml"><img src="https://github.com/lingyired/status-trio/actions/workflows/release.yml/badge.svg" alt="Status des Build-and-Release-Workflows für macOS"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/lingyired/status-trio?label=license" alt="Lizenz: Apache-2.0"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B%20supported-blue?logo=apple&logoColor=white" alt="macOS 15 oder neuer wird unterstützt">
  <img src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%7C%20Intel-lightgrey" alt="Universal-Binary für Apple Silicon und Intel">
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-Hans.md">简体中文</a> ·
  <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <strong>Deutsch</strong> ·
  <a href="README.pt-BR.md">Português (Brasil)</a> ·
  <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="screenshots/menu-bar-wifi.jpg" width="1000" alt="Status Trio Menüleistensymbol mit dem Wi-Fi-Symbol bei bestehender Wi-Fi-Verbindung und geöffnetem Status-Popover">
</p>

Status Trio ist eine native macOS-Status-App, die Wi-Fi, Batterie und Lautstärke in einem einzigen kompakten, konfigurierbaren Symbol vereint, das in der Menüleiste, im Dock oder an beiden Orten angezeigt wird. Das Popover bietet mehr als das Symbol: ein Wi-Fi-Bereich für Netzwerke in der Nähe und Verbindungsdetails, ein Bluetooth-Bereich für gekoppelte Geräte, eine Seite „Batteriedetails“ und die Audiogeräte, die gerade wiedergeben. Inspiriert ist sie vom kombinierten Statusleisten-Symbol des iPhone Duo für Wi-Fi, Batterie und Mobilfunkdaten, angepasst für den Mac mit Lautstärke statt Mobilfunkdaten.

> Status Trio ist ein unabhängiges Projekt und steht in keiner Verbindung zu Apple.

## Funktionen

- **Ein Symbol, drei Signale** — Batterie, Wi-Fi und Lautstärke teilen sich ein Symbol in der Menüleiste, im Dock oder an beiden Orten, und ein Bluetooth-Gerät, das gerade wiedergibt, kann mit seinem eigenen Symbol den mittleren Platz einnehmen.
- **Bluetooth** — die Lautstärkeanzeige wird blau, während der Wiedergabe. Der Bluetooth-Bereich listet gekoppelte Geräte auf, die Sie antippen können, um sie zu verbinden oder zu trennen, zeigt standardmäßig die Batteriestände und bleibt aus, bis Sie ihn aktivieren.
- **Batterie** — Prozentsatz, Laden oder Netzbetrieb, Zeit bis voll und eine Farbe, wenn der Ladestand niedrig wird. Öffnen Sie die Zeile für Netzteil-Nennleistung, Batteriespannung, Batteriestrom, Ladezyklen und Stromsparmodus.
- **Wi-Fi** — das Netzwerk, mit dem Sie verbunden sind, und die Signalstärke. Öffnen Sie es, um Netzwerke in der Nähe zu sehen, die Verbindungsdetails zu prüfen oder Wi-Fi auszuschalten. Der Wechsel zwischen Netzwerken findet im Wi-Fi-Bereich der Systemeinstellungen statt.
- **Lautstärke** — Pegel, Stummschaltung und das Ausgabegerät, dargestellt als Punkte oder Bogen. Scrollen Sie im ganzen Bereich oder nur im Lautstärkeregler, und wählen Sie, in welche Richtung die Lautstärke erhöht wird.
- **Nach Ihren Wünschen** — Symbolgröße, Symbolskalierung, Stärke des äußeren Rings, Statusfarben und welche Elemente das Popover zeigt, in der Reihenfolge Ihrer Wahl.
- **Menüleiste, Dock oder beides** — und das Dock-Symbol kann der Systemeinstellung folgen oder dunkel bzw. hell bleiben.
- **Nativ auf macOS** — ein Linksklick öffnet das Popover, ein Rechtsklick das Menü, und eine Anleitung beim ersten Start erklärt jeden Teil des Symbols. Ethernet, ein persönlicher Hotspot oder Internetfreigabe können das Wi-Fi-Symbol beibehalten, wenn Sie das bevorzugen.
- **Immer aktuell** — der Status stammt aus Systemereignissen, mit einer langsamen Abfrage als Ersatzlösung, und Sparkle aktualisiert die App über einen signierten Feed.
- **Ebenfalls enthalten** — zwölf Sprachen und die Option „Beim Anmelden starten“.

## Bluetooth-Audio

Während Audio über Bluetooth wiedergegeben wird, lassen zwei Schalter unter **Einstellungen › Bluetooth** das mittlere Symbol zum eigenen Symbol dieses Geräts werden — AirPods, Kopfhörer, Lautsprecher und andere Geräte bringen ihr eigenes mit — und lassen die Lautstärkepunkte oder den Bogen blau werden. Beide sind standardmäßig aus. **Netzwerkfehler priorisieren**, standardmäßig aktiviert, behält das Netzwerksymbol, solange die Verbindung selbst Probleme hat:

<p align="center">
  <img src="screenshots/menu-bar-airpods.jpg" width="1000" alt="Status Trio Menüleistensymbol mit dem AirPods-Symbol bei verbundenen AirPods und geöffnetem Status-Popover">
</p>

Die Bluetooth-Zeile des Popovers meldet den Live-Status: die Namen verbundener Geräte und bei AirPods den Batteriestand von linkem Hörer, rechtem Hörer und Ladecase. Der Bluetooth-Bereich listet gekoppelte Geräte und ihren Verbindungsstatus auf: Tippen Sie ein Gerät an, um es zu verbinden, und ein verbundenes, um es zu trennen — Tastaturen, Mäuse, Trackpads und Gamepads fragen zuerst in der Zeile nach der Bestätigung. Er ist standardmäßig aus, wird unter **Einstellungen › Statusbereich** aktiviert und fragt bei der ersten Verwendung nach der Bluetooth-Berechtigung. **Einstellungen › Bluetooth** steuert außerdem, ob die Batteriestände gelesen werden (standardmäßig an), listet die gekoppelten Geräte auf, damit Sie sie in die gewünschte Reihenfolge ziehen und die Anzahl der angezeigten Geräte festlegen können, und skaliert das Bluetooth-Symbol von 100 % bis 180 %.

## Dock-Symbol

Dasselbe Live-Symbol kann statt in der Menüleiste im Dock angezeigt werden oder an beiden Orten gleichzeitig:

<p align="center">
  <img src="screenshots/status-trio-dock-dark-1440x810.jpg" width="880" alt="Status Trio Live-Symbol im Dock mit dunkler Darstellung">
  <br>
  <sub>Dock-Symbol in dunkler Darstellung</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-1440x810.jpg" width="880" alt="Status Trio Live-Symbol im Dock mit heller Darstellung">
  <br>
  <sub>Dock-Symbol in heller Darstellung</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-bt-1440x810.jpg" width="880" alt="Status Trio im Dock mit angezeigtem Bluetooth-Bereich, helle Darstellung">
  <br>
  <sub>Vorschau des Bluetooth-Bereichs</sub>
</p>

Das Dock-Symbol zeichnet dasselbe kombinierte Symbol wie die Menüleiste, sodass bei aktiviertem Ersetzen durch Bluetooth-Audio auch dort das Gerätesymbol die Mitte übernimmt. Sein Hintergrund kann dem Symbol- und Widgetstil des Systems folgen oder auf einen festen Farbton festgelegt werden:

<p align="center">
  <img src="screenshots/status-trio-dock-icons.png" width="880" alt="Status Trio Dock-Symbol mit dunklem, hellem und klarem Hintergrund in zwei Reihen: der Wi-Fi-Zustand und Bluetooth-Audio, das das Wi-Fi-Symbol durch blaue Lautstärkepunkte ersetzt">
</p>

## Symbolzustände

Jeder Zustand, den das kombinierte Symbol anzeigen kann, gezeichnet vom eigenen Renderer der App — Batterieanzeigen oben, Wi-Fi (oder das Bluetooth-Audiogerät, das es ersetzen kann, wenn diese Option aktiv ist) in der Mitte und Lautstärkepunkte oder der Bogen unten, die blau werden, während ein Bluetooth-Gerät wiedergibt:

<p align="center">
  <img src="screenshots/status-trio-icon-states.png" width="880" alt="Status Trio Symbolzustände: Laden, Netzbetrieb, Prozentsatz, niedriger Ladestand und Energiesparmodus oben; Wi-Fi-Signal, Hotspot, temporär, geteilt und kabelgebunden in der Mitte; darunter Bluetooth-Audio, das das Wi-Fi-Symbol ersetzt, Wi-Fi bleibt bei einem Netzwerkfehler, sowie blaue Lautstärkepunkte und der Bogen; unten Lautstärkepunkte und Bogenstile für jeden Pegel">
</p>

Dieselben Zustände für eine dunkle Menüleiste dargestellt:

<p align="center">
  <img src="screenshots/status-trio-icon-states-dark.png" width="880" alt="Dieselben Status Trio Symbolzustände in dunkler Darstellung: weiße Symbole auf dunklen Flächen, grünes Laden, roter niedriger Ladestand und gelbe Energiesparmodus-Akzente sowie das hellere Blau, das die App für Bluetooth-Audio auf einer dunklen Menüleiste verwendet">
</p>

## Voraussetzungen

- macOS 15 oder neuer zum Ausführen der App
- Swift-6-Toolchain mit dem macOS-26-SDK (Xcode 26 oder neuer), um sie zu bauen. Ein Build gegen ein
  älteres SDK erzeugt stillschweigend die Popover-Darstellung von vor Tahoe, deshalb schlägt `scripts/build-app.sh` fehl,
  wenn das SDK älter als 26 ist.

## Aus dem Quellcode starten

```bash
git clone https://github.com/lingyired/status-trio.git
cd status-trio
swift run StatusTrio
```

## Lokale App bauen

Bauen Sie ein ad-hoc-signiertes App-Bundle und starten Sie es:

```bash
bash scripts/build-app.sh release
```

Das Bundle wird unter `dist/StatusTrio.app` erstellt. Um zu bauen, ohne eine vorhandene Instanz zu beenden oder zu starten, führen Sie aus:

```bash
bash scripts/build-app.sh release no-open
```

Das ad-hoc-signierte Bundle ist für die lokale persönliche Nutzung gedacht. Gatekeeper kann es ablehnen, wenn das Bundle mit Quarantäne-Metadaten übertragen wird.

## Ein GitHub-Release installieren

Laden Sie die neueste `StatusTrio-*.dmg` von der [GitHub-Releases-Seite](https://github.com/lingyired/status-trio/releases) herunter, öffnen Sie sie und kopieren Sie `Status Trio.app` nach `/Applications`.

Der aktuelle öffentliche Build ist ad-hoc-signiert, aber nicht von Apple notarisiert. macOS zeigt beim ersten Start möglicherweise diese Warnung an:

> Apple kann nicht überprüfen, ob „Status Trio“ frei von Malware ist, die Ihren Mac schädigen oder Ihre Privatsphäre gefährden könnte.

Dies ist eine Gatekeeper-Warnung, die durch die fehlende Developer-ID-Signatur und die fehlende Apple-Notarisierung verursacht wird. Sie bedeutet für sich genommen nicht, dass die App Malware enthält. Umgehen Sie die Warnung nur, wenn die DMG von der offiziellen GitHub-Releases-Seite heruntergeladen wurde und ihre veröffentlichte SHA-256-Prüfsumme übereinstimmt.

Nachdem Sie die App nach `/Applications` kopiert haben, entfernen Sie das Quarantäne-Attribut und öffnen Sie sie:

```bash
xattr -dr com.apple.quarantine "/Applications/Status Trio.app"
open "/Applications/Status Trio.app"
```

Alternativ können Sie die App einmal zu öffnen versuchen, dann zu **Systemeinstellungen → Datenschutz & Sicherheit** gehen und **Trotzdem öffnen** wählen.

Deaktivieren Sie Gatekeeper nicht global. Nachfolgende Sparkle-Updates werden mit dem EdDSA-Signaturschlüssel der App authentifiziert; der Befehl `xattr` ist normalerweise nur für die erste manuelle Installation erforderlich.

## Verwendung

- **Linksklick** auf das Menüleistensymbol oder das Dock-Symbol öffnet das Status-Popover.
- **Rechtsklick** auf eines der beiden Symbole öffnet das native Menü mit Version und Beenden-Aktionen.
- Wählen Sie die Wi-Fi- oder Batteriezeile im Popover, um ihre Seite zu öffnen: Netzwerke in der Nähe und Verbindungsdetails oder Batteriedetails. Die Bluetooth-Zeile listet ihre gekoppelten Geräte direkt darunter auf — tippen Sie eines an, um es zu verbinden oder zu trennen — mit einem „Erweitern“-Schalter, wenn nicht alle hineinpassen.
- Öffnen Sie **Einstellungen**, um zu wählen, wo das Symbol angezeigt wird (Menüleiste, Dock oder beides), und um seine Größe, Farben, die Stärke des äußeren Rings, die angezeigten Elemente des Statusbereichs und ihre Reihenfolge, das Ändern der Lautstärke durch Scrollen, die Sprache, die Suche nach Updates und „Beim Anmelden starten“ zu ändern.
- Öffnen Sie die Anleitung **Dein Symbol kennenlernen** jederzeit erneut über **Einstellungen › App-Symbol › Anleitung öffnen**.
- Aktivieren Sie auf Nachfrage den Namen des aktuellen Wi-Fi-Netzes; macOS fordert für dieses optionale Detail Zugriff auf den Standort an.

## Bekannte Einschränkungen

Zwei Grenzen, die macOS und dieses Projekt bewusst ziehen. Beide sind in [Bekannte Einschränkungen](docs/known-limitations.md) erklärt.

- **Der Wechsel zwischen Netzwerken findet in den Systemeinstellungen statt.** Die Auswahl eines Netzwerks im Popover öffnet den Wi-Fi-Bereich; Status Trio liest oder speichert niemals Wi-Fi-Passwörter, denn macOS bietet keine öffentliche API, um sich mit einem gespeicherten Passwort zu verbinden, und jede Alternative endet damit, dass die App sie aufbewahrt.
- **„Jetzt vollständig laden“ bleibt in macOS.** Wenn optimiertes Batterieladen oder ein Ladelimit das Laden pausiert, meldet das Popover den pausierten Zustand und verweist auf die Batterieeinstellungen; keine öffentliche API erlaubt einer App, das Laden über das Limit hinaus fortzusetzen, und Status Trio schreibt nicht in den SMC und liefert keinen privilegierten Helfer, um das zu tun.

## Sprachen

Status Trio folgt standardmäßig der bevorzugten Sprache von macOS und enthält English, 简体中文, 繁體中文, 日本語, 한국어, Español, Français, Deutsch, Italiano, Português (Brasil), Русский und العربية.

## Datenschutz

Status Trio liest den Status über öffentliche macOS-Frameworks. Die App verwendet keine App-Sandbox und benötigt keine Netzwerk-Berechtigung; Telemetrie oder Analysen sind nicht enthalten. Sie liest und speichert keine Wi-Fi-Passwörter und fordert niemals Zugriff auf den Schlüsselbund an. Der Standortzugriff ist optional und wird nur angefordert, wenn Sie den aktuellen Wi-Fi-Netzwerknamen anzeigen oder Wi-Fi-Details öffnen möchten. Der Bluetooth-Zugriff wird nur angefordert, wenn der Bluetooth-Bereich angezeigt wird, und dient dazu, den Verbindungsstatus gekoppelter Geräte anzuzeigen.

## Entwicklung

Führen Sie die Testsuite aus:

```bash
swift test
```

Führen Sie einen gezielten XCTest-Filter über das Hilfsskript aus:

```bash
bash scripts/test.sh BatteryMonitorTests
```

Um eine Worktree-App neben der Hauptinstallation zu bauen:

```bash
bash scripts/build-worktree.sh release
```

Das Hilfsskript leitet eine Entwicklungs-Bundle-ID und einen Anzeigenamen aus dem aktuellen Branch ab. Beide Werte können überschrieben werden:

```bash
BUNDLE_ID=com.lingsmbp.StatusTrio.dev.settings-redesign \
APP_NAME="Status Trio (Settings Redesign)" \
bash scripts/build-worktree.sh release
```

Die Sperre für einzelne Instanzen richtet sich nach der Bundle-ID, sodass Builds mit unterschiedlichen IDs gleichzeitig laufen können.

## Technische Basis

- Swift 6
- SwiftUI + AppKit
- macOS 15+
- `LSUIElement`-Menüleisten-Accessoire, das zu einer regulären Aktivierungsrichtlinie wechselt, während das Dock-Symbol angezeigt wird
- Sparkle für die Suche nach Updates

## Dokumentation

- [Bekannte Einschränkungen](docs/known-limitations.md)
- [Automatisierte GitHub-Actions-Releases](docs/github-actions-release.md)
- [Status Trio Design-Spezifikation](docs/superpowers/specs/2026-09-12-status-trio-design.md)
- [Menüleistensymbol als SVG](status-menubar.svg)
- [Datengetriebene Symbol-Demo](status-menubar-demo.html)

## Lizenz

Copyright 2026 lingyired.

Lizenziert unter der Apache License, Version 2.0. Siehe [LICENSE](LICENSE) und [NOTICE](NOTICE).

## Autor

Erstellt und gepflegt von [lingyired](https://github.com/lingyired).<br>
Website: [https://statustrio.lingai.net/](https://statustrio.lingai.net/)

## Star History

<a href="https://www.star-history.com/?repos=lingyired%2Fstatus-trio&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
 </picture>
</a>
