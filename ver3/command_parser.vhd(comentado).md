El sistema es una maquina de estados finita (FSM)  la cual interpreta comandos ASCII  recibidos byte a byte ( provenientes de un UART )  y genera el control del PanTilt que se mueve por medio de dos servomotores.

![[ver3/command_parser_fsm.png]]
### 1. Proposito General

El sistema recibe comandos con el siguiente formato 

```
P090  <- MOVER PAN A 90°
T075  <- MOVER TILT A 75
H     <- HOME  (POSICION INICIAL)
S     <- INICIAR BARRIDO 
X     <- STOP 
R     <- REARMAR TRAS UN STOP
```


### 2. Generics ( parametros configurables)

```vhdl
PAN_INITIAL_ANGLE, PAN_MIN_ANGLE, PAN_MAX_ANGLE, TILT_INITIAL_ANGLE, TILT_MIN_ANGLE, TILT_MAX_ANGLE, SWEEP_STEP_CYCLES

```

Permiten reusar el mismo diseño con distintos rangos mecánicos sin tocar el codigo `SWEEP_STEP_CYCLES` define cuantos ciclos de reloj esperar entre cada paso de 1° en modo sweep (barrido)

### 3. Tipos y señales de estado 

* `state_type` : los 5 estados del parser (Esperando comando, diggito 1, 2, 3 o Enter).
* `cmd_type_t` : que comando se esta procesando actualmente (se "recuerda" mientras se leen los digitos)
* `pan_mode_t` : si el pan esta en modo manual o en barrido -esto es necesario ya que el pan tiene 2 modos en los cuales puede estar  los cuales son, angulo `pan_reg` o el barrido `sweep_angle` ( dato curioso se puede hacer que el pan este en barrido mientras el til se puede mandar codigo )
### 4. El multiplexor de salida 

```
pan_angle <= sweep_angle when pan_mode = SWEEP_MODE else pan_reg;
```

Aqui esta la clave del diseño: pan_reg conserva el ultimo angulo manual. y el barrido es independiente. Cuando cambias de modo no se pierde el valor del otro - simplemente se ignora hasta que vuelva a ese modo.


### 5. Logica de barrido ( se mueve de manera independienta al UART)


```vhdl
if pan_mode = SWEEP_MODE and stopped = '0' then 
	if sweep_timer = SWEEP_STEP_CYCLES - 1 then ...
```

Esto no esta dentro del `if rx_valid = '1'` , porque el barrido debe avanzar continuamente con el reloj, no solo cuando llega un byte. Es un contador ( `sweep_timer`) que actua divisor de frecuencia: cada `SWEEP_STEP_CYCLES` ciclos, incrementa o decrementa `sweep_angle` en 1 y al llegar a los limites (`PAN_MIN_ANGLE / PAN_MAX_ANGLE)` invierte la direccion (` sweep_dir ` ) 

la condicion `stopped = '0'` es importante: si se emitio `STOP`, el barrido se congela en su posicion actual, no sigue moviendose.

### 6. El parser de protocolo (dentro de if rx_valid ='1')

`WAIT_CMD`

Decodifica el primer byte. Nota que acepta mayuscula y minuscula ( x"50" = 'P', x"70"= 'p'), gracias a comparar contra ambos codigos ASCII. 
Comandos con parametro (PAN /TILT) van a `WAIT_DIGIT1`; comandos sin parametro (`HOME /SWEEP / STOP / REARM `) Saltan directo a `WAIT_ENTER`.

`WAIT_DIGITAL1/2/3`

Solo aceptan ASCCI '0'-'9' (x"30"-x"39"). Cualquier otro byte es un error de protocolo -> invalida el comando y regresa a `WAIT_CMD` ( Se genera una recuperacion de errores por resincronizacion).

`WAIT_ENTER`

Solo acepta CR (x"0D") O LF( x"0A") para confirmar el comando.  Aqui es donde realmente se ejecuta la accion, no al recibir los digitos 


### 7. Conversion de digitos ASCII a numero (las variables)

``` vhdl
variable digit1_value : integer range 0 to 900;
```

En vez de hacer digit * 100, el codigo usa un `case` explicito. Esto es una decision de estilo (a veces por convencion de equipo, a veces por convencion de equipos, a veces para evitar inferir un miltiplicador en hardware si la herramienta de sintesis no optimiza bien una multiplicacion por contaste pequeña). Funcionalmente es identica a `digit1*100, digit2*100, digit3,` sumados en `angle_value`. Luego se valida contra el rango (`PAN_MIN/MAX` o `TILT_MIN/MAX`) antes de aceptar el valor -- proteccion contra comandos como P999 que dañarian el servo.

### 8. Mecanismo STOP / REARM (seguridad)

``` vhdl
elsif stopped = '1' then 
	led_valid <= '0';
	led_invalid <= '1';

```

Una vez que `stopped = '1'`, todos los comandos (excepto REARM) se rechazan como invalidos. Esto es una capa de seguridad: si algo se detiene de emergencia, el sistema no reacciona a nada hasta que se rearme explicitamente. REARM se comprueba antes que este chequeo, por eso puede "romper" el bloqueo

### 9. Señales de estado `led_valid/ led_invalid`

Actuan como flags de un solo ciclo (pulso) que inican si el ultimo comando fue aceptado o rechazado -- tipicamente para encender un LED indicador o para que otro modulo sepa si debe hacer algo. 


### 10. Codigo comentado 

``` vhdl
--------------------------------------------------------------------------------
-- command_parser.vhd
--
-- Parser de comandos ASCII para control de un sistema pan/tilt (dos servos).
--
-- Protocolo esperado (bytes tipo UART, uno por ciclo con rx_valid='1'):
--   P<ddd><CR/LF>  -> mover PAN al angulo ddd (ej: P090)
--   T<ddd><CR/LF>  -> mover TILT al angulo ddd (ej: T075)
--   H<CR/LF>       -> HOME: pan y tilt a su posicion inicial
--   S<CR/LF>       -> SWEEP: pan entra en modo de barrido automatico
--   X<CR/LF>       -> STOP: congela todo movimiento y bloquea nuevos comandos
--   R<CR/LF>       -> REARM: desbloquea el sistema tras un STOP
--
-- Acepta mayusculas y minusculas para la letra de comando.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity command_parser is
    generic (
        -- Parametros mecanicos del PAN (servo horizontal)
        PAN_INITIAL_ANGLE  : integer := 90;   -- angulo al iniciar / tras HOME
        PAN_MIN_ANGLE      : integer := 0;    -- limite mecanico inferior
        PAN_MAX_ANGLE      : integer := 180;  -- limite mecanico superior

        -- Parametros mecanicos del TILT (servo vertical)
        TILT_INITIAL_ANGLE : integer := 90;
        TILT_MIN_ANGLE     : integer := 50;   -- tilt suele tener rango mas
        TILT_MAX_ANGLE     : integer := 130;  -- angosto que el pan

        -- Cuantos ciclos de reloj esperar entre cada paso de 1 grado
        -- durante el modo SWEEP. Controla la VELOCIDAD del barrido.
        -- (Con un reloj de, por ejemplo, 27 MHz, 972222 ciclos ~= 36 ms/paso)
        SWEEP_STEP_CYCLES  : positive := 972222
    );
    port (
        clk   : in  std_logic;
        reset : in  std_logic;                      -- reset sincrono, activo alto

        rx_data  : in  std_logic_vector(7 downto 0); -- byte recibido
        rx_valid : in  std_logic;                    -- pulso: rx_data es valido este ciclo

        pan_angle  : out integer range 0 to 180;     -- angulo actual de salida (PAN)
        tilt_angle : out integer range 0 to 180;     -- angulo actual de salida (TILT)

        cmd_valid   : out std_logic;                 -- pulso: ultimo comando fue aceptado
        cmd_invalid : out std_logic                  -- pulso: ultimo comando fue rechazado
    );
end entity command_parser;

architecture rtl of command_parser is

    ----------------------------------------------------------------------------
    -- Estados del protocolo: en que parte del comando estamos parseando
    ----------------------------------------------------------------------------
    type state_type is (
        WAIT_CMD,     -- esperando la letra de comando (P/T/H/S/X/R)
        WAIT_DIGIT1,  -- esperando la centena
        WAIT_DIGIT2,  -- esperando la decena
        WAIT_DIGIT3,  -- esperando la unidad
        WAIT_ENTER    -- esperando CR o LF para confirmar/ejecutar
    );
    signal state : state_type := WAIT_CMD;

    -- Que comando se esta armando actualmente (se "recuerda" mientras
    -- se van leyendo los digitos, para saber que hacer al llegar a WAIT_ENTER)
    type cmd_type_t is (CMD_PAN, CMD_TILT, CMD_HOME, CMD_SWEEP, CMD_STOP, CMD_REARM);
    signal cmd_type : cmd_type_t := CMD_PAN;

    -- El PAN puede estar en control manual (obedece pan_reg) o en
    -- barrido automatico (obedece sweep_angle). El TILT no tiene este
    -- concepto porque nunca hace sweep.
    type pan_mode_t is (MANUAL, SWEEP_MODE);
    signal pan_mode : pan_mode_t := MANUAL;

    -- Digitos acumulados del numero de 3 cifras que sigue a P/T
    signal digit1 : integer range 0 to 9 := 0;  -- centena
    signal digit2 : integer range 0 to 9 := 0;  -- decena
    signal digit3 : integer range 0 to 9 := 0;  -- unidad

    -- Registros "manuales": guardan el ultimo angulo pedido explicitamente.
    -- pan_reg sigue existiendo aunque pan_mode = SWEEP_MODE; simplemente
    -- no se usa para la salida hasta volver a MANUAL (con otro P o con HOME).
    signal pan_reg  : integer range 0 to 180 := PAN_INITIAL_ANGLE;
    signal tilt_reg : integer range 0 to 180 := TILT_INITIAL_ANGLE;

    -- Bandera de seguridad: '1' tras un STOP, bloquea todo comando
    -- excepto REARM. Se limpia con REARM.
    signal stopped : std_logic := '0';

    -- Estado del barrido automatico (independiente de pan_reg)
    signal sweep_angle : integer range 0 to 180 := PAN_MIN_ANGLE;
    signal sweep_dir   : std_logic := '1';  -- '1' = subiendo, '0' = bajando
    -- Contador/divisor de frecuencia: cuenta ciclos de reloj hasta
    -- alcanzar SWEEP_STEP_CYCLES-1, momento en que se da un paso de 1 grado.
    signal sweep_timer : integer range 0 to SWEEP_STEP_CYCLES - 1 := 0;

    -- Registros de salida para los pulsos de aceptado/rechazado
    signal led_valid   : std_logic := '0';
    signal led_invalid : std_logic := '0';

begin

    ----------------------------------------------------------------------------
    -- Salidas combinacionales
    ----------------------------------------------------------------------------

    -- TILT siempre sale directo de su registro manual (no tiene modo sweep)
    tilt_angle <= tilt_reg;

    -- PAN es un MUX: si estamos en SWEEP_MODE, sale el contador de barrido;
    -- si estamos en MANUAL, sale el ultimo valor pedido por comando P.
    pan_angle  <= sweep_angle when pan_mode = SWEEP_MODE else pan_reg;

    cmd_valid   <= led_valid;
    cmd_invalid <= led_invalid;

    ----------------------------------------------------------------------------
    -- Proceso principal: sincrono, todo pasa en flanco de subida de clk
    ----------------------------------------------------------------------------
    process(clk)
        -- Variables usadas solo para el calculo del angulo de 3 digitos
        -- dentro de WAIT_ENTER (no necesitan persistir entre ciclos)
        variable digit1_value : integer range 0 to 900; -- digit1 * 100
        variable digit2_value : integer range 0 to 90;  -- digit2 * 10
        variable digit3_value : integer range 0 to 9;   -- digit3 * 1
        variable angle_value  : integer range 0 to 999; -- suma de los 3
    begin
        if rising_edge(clk) then

            ------------------------------------------------------------------
            -- RESET: vuelve todo a su condicion inicial "segura"
            ------------------------------------------------------------------
            if reset = '1' then

                state    <= WAIT_CMD;
                cmd_type <= CMD_PAN;
                pan_mode <= MANUAL;

                digit1 <= 0;
                digit2 <= 0;
                digit3 <= 0;

                pan_reg  <= PAN_INITIAL_ANGLE;
                tilt_reg <= TILT_INITIAL_ANGLE;

                stopped <= '0';

                sweep_angle <= PAN_MIN_ANGLE;
                sweep_dir   <= '1';
                sweep_timer <= 0;

                led_valid   <= '0';
                led_invalid <= '0';

            else

                ----------------------------------------------------------------
                -- LOGICA DE BARRIDO (SWEEP)
                -- Corre TODOS los ciclos (no depende de rx_valid), porque el
                -- movimiento del servo debe ser continuo en el tiempo, no
                -- disparado por la llegada de bytes.
                ----------------------------------------------------------------
                if pan_mode = SWEEP_MODE and stopped = '0' then
                    if sweep_timer = SWEEP_STEP_CYCLES - 1 then
                        -- Se cumplio el tiempo de un "paso": avanzar 1 grado
                        sweep_timer <= 0;
                        if sweep_dir = '1' then
                            if sweep_angle = PAN_MAX_ANGLE then
                                -- Llego al limite superior: rebota (invierte direccion)
                                sweep_dir   <= '0';
                                sweep_angle <= sweep_angle - 1;
                            else
                                sweep_angle <= sweep_angle + 1;
                            end if;
                        else
                            if sweep_angle = PAN_MIN_ANGLE then
                                -- Llego al limite inferior: rebota
                                sweep_dir   <= '1';
                                sweep_angle <= sweep_angle + 1;
                            else
                                sweep_angle <= sweep_angle - 1;
                            end if;
                        end if;
                    else
                        -- Todavia no toca dar el paso: solo contar ciclos
                        sweep_timer <= sweep_timer + 1;
                    end if;
                end if;

                ----------------------------------------------------------------
                -- PARSER DE PROTOCOLO: solo actua cuando llega un byte nuevo
                ----------------------------------------------------------------
                if rx_valid = '1' then

                    case state is

                        --------------------------------------------------------
                        -- Esperando la letra de comando
                        --------------------------------------------------------
                        when WAIT_CMD =>
                            case rx_data is
                                when x"50" | x"70" =>          -- 'P' o 'p'
                                    cmd_type <= CMD_PAN;
                                    state    <= WAIT_DIGIT1;   -- espera 3 digitos
                                when x"54" | x"74" =>          -- 'T' o 't'
                                    cmd_type <= CMD_TILT;
                                    state    <= WAIT_DIGIT1;
                                when x"48" | x"68" =>          -- 'H' o 'h'
                                    cmd_type <= CMD_HOME;
                                    state    <= WAIT_ENTER;    -- sin parametros
                                when x"53" | x"73" =>          -- 'S' o 's'
                                    cmd_type <= CMD_SWEEP;
                                    state    <= WAIT_ENTER;
                                when x"58" | x"78" =>          -- 'X' o 'x'
                                    cmd_type <= CMD_STOP;
                                    state    <= WAIT_ENTER;
                                when x"52" | x"72" =>          -- 'R' o 'r'
                                    cmd_type <= CMD_REARM;
                                    state    <= WAIT_ENTER;
                                when others =>
                                    -- Byte desconocido: se rechaza y se
                                    -- permanece en WAIT_CMD (no cambia 'state')
                                    led_valid   <= '0';
                                    led_invalid <= '1';
                            end case;

                        --------------------------------------------------------
                        -- Digito 1 = centena del angulo
                        --------------------------------------------------------
                        when WAIT_DIGIT1 =>
                            case rx_data is
                                when x"30" => digit1 <= 0; state <= WAIT_DIGIT2;
                                when x"31" => digit1 <= 1; state <= WAIT_DIGIT2;
                                when x"32" => digit1 <= 2; state <= WAIT_DIGIT2;
                                when x"33" => digit1 <= 3; state <= WAIT_DIGIT2;
                                when x"34" => digit1 <= 4; state <= WAIT_DIGIT2;
                                when x"35" => digit1 <= 5; state <= WAIT_DIGIT2;
                                when x"36" => digit1 <= 6; state <= WAIT_DIGIT2;
                                when x"37" => digit1 <= 7; state <= WAIT_DIGIT2;
                                when x"38" => digit1 <= 8; state <= WAIT_DIGIT2;
                                when x"39" => digit1 <= 9; state <= WAIT_DIGIT2;
                                when others =>
                                    -- No es un digito ASCII '0'-'9':
                                    -- error de protocolo -> resincroniza a WAIT_CMD
                                    state       <= WAIT_CMD;
                                    led_valid   <= '0';
                                    led_invalid <= '1';
                            end case;

                        --------------------------------------------------------
                        -- Digito 2 = decena del angulo
                        --------------------------------------------------------
                        when WAIT_DIGIT2 =>
                            case rx_data is
                                when x"30" => digit2 <= 0; state <= WAIT_DIGIT3;
                                when x"31" => digit2 <= 1; state <= WAIT_DIGIT3;
                                when x"32" => digit2 <= 2; state <= WAIT_DIGIT3;
                                when x"33" => digit2 <= 3; state <= WAIT_DIGIT3;
                                when x"34" => digit2 <= 4; state <= WAIT_DIGIT3;
                                when x"35" => digit2 <= 5; state <= WAIT_DIGIT3;
                                when x"36" => digit2 <= 6; state <= WAIT_DIGIT3;
                                when x"37" => digit2 <= 7; state <= WAIT_DIGIT3;
                                when x"38" => digit2 <= 8; state <= WAIT_DIGIT3;
                                when x"39" => digit2 <= 9; state <= WAIT_DIGIT3;
                                when others =>
                                    state       <= WAIT_CMD;
                                    led_valid   <= '0';
                                    led_invalid <= '1';
                            end case;

                        --------------------------------------------------------
                        -- Digito 3 = unidad del angulo
                        --------------------------------------------------------
                        when WAIT_DIGIT3 =>
                            case rx_data is
                                when x"30" => digit3 <= 0; state <= WAIT_ENTER;
                                when x"31" => digit3 <= 1; state <= WAIT_ENTER;
                                when x"32" => digit3 <= 2; state <= WAIT_ENTER;
                                when x"33" => digit3 <= 3; state <= WAIT_ENTER;
                                when x"34" => digit3 <= 4; state <= WAIT_ENTER;
                                when x"35" => digit3 <= 5; state <= WAIT_ENTER;
                                when x"36" => digit3 <= 6; state <= WAIT_ENTER;
                                when x"37" => digit3 <= 7; state <= WAIT_ENTER;
                                when x"38" => digit3 <= 8; state <= WAIT_ENTER;
                                when x"39" => digit3 <= 9; state <= WAIT_ENTER;
                                when others =>
                                    state       <= WAIT_CMD;
                                    led_valid   <= '0';
                                    led_invalid <= '1';
                            end case;

                        --------------------------------------------------------
                        -- Esperando CR/LF: aqui se EJECUTA el comando completo
                        --------------------------------------------------------
                        when WAIT_ENTER =>

                            if (rx_data = x"0D") or (rx_data = x"0A") then
                                -- Terminador valido (CR o LF): procesar comando

                                if cmd_type = CMD_REARM then
                                    -- REARM tiene prioridad sobre el bloqueo de
                                    -- 'stopped': es la unica forma de salir de el.
                                    stopped     <= '0';
                                    led_valid   <= '1';
                                    led_invalid <= '0';

                                elsif stopped = '1' then
                                    -- Sistema bloqueado por STOP: se rechaza
                                    -- cualquier otro comando (medida de seguridad).
                                    led_valid   <= '0';
                                    led_invalid <= '1';

                                else
                                    -- Sistema operativo normal: ejecutar segun cmd_type
                                    case cmd_type is

                                        ------------------------------------------------
                                        when CMD_PAN =>
                                            -- Reconstruir el numero de 3 digitos:
                                            -- digit1*100 + digit2*10 + digit3
                                            -- (se usa 'case' en vez de '*' por estilo/
                                            --  para forzar una implementacion explicita)
                                            case digit1 is
                                                when 0 => digit1_value := 0;
                                                when 1 => digit1_value := 100;
                                                when 2 => digit1_value := 200;
                                                when 3 => digit1_value := 300;
                                                when 4 => digit1_value := 400;
                                                when 5 => digit1_value := 500;
                                                when 6 => digit1_value := 600;
                                                when 7 => digit1_value := 700;
                                                when 8 => digit1_value := 800;
                                                when 9 => digit1_value := 900;
                                                when others => digit1_value := 0;
                                            end case;

                                            case digit2 is
                                                when 0 => digit2_value := 0;
                                                when 1 => digit2_value := 10;
                                                when 2 => digit2_value := 20;
                                                when 3 => digit2_value := 30;
                                                when 4 => digit2_value := 40;
                                                when 5 => digit2_value := 50;
                                                when 6 => digit2_value := 60;
                                                when 7 => digit2_value := 70;
                                                when 8 => digit2_value := 80;
                                                when 9 => digit2_value := 90;
                                                when others => digit2_value := 0;
                                            end case;

                                            digit3_value := digit3;
                                            angle_value  := digit1_value + digit2_value + digit3_value;

                                            -- Validar contra los limites mecanicos del PAN
                                            if (angle_value >= PAN_MIN_ANGLE) and (angle_value <= PAN_MAX_ANGLE) then
                                                pan_reg     <= angle_value;
                                                pan_mode    <= MANUAL;  -- un comando P saca del modo SWEEP
                                                led_valid   <= '1';
                                                led_invalid <= '0';
                                            else
                                                -- Angulo fuera de rango (ej: P999): se rechaza
                                                led_valid   <= '0';
                                                led_invalid <= '1';
                                            end if;

                                        ------------------------------------------------
                                        when CMD_TILT =>
                                            -- Misma logica de reconstruccion que CMD_PAN
                                            case digit1 is
                                                when 0 => digit1_value := 0;
                                                when 1 => digit1_value := 100;
                                                when 2 => digit1_value := 200;
                                                when 3 => digit1_value := 300;
                                                when 4 => digit1_value := 400;
                                                when 5 => digit1_value := 500;
                                                when 6 => digit1_value := 600;
                                                when 7 => digit1_value := 700;
                                                when 8 => digit1_value := 800;
                                                when 9 => digit1_value := 900;
                                                when others => digit1_value := 0;
                                            end case;

                                            case digit2 is
                                                when 0 => digit2_value := 0;
                                                when 1 => digit2_value := 10;
                                                when 2 => digit2_value := 20;
                                                when 3 => digit2_value := 30;
                                                when 4 => digit2_value := 40;
                                                when 5 => digit2_value := 50;
                                                when 6 => digit2_value := 60;
                                                when 7 => digit2_value := 70;
                                                when 8 => digit2_value := 80;
                                                when 9 => digit2_value := 90;
                                                when others => digit2_value := 0;
                                            end case;

                                            digit3_value := digit3;
                                            angle_value  := digit1_value + digit2_value + digit3_value;

                                            -- Validar contra los limites mecanicos del TILT
                                            -- (normalmente mas estrechos que los del PAN)
                                            if (angle_value >= TILT_MIN_ANGLE) and (angle_value <= TILT_MAX_ANGLE) then
                                                tilt_reg    <= angle_value;
                                                led_valid   <= '1';
                                                led_invalid <= '0';
                                            else
                                                led_valid   <= '0';
                                                led_invalid <= '1';
                                            end if;

                                        ------------------------------------------------
                                        when CMD_HOME =>
                                            -- Vuelve ambos servos a su posicion inicial
                                            -- y saca al pan de modo SWEEP si estaba activo
                                            pan_reg     <= PAN_INITIAL_ANGLE;
                                            tilt_reg    <= TILT_INITIAL_ANGLE;
                                            pan_mode    <= MANUAL;
                                            led_valid   <= '1';
                                            led_invalid <= '0';

                                        ------------------------------------------------
                                        when CMD_SWEEP =>
                                            -- Activa el barrido automatico del PAN,
                                            -- reiniciando desde el limite inferior
                                            pan_mode    <= SWEEP_MODE;
                                            sweep_angle <= PAN_MIN_ANGLE;
                                            sweep_dir   <= '1';
                                            sweep_timer <= 0;
                                            led_valid   <= '1';
                                            led_invalid <= '0';

                                        ------------------------------------------------
                                        when CMD_STOP =>
                                            -- Congela el movimiento (el sweep deja de
                                            -- avanzar) y bloquea comandos futuros hasta
                                            -- que llegue un REARM
                                            stopped     <= '1';
                                            led_valid   <= '1';
                                            led_invalid <= '0';

                                        ------------------------------------------------
                                        when others =>
                                            -- CMD_REARM ya se maneja arriba; este
                                            -- 'others' es una red de seguridad
                                            led_valid   <= '0';
                                            led_invalid <= '1';

                                    end case;

                                end if;

                                -- Terminado el comando (aceptado o no), volver
                                -- siempre a esperar el proximo comando
                                state <= WAIT_CMD;

                            else
                                -- Se esperaba CR/LF y llego otra cosa:
                                -- comando invalido, resincronizar
                                state       <= WAIT_CMD;
                                led_valid   <= '0';
                                led_invalid <= '1';

                            end if;

                    end case;

                end if;  -- rx_valid

            end if;  -- reset

        end if;  -- rising_edge

    end process;

end architecture rtl;
```
