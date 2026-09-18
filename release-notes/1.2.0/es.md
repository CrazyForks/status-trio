# Versión %VERSION% (compilación %BUILD%)

## Novedades destacadas: audio por Bluetooth
- La fila Bluetooth del panel emergente ahora muestra el estado en vivo: los nombres de los dispositivos conectados y, en los AirPods, la batería del izquierdo, el derecho y el estuche. Los demás dispositivos solo muestran su nombre.
- Mientras se reproduce audio por Bluetooth, el icono de red central puede cambiar al glifo del dispositivo correspondiente (AirPods, auriculares, altavoces, etc.) y mostrarse en azul, con los puntos o el arco de volumen también en azul, para identificar de un vistazo la salida activa.
- Nueva página «Ajustes > Bluetooth»: interruptores para reemplazar el icono de red, usar volumen Bluetooth en azul, dar prioridad a los errores de red y mostrar los niveles de batería Bluetooth, además de un tamaño de icono Bluetooth del 100 % al 180 %.
- Se corrigió que un dispositivo renombrado en Ajustes del Sistema siguiera mostrando su nombre anterior.
- Se corrigió que los niveles de batería Bluetooth se quedaran en «No disponible» al alternar entre el resumen y la página del dispositivo.

## Detalles de la batería
- Al tocar la fila de batería del panel emergente se abre una página dedicada con la potencia nominal del adaptador, el tiempo restante, el modo de bajo consumo, el voltaje, la corriente, la hora de muestreo y el número de ciclos.
- Nueva estimación de la potencia neta de la batería: al cargar se etiqueta en verde como «Cargando (estimación)» y al descargar como «Descargando (estimación)».
- Estos valores son estimaciones con el mejor esfuerzo posible, no el consumo total del Mac. Tras cambiar la fuente de alimentación, macOS puede tardar hasta un minuto en informar valores nuevos; durante ese periodo se muestra «Muestreando» en lugar de «No disponible».

## Resumen de Wi-Fi
- Cuando el Wi-Fi está conectado, el panel emergente usa el nombre de la red (SSID) como título y muestra debajo la banda y la intensidad de la señal, por ejemplo 5 GHz / -52 dBm.
- Las mediciones que faltan se omiten en lugar de mostrarse como 0; Ethernet, sin conexión y otras rutas que no son Wi-Fi no las muestran.

## Conoce tu icono
- Una instalación nueva abre la guía «Conoce tu icono» en el primer inicio. Selecciona el arco de la batería, el glifo de red central o el indicador de volumen para leer qué significa cada uno; la explicación del volumen sigue tu ajuste actual de puntos o arco.
- La guía incluye una galería de combinaciones de estados habituales: cargando, batería baja, Ethernet, sin Internet y silenciado, punto de acceso con modo de bajo consumo, Wi-Fi débil al 25 % de volumen, Wi-Fi desactivado, auriculares Bluetooth, AirPods y Wi-Fi con volumen azul.
- Actualizar a esta versión, reiniciar y las instalaciones existentes no la abren automáticamente. Puedes reabrirla cuando quieras desde «Ajustes», «Icono de la app», «Abrir guía».

## Volumen
- Nuevo interruptor «Desplazamiento natural»: cuando está activado, desplazarse hacia arriba con el ratón o el trackpad sube el volumen, sin importar la preferencia de desplazamiento natural del sistema; cuando está desactivado, el volumen sigue la dirección de desplazamiento del sistema.
- Nueva opción «Área de ajuste»: desplazarse en cualquier parte del panel o solo sobre el control de volumen.
- Si al activarlo el desplazamiento hacia arriba sigue bajando el volumen, una utilidad de desplazamiento como MOS, Scroll Reverser o LinearMouse está invirtiendo los eventos; añade Status Trio a su lista de excepciones o de omisiones.

## Ajustes y apariencia
- El estilo de volumen (puntos o arco), la colocación del icono y el grosor del trazo del anillo ahora son selectores visuales: la selección se marca con un anillo concéntrico y se previsualiza en la propia tarjeta.
- Nuevo ajuste «Grosor del trazo del anillo»: fino, estándar o grueso, aplicado al anillo exterior de la batería, al arco de volumen y a los puntos de volumen para un resultado más nítido en pantallas Retina.
- Elegir «Solo barra de menús» ahora avisa de que el icono del Dock desaparece al cerrar la ventana de ajustes.
- Los controles de audio y el pie del panel emergente son más compactos: el interruptor de silencio pasa a la cabecera, se eliminan los iconos de altavoz duplicados, el nombre del dispositivo de salida pasa a ser un subtítulo y se añade una entrada «Más acciones».
- Las filas del panel emergente comparten ahora un mismo tamaño de icono y espaciado; el icono predeterminado de la barra de menús es de 24 pt y la escala del símbolo de Wi-Fi es del 160 % de forma predeterminada.

## Correcciones
- Cambiar una opción de icono ahora redibuja de inmediato los iconos de la barra de menús y del Dock, sin retardo.
- La vista previa de la barra de menús en Ajustes permanece fijada en la parte superior de la página en lugar de desplazarse con las opciones.
- Al hacer clic en una red Wi-Fi conocida se abren directamente los ajustes de Wi-Fi del sistema.
- El símbolo de Wi-Fi está centrado en el icono de estado (issue #30).

## Agradecimientos
- Gracias a @ReffWu y @hhh2210 por sus contribuciones de código a esta versión.
