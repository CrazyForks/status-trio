<p align="center">
  <img src="screenshots/status-trio-dock-state-strip-symmetric.png" width="1000" alt="Ocho estados del icono de Status Trio en el Dock con fondos oscuros y claros dispuestos de forma simétrica, incluidos estados de Wi-Fi, audio por Bluetooth, batería, puntos y arco">
</p>

<p align="center">
  <img src="Support/AppIcon.png" width="112" alt="Icono de la app Status Trio">
</p>

<h1 align="center">Status Trio</h1>

<p align="center">
  <a href="https://trendshift.io/repositories/234371?utm_source=trendshift-badge&utm_medium=badge&utm_campaign=badge-trendshift-234371" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/234371/daily?language=Swift" alt="lingyired/status-trio | Trendshift" width="250" height="55"/></a>
</p>

<p align="center"><strong>Tres señales del sistema. Un solo icono de estado nativo de macOS: en la barra de menús o en el Dock.</strong></p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/badge/Download%20for%20macOS-Universal%20%C2%B7%20macOS%2015%2B-000000?logo=apple&logoColor=white&style=for-the-badge" alt="Descargar para macOS — versión universal, macOS 15 o posterior"></a>
</p>

<p align="center">
  ¿Quieres verlo en acción primero? Abre <a href="https://statustrio.lingai.net/">statustrio.lingai.net</a> para simular todos los estados del icono en el navegador.
</p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/github/v/release/lingyired/status-trio?label=release&color=blue" alt="Última versión"></a>
  <a href="https://github.com/lingyired/status-trio/actions/workflows/release.yml"><img src="https://github.com/lingyired/status-trio/actions/workflows/release.yml/badge.svg" alt="Estado del flujo de trabajo Build and Release macOS"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/lingyired/status-trio?label=license" alt="Licencia: Apache-2.0"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B%20supported-blue?logo=apple&logoColor=white" alt="Compatible con macOS 15 o posterior">
  <img src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%7C%20Intel-lightgrey" alt="Binario universal para Apple Silicon e Intel">
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-Hans.md">简体中文</a> ·
  <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <strong>Español</strong> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt-BR.md">Português (Brasil)</a> ·
  <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="screenshots/menu-bar-wifi.jpg" width="1000" alt="Icono de Status Trio en la barra de menús mostrando el glifo de Wi-Fi mientras hay conexión Wi-Fi, con su panel emergente de estado abierto">
</p>

Status Trio es una app de estado nativa de macOS que combina Wi-Fi, batería y volumen en un único icono compacto y configurable, que se muestra en la barra de menús, en el Dock o en ambos. Su panel emergente va más allá del icono: un panel de Wi-Fi para unirse a redes y consultar los detalles del enlace, un panel de Bluetooth para los dispositivos emparejados, una página de Detalles de la batería y los dispositivos de audio que están reproduciendo. Está inspirada en el icono combinado de la barra de estado del iPhone Duo para Wi-Fi, batería y datos móviles, adaptado al Mac con el volumen en lugar de los datos móviles.

> Status Trio es un proyecto independiente y no está afiliado a Apple.

## Aspectos destacados

- **Un icono, tres señales** — la batería, el Wi-Fi y el volumen comparten un solo icono en la barra de menús, en el Dock o en ambos, y un dispositivo Bluetooth que está reproduciendo puede ocupar la posición central con su propio símbolo.
- **Bluetooth** — el indicador de volumen se vuelve azul mientras se reproduce. El panel muestra los dispositivos conectados y emparejados junto con la batería de los AirPods, y permanece desactivado hasta que lo actives.
- **Batería** — porcentaje, carga o conexión a la corriente, tiempo para la carga completa y un color cuando está baja. Abre la fila para ver la potencia del adaptador, el voltaje, la corriente, el número de ciclos y el modo de bajo consumo.
- **Wi-Fi** — la red a la que estás conectado y la intensidad de la señal. Ábrelo para ver las redes cercanas, unirte a una o desactivar el Wi-Fi.
- **Volumen** — nivel, silencio y dispositivo de salida, dibujado como puntos o como un arco. Desplázate por todo el panel o solo por el control, y elige en qué dirección sube el volumen.
- **Hazlo tuyo** — tamaño del icono, escala de los símbolos, grosor del anillo, colores de estado y qué secciones muestra el panel emergente, en el orden que quieras.
- **Barra de menús, Dock o ambos** — y el icono del Dock puede seguir el estilo del sistema o mantenerse oscuro o claro.
- **Nativo en macOS** — el clic izquierdo abre el panel emergente, el clic derecho abre el menú, y una guía de primer inicio explica cada parte del icono. Ethernet, un punto de acceso personal o Compartir Internet pueden mantener el glifo de Wi-Fi si lo prefieres.
- **Siempre al día** — el estado proviene de eventos del sistema, con un sondeo lento como respaldo, y Sparkle actualiza la app mediante un canal firmado.
- **También incluye** — doce idiomas y la opción de abrir al iniciar sesión.

## Audio por Bluetooth

Mientras se reproduce audio por Bluetooth, dos interruptores en **Ajustes › Bluetooth** permiten que el glifo central pase a ser el símbolo propio de ese dispositivo —los AirPods, los auriculares, los altavoces y otros dispositivos aportan el suyo— y que los puntos o el arco del volumen se vuelvan azules. Ambos están desactivados de forma predeterminada. **Dar prioridad a los errores de red**, activado de forma predeterminada, mantiene el icono de red mientras la propia conexión tiene problemas:

<p align="center">
  <img src="screenshots/menu-bar-airpods.jpg" width="1000" alt="Icono de Status Trio en la barra de menús mostrando el glifo de AirPods mientras hay AirPods conectados, con su panel emergente de estado abierto">
</p>

La fila de Bluetooth del panel emergente informa del estado en vivo: los nombres de los dispositivos conectados y, en el caso de los AirPods, la batería del izquierdo, del derecho y del estuche. El panel de Bluetooth muestra los dispositivos emparejados y su estado de conexión; está desactivado de forma predeterminada, se activa en **Ajustes › Panel de estado** y solicita permiso de Bluetooth la primera vez que se usa. **Ajustes › Bluetooth** también controla si se leen los niveles de batería y ajusta la escala del icono de Bluetooth del 100 % al 180 %.

## Icono del Dock

El mismo icono en vivo puede residir en el Dock en lugar de la barra de menús, o en ambos lugares a la vez:

<p align="center">
  <img src="screenshots/status-trio-dock-dark-1440x810.jpg" width="880" alt="Icono en vivo de Status Trio en el Dock con apariencia oscura">
  <br>
  <sub>Icono del Dock en apariencia oscura</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-1440x810.jpg" width="880" alt="Icono en vivo de Status Trio en el Dock con apariencia clara">
  <br>
  <sub>Icono del Dock en apariencia clara</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-bt-1440x810.jpg" width="880" alt="Status Trio en el Dock con el panel de Bluetooth visible, apariencia clara">
  <br>
  <sub>Vista previa del panel de Bluetooth</sub>
</p>

El icono del Dock dibuja el mismo icono combinado que la barra de menús, así que, con la sustitución por audio Bluetooth activada, el glifo del dispositivo también ocupa el centro ahí. Su fondo puede seguir el estilo de iconos del sistema o fijarse a un tono concreto:

<p align="center">
  <img src="screenshots/status-trio-dock-icons.png" width="880" alt="Icono de Status Trio en el Dock con fondos oscuro, claro y transparente, en dos filas: el estado de Wi-Fi y el audio Bluetooth sustituyendo al icono de Wi-Fi con puntos de volumen azules">
</p>

## Estados del icono

Todos los estados que puede mostrar el icono combinado, dibujados por el propio renderizador de la app —los indicadores de batería arriba, el Wi-Fi (o el dispositivo de audio Bluetooth que puede sustituirlo, cuando esa opción está activada) en el centro, y los puntos o el arco del volumen abajo, que se vuelven azules mientras un dispositivo Bluetooth está reproduciendo—:

<p align="center">
  <img src="screenshots/status-trio-icon-states.png" width="880" alt="Estados del icono de Status Trio: carga, conectado a la corriente, porcentaje, batería baja y Modo de bajo consumo arriba; señal de Wi-Fi, punto de acceso personal, temporal, compartida y por cable en el centro; audio Bluetooth sustituyendo al icono de Wi-Fi, Wi-Fi conservado durante un error de red, y puntos de volumen azules y arco debajo de eso; estilos de puntos de volumen y arco para cada nivel abajo del todo">
</p>

Los mismos estados representados para una barra de menús oscura:

<p align="center">
  <img src="screenshots/status-trio-icon-states-dark.png" width="880" alt="Los mismos estados del icono de Status Trio en apariencia oscura: glifos blancos sobre fondos oscuros, carga en verde, batería baja en rojo y acentos amarillos del modo de bajo consumo, además del azul más brillante que la app usa para el audio Bluetooth en una barra de menús oscura">
</p>

## Requisitos

- macOS 15 o posterior para ejecutar la app
- Cadena de herramientas de Swift 6 con el SDK de macOS 26 (Xcode 26 o posterior) para compilarla. Compilar contra un
  SDK anterior produce de forma silenciosa la apariencia del panel emergente previa a Tahoe, por lo que
  `scripts/build-app.sh` falla cuando el SDK es anterior a 26.

## Ejecutar desde el código fuente

```bash
git clone https://github.com/lingyired/status-trio.git
cd status-trio
swift run StatusTrio
```

## Compilar una app local

Compila un paquete de app firmado de forma ad-hoc y ejecútalo:

```bash
bash scripts/build-app.sh release
```

El paquete se crea en `dist/StatusTrio.app`. Para compilar sin cerrar ni abrir una instancia existente, ejecuta:

```bash
bash scripts/build-app.sh release no-open
```

El paquete firmado de forma ad-hoc está pensado para uso personal local. Gatekeeper puede rechazarlo si el paquete se transfiere con metadatos de cuarentena.

## Instalar una versión de GitHub

Descarga el último `StatusTrio-*.dmg` desde la [página de versiones de GitHub](https://github.com/lingyired/status-trio/releases), ábrelo y copia `Status Trio.app` en `/Applications`.

La versión pública actual está firmada de forma ad-hoc, pero Apple no la ha notarizado. macOS puede mostrar esta advertencia en el primer inicio:

> Apple no puede verificar que “Status Trio” esté libre de software malicioso que pueda dañar tu Mac o poner en riesgo tu privacidad.

Es una advertencia de Gatekeeper causada por la falta de la firma Developer ID y de la notarización de Apple. No significa por sí sola que la app contenga software malicioso. Omite la advertencia solo cuando el DMG se haya descargado de la página oficial de versiones de GitHub y su suma de verificación SHA-256 publicada coincida.

Después de copiar la app en `/Applications`, elimina el atributo de cuarentena y ábrela:

```bash
xattr -dr com.apple.quarantine "/Applications/Status Trio.app"
open "/Applications/Status Trio.app"
```

Como alternativa, intenta abrir la app una vez y luego ve a **Ajustes del Sistema → Privacidad y seguridad** y elige **Abrir de todos modos**.

No desactives Gatekeeper de forma global. Las actualizaciones posteriores de Sparkle se autentican con la clave de firma EdDSA de la app; el comando `xattr` normalmente solo es necesario para la primera instalación manual.

## Uso

- **Clic izquierdo** en el icono de la barra de menús o en el icono del Dock para abrir el panel emergente de estado.
- **Clic derecho** en cualquiera de los dos iconos para abrir el menú nativo, que incluye la versión y la opción de salir.
- Selecciona una fila del panel emergente para abrir su página: los detalles de Wi-Fi con las redes cercanas, los dispositivos Bluetooth emparejados y los Detalles de la batería.
- Abre **Ajustes** para elegir dónde se muestra el icono (barra de menús, Dock o ambos) y para cambiar su tamaño, los colores, el grosor del anillo, las secciones del panel y su orden, el comportamiento de ajuste con el desplazamiento, el idioma, la búsqueda de actualizaciones y abrir al iniciar sesión.
- Vuelve a abrir la guía **Conoce tu icono** en cualquier momento desde **Ajustes › Icono de la app › Abrir guía**.
- Activa el nombre de la red Wi-Fi actual cuando se te solicite; macOS pide acceso a la ubicación para este detalle opcional.

## Idiomas

Status Trio sigue el idioma preferido de macOS de forma predeterminada e incluye English, 简体中文, 繁體中文, 日本語, 한국어, Español, Français, Deutsch, Italiano, Português (Brasil), Русский y العربية.

## Privacidad

Status Trio lee el estado mediante frameworks públicos de macOS. No usa App Sandbox ni requiere un permiso de red, y no incluye telemetría ni análisis. El acceso a la ubicación es opcional y solo se solicita cuando eliges mostrar el nombre de la red Wi-Fi actual o abrir los detalles de Wi-Fi. El acceso a Bluetooth solo se solicita cuando abres los detalles de Bluetooth, y existe para mostrar el estado de conexión de los dispositivos emparejados.

## Desarrollo

Ejecuta la suite de pruebas:

```bash
swift test
```

Ejecuta un filtro de XCTest concreto mediante el script auxiliar:

```bash
bash scripts/test.sh BatteryMonitorTests
```

Para compilar una app de worktree junto a la instalación principal:

```bash
bash scripts/build-worktree.sh release
```

El script auxiliar deriva un identificador de paquete y un nombre visible de desarrollo a partir de la rama actual. Ambos valores se pueden sobrescribir:

```bash
BUNDLE_ID=com.lingsmbp.StatusTrio.dev.settings-redesign \
APP_NAME="Status Trio (Settings Redesign)" \
bash scripts/build-worktree.sh release
```

El bloqueo de instancia única está limitado por el identificador de paquete, por lo que las compilaciones con identificadores distintos pueden ejecutarse al mismo tiempo.

## Base técnica

- Swift 6
- SwiftUI + AppKit
- macOS 15+
- Accesorio de barra de menús `LSUIElement` que cambia a una política de activación normal mientras se muestra el icono del Dock
- Sparkle para buscar actualizaciones

## Documentación

- [Versiones automatizadas con GitHub Actions](docs/github-actions-release.md)
- [Especificación de diseño de Status Trio](docs/superpowers/specs/2026-09-12-status-trio-design.md)
- [SVG del icono de la barra de menús](status-menubar.svg)
- [Demostración del icono basada en datos](status-menubar-demo.html)

## Licencia

Copyright 2026 lingyired.

Con licencia Apache License, Version 2.0. Consulta [LICENSE](LICENSE) y [NOTICE](NOTICE).

## Autor

Creado y mantenido por [lingyired](https://github.com/lingyired).<br>
Sitio web: [https://statustrio.lingai.net/](https://statustrio.lingai.net/)

## Star History

<a href="https://www.star-history.com/?repos=lingyired%2Fstatus-trio&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
 </picture>
</a>
