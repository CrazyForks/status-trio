# Versión %VERSION% (compilación %BUILD%)

## Liquid Glass nativo en macOS 26 y posteriores
- El panel emergente ahora usa el material Liquid Glass del propio sistema en lugar del aspecto esmerilado heredado de versiones anteriores de macOS, por lo que combina con los menús y paneles que lo rodean.
- Esta es la apariencia del sistema, no un estilo propio de la app: sigue los ajustes de tu sistema.
- macOS 15 a 25 conservan la apariencia que ya tenían; la versión mínima del sistema no cambia, así que nadie tiene que actualizar macOS para seguir usando Status Trio.

## El panel se abre sobre apps en pantalla completa
- Al hacer clic en el icono de la barra de menús, el panel de estado ahora se abre aunque otra app esté en pantalla completa. Antes se abría detrás de esa app, así que el clic parecía no hacer nada.

## Actualización en segundo plano más económica
- La actualización de respaldo (el temporizador que recoge un cambio que el sistema no envió a la app) ahora se ejecuta cada 15 segundos de forma predeterminada en lugar de cada 5, y macOS puede desplazar ese temporizador para que se active junto con otras tareas. El icono sigue actualizándose en cuanto el sistema informa de un cambio.
- La batería se comprueba en cada ciclo de la actualización de respaldo. El Wi-Fi y el volumen se comprueban con menos frecuencia mientras el panel de estado y la ventana de Ajustes están cerrados, y vuelven a tu intervalo de actualización en cuanto uno de los dos está en pantalla.
- El control deslizante del intervalo de actualización sigue bajando hasta 5 segundos para quien quiera la cadencia anterior.
- La fila del volumen ya no vuelve a dibujar el panel de estado cuando la lectura de volumen no ha cambiado.

## Bluetooth ya no sondea en segundo plano
- El panel de Bluetooth antes leía la lista de dispositivos emparejados cada 15 segundos mientras la app estuviera en ejecución, incluso después de cerrar el panel. Ahora se actualiza cuando un dispositivo se conecta o se desconecta, y solo recurre a una comprobación lenta mientras hay una vista de Bluetooth en pantalla.
- Los dispositivos emparejados y los niveles de batería ahora provienen de un solo informe del sistema en lugar de dos, lo que reduce a la mitad el trabajo de cada actualización.
- Los nombres de los dispositivos siguen viniendo del mismo origen y el comportamiento de permisos no cambia: la app sigue pidiendo Bluetooth solo cuando abres una vista de Bluetooth.

## La búsqueda de Wi-Fi se detiene cuando dejas de mirar
- La página de Wi-Fi antes recorría todos los canales cada cinco segundos aproximadamente mientras estuviera abierta, incluso después de volver al resumen. Ahora escanea cuando abres la página, cuando pulsas Actualizar y cuando cambias el interruptor de Wi-Fi, y conserva el último resultado entre medias.
- Salir de la página de Wi-Fi detiene su bucle de escaneo en lugar de dejarlo en ejecución en segundo plano.
- En los Mac sin interfaz Wi-Fi, por ejemplo un Mac mini o un Mac Studio conectado por Ethernet, la app ya no reconstruye su monitorización de Wi-Fi cada 30 segundos; ahora lo intenta unas cuantas veces y luego espera una reactivación o un cambio de red.
- Nada cambia en la propia lista: las mismas redes, los mismos detalles y el mismo botón de actualización manual.

## El cambio de Wi-Fi se queda en el sistema
- El panel emergente ya no se conecta a una red ni cambia entre ellas. Elegir una red abre el panel de Wi-Fi de Ajustes del Sistema, y la página de Wi-Fi lo indica encima del botón que lo abre.
- Status Trio ya no lee ni guarda contraseñas de Wi-Fi. El comportamiento anterior no se podía hacer fiable: macOS se guarda para sí la contraseña de una red guardada, y una copia almacenada que había quedado obsoleta acababa en conexiones fallidas y peticiones repetidas del llavero, sin forma de decirte que la contraseña era incorrecta.
- Si marcaste **Recordar la contraseña en el llavero** en una versión anterior, ese elemento del llavero sigue ahí y ya no se usa. Puedes eliminarlo en Acceso a Llaveros buscando `com.lingsmbp.StatusTrio.wifi-password`.
- Nada más ha cambiado en la página: las mismas redes, los mismos detalles de señal y enlace, el mismo interruptor de Wi-Fi y el mismo botón que abre Ajustes del Sistema.

## Los niveles de batería Bluetooth vienen activados
- **Mostrar niveles de batería Bluetooth** en **Ajustes › Bluetooth** ahora viene activado por defecto: una vez activado el panel de Bluetooth, un dispositivo conectado informa de su nivel sin tener que activar este interruptor por separado. Desactivarlo sigue deteniendo la lectura.
- La lista de dispositivos Bluetooth ya no muestra **No disponible** en cada fila: un dispositivo que no informa de batería no muestra ningún texto de batería, y un informe que no se puede leer se avisa una vez bajo la lista.

## Dispositivos emparejados en el panel de estado
- **Ajustes › Bluetooth** ahora puede listar los dispositivos emparejados bajo la fila Bluetooth: los primeros siempre están visibles, el resto aparece detrás de un control Expandir, y el máximo lo eliges tú. Los dispositivos conectados aparecen siempre primero.
- Arrastra los dispositivos en Ajustes para definir el orden que se muestra en el panel. Los dispositivos nuevos aparecen al final.

## Conectar o desconectar un dispositivo desde el panel de estado
- Tocar un dispositivo emparejado en la lista de Bluetooth ahora lo conecta, y tocar uno conectado lo desconecta. La fila muestra la solicitud en curso e informa de un fallo en lugar de fingir que funcionó.
- Desconectar un teclado, ratón, trackpad o mando pide confirmación primero, en la propia fila: desconectar el que estás usando te dejaría sin entrada.
