Esta es la pieza que **une todo** lo que hemos visto: es la entidad de nivel superior (top-level) que se sintetiza directamente en la FPGA (por los nombres de puertos —`CLOCK_50`, `KEY0`, `SW0`, `HEX0..3`, `LEDR0`, `LEDR9`— se nota que es para una placa Terasic DE10-Lite o similar). Su arquitectura es `structural`: no tiene lógica propia, **solo instancia otros módulos y los conecta entre sí** — es puro cableado.

### 1. Generics: pasar la configuracion hacia abajo 

Todos los `generic` (ángulos límite, ciclos de PWM, etc.) se declaran aquí arriba y se **reenvían** hacia `command_parser` y `servo_pwm` mediante `generic map`. Esto es clave: si mañana quieres cambiar el rango del tilt, solo tocas un número en este archivo, y se propaga automáticamente a todos los submódulos que lo necesitan — no hay valores duplicados ni hardcodeados en varios lugares.

### 2. Señales internas (el "cableado")

```vhdl
signal rx_data, rx_valid          -- salida de uart_rx, entrada de command_parser
signal pan_angle, tilt_angle      -- salida de command_parser, entrada de servo_pwm y display
signal selected_angle             -- cuál de los dos ángulos se muestra en los displays
signal cmd_valid, cmd_invalid     -- feedback visual en LEDs
```

Estas señales son los "cables" invisibles entre los bloques — no corresponden a pines físicos, solo existen dentro de la FPGA para conectar una entidad con otra.

### 3. Lógica combinacional de nivel superior (fuera de los process)

```
reset_int <= not KEY0;
```

En la DE10-Lite, los botones son activos en bajo (presionado = `'0'`). Como todos los módulos internos esperan `reset = '1'` cuando está activo, aquí se **invierte** la señal una sola vez, y todos los submódulos reciben ya la polaridad correcta.

```
selected_angle <= pan_angle when SW0 = '0' else tilt_angle;
```

Un multiplexor de 1 bit: el switch `SW0` decide si los displays de 7 segmentos muestran el ángulo de pan o el de tilt. Nota que esta señal **no** afecta el movimiento físico de los servos — ambos se mueven siempre en paralelo; `SW0` solo cambia qué número se _ve_ en pantalla (coincide con el mismo `axis` que ya vimos en `display_ctrl`, que usa `SW0` para elegir la etiqueta "P" o "t" en `hex3`).

```
LEDR0 <= cmd_valid;
LEDR9 <= cmd_invalid;
```

Feedback inmediato en hardware: un LED se prende brevemente cuando un comando fue aceptado, otro cuando fue rechazado — el "led_valid"/"led_invalid" que vimos en `command_parser` finalmente llega a un LED físico.

