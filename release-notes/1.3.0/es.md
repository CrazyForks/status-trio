# Versión %VERSION% (compilación %BUILD%)

## Liquid Glass nativo en macOS 26
- El panel emergente ahora usa el material Liquid Glass de macOS 26 y combina con los menús del sistema; ajustes como Reducir transparencia siguen aplicándose.
- macOS 15 a 25 conservan la apariencia que ya tenían, y la versión mínima del sistema no cambia: nadie tiene que actualizar macOS para seguir usando Status Trio.

## Bluetooth funciona mejor
- El panel de estado ahora lista tus dispositivos emparejados enseguida: toca uno para conectarlo y tócalo de nuevo para desconectarlo; desconectar un teclado o un ratón pide confirmación primero, en la propia fila.
- Arrastra los dispositivos en Ajustes para reordenarlos; los dispositivos conectados aparecen siempre primero.
- Los niveles de batería Bluetooth ahora se muestran de forma predeterminada, sin ningún interruptor que activar.

## El cambio de Wi-Fi se queda en el sistema
- La app ya no se conecta a redes por ti: elegir una red abre el panel de Wi-Fi de Ajustes del Sistema, donde haces el cambio tú.
- Status Trio ya no lee ni guarda contraseñas de Wi-Fi.
- Una contraseña guardada en una versión anterior puede seguir en tu llavero, pero ya no se usa.
- Ver tus redes, los detalles de señal y el interruptor de Wi-Fi funcionan como antes.

## Consume menos energía
- Mucho menos trabajo en segundo plano: Bluetooth ya no sondea los dispositivos con un temporizador, la búsqueda de Wi-Fi se detiene cuando dejas la página y la actualización de respaldo se ralentizó de cada 5 segundos a cada 15.
- Las actualizaciones siguen llegando en cuanto el sistema informa de un cambio, y tu ajuste del intervalo de actualización no cambia.

## Correcciones y mejoras
- Al hacer clic en el icono de la barra de menús, el panel de estado ahora se abre aunque otra app esté en pantalla completa.
- Las lecturas de energía en los detalles de la batería son más precisas: «Consumo del sistema (estimado)» con corriente, «Descarga de batería (estimada)» con batería.
- Un permiso de ubicación denegado para Wi-Fi puede volver a solicitarse en lugar de quedarse atascado en nombres de red no disponibles.
- Con «Reducir movimiento» activado en el sistema, la interfaz de Ajustes ya no reproduce animaciones de transición.

## Agradecimientos
- Gracias a @hhh2210 por sus contribuciones de código a esta versión.
