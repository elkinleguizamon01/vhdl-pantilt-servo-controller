# Sistema de control pan/tilt en VHDL

Sistema digital para controlar una plataforma pan/tilt (dos servomotores) mediante comandos ASCII recibidos por UART, con retroalimentación visual en displays de 7 segmentos y LEDs. Implementado en VHDL para FPGA (Intel/Altera, proyecto Quartus).

## Estructura del proyecto

```
ver3/
├── command_parser.vhd     # Interpreta comandos ASCII y produce angulos objetivo
├── uart_rx.vhd             # Receptor UART: bits seriales -> bytes paralelos
├── servo_pwm.vhd            # Genera la senal PWM para cada servomotor
├── display_ctrl.vhd         # Muestra el angulo actual en 4 displays de 7 segmentos
├── pwmservo.vhd              # Entidad top-level: instancia y conecta todo lo anterior
├── pwmservo.qsf                # Configuracion del proyecto Quartus (pines, dispositivo)
├── pwmservo.qdf                # Metadatos generados por Quartus
└── pwmservo.wqs                 # Configuracion de simulacion / waveform
```

## Como funciona el sistema

Un usuario envia comandos de texto por un puerto serial (por ejemplo `P090\r` o `S\r`). Esos bytes viajan a traves de la cadena de modulos hasta convertirse en movimiento fisico de los servos y una lectura visible en los displays:

```
UART_RX --> uart_rx --> command_parser --> servo_pwm (pan)  --> SERVO_PAN
                              |        \--> servo_pwm (tilt) --> SERVO_TILT
                              \--------> display_ctrl --> HEX0..HEX3
```

`pwmservo.vhd` es la entidad de nivel superior: no contiene logica propia, solo instancia los cuatro modulos anteriores y los conecta (arquitectura `structural`).

## Protocolo de comandos

| Comando | Formato | Efecto |
|---|---|---|
| Pan | `Pddd<CR/LF>` | Mueve el pan al angulo `ddd` (ej. `P090`) |
| Tilt | `Tddd<CR/LF>` | Mueve el tilt al angulo `ddd` (ej. `T075`) |
| Home | `H<CR/LF>` | Vuelve pan y tilt a su posicion inicial |
| Sweep | `S<CR/LF>` | Activa el barrido automatico del pan |
| Stop | `X<CR/LF>` | Congela el movimiento y bloquea nuevos comandos |
| Rearm | `R<CR/LF>` | Desbloquea el sistema tras un `Stop` |

Acepta mayusculas o minusculas para la letra de comando, y `CR` (`\r`) o `LF` (`\n`) como terminador.

## Modulos

### `command_parser.vhd`
Maquina de estados finita que interpreta byte a byte el protocolo anterior. Valida cada angulo contra los limites mecanicos configurados por generics, maneja el modo de barrido automatico (`sweep`) y el bloqueo de seguridad `stop`/`rearm`. Expone `cmd_valid`/`cmd_invalid` como retroalimentacion de si el ultimo comando fue aceptado.

### `uart_rx.vhd`
Receptor serial UART generico. Sincroniza la señal de entrada con un doble flip-flop (evita metaestabilidad), detecta el bit de inicio, muestrea los bits de datos en el centro de cada periodo de bit, y publica el byte completo junto con un pulso `data_valid`.

### `servo_pwm.vhd`
Convierte un angulo (0-180) en una señal PWM apta para un servomotor de hobby (periodo ~20 ms, pulso entre ~1 y ~2 ms). El ancho de pulso se recalcula con un pequeño multiplicador serial (una suma por ciclo de reloj) cada vez que cambia el angulo de entrada.

### `display_ctrl.vhd`
Logica combinacional que separa un angulo en centena/decena/unidad y las codifica para 3 displays de 7 segmentos, mas un cuarto display que indica si se esta mostrando el eje de pan o de tilt.

### `pwmservo.vhd`
Entidad top-level sintetizable en la FPGA. Mapea los generics de configuracion hacia cada submodulo, resuelve la polaridad del boton de reset, selecciona (via switch) que angulo se muestra en los displays, e instancia:
- `UART_RECEIVER` (`uart_rx`)
- `COMMAND_DECODER` (`command_parser`)
- `PAN_SERVO` y `TILT_SERVO` (dos instancias de `servo_pwm`)
- `DISPLAY_CONTROLLER` (`display_ctrl`)

## Parametros de configuracion (generics)

| Generic | Descripcion | Valor por defecto |
|---|---|---|
| `PAN_MIN_ANGLE` / `PAN_MAX_ANGLE` | Rango mecanico del pan | 0 - 180 |
| `TILT_MIN_ANGLE` / `TILT_MAX_ANGLE` | Rango mecanico del tilt | 50 - 130 |
| `PAN_INITIAL_ANGLE` / `TILT_INITIAL_ANGLE` | Posicion tras reset o `Home` | 90 / 90 |
| `CLKS_PER_BIT` | Ciclos de reloj por bit UART (define el baudrate) | 10417 (~4800 baudios a 50 MHz) |
| `PWM_PERIOD_CYCLES` | Ciclos de reloj por periodo PWM (define ~20 ms) | 1,000,000 |
| `SWEEP_STEP_CYCLES` | Ciclos entre cada paso de 1 grado en modo sweep | 972,222 |

Todos se definen una sola vez en `pwmservo.vhd` y se propagan hacia los submodulos correspondientes.

## Compilacion

El proyecto esta pensado para **Intel Quartus Prime**:

1. Abrir `pwmservo.qsf` en Quartus (o crear un proyecto nuevo con ese archivo de configuracion).
2. Verificar que los 5 archivos `.vhd` esten agregados al proyecto.
3. Compilar (`Processing > Start Compilation`).
4. Programar la FPGA con el archivo `.sof` generado.
