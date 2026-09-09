Este es el módulo que le da entrada de datos a todo el sistema: convierte la señal serial física (`rx`, un solo bit que cambia en el tiempo) en un byte paralelo (`data_out`) con un pulso `data_valid`. Es el mismo `rx_data`/`rx_valid` que alimenta a `command_parser`. Tiene dos partes bien diferenciadas.

![[uart_rx_fsm.png]]

### El sincronizador de doble flip-flop

``` vhdl
process(clk)
begin
    if rising_edge(clk) then
        if reset = '1' then
            rx_ff1 <= '1';
            rx_ff2 <= '1';
        else
            rx_ff1 <= rx;
            rx_ff2 <= rx_ff1;
        end if;
    end if;
end process;
```

Esto es un proceso **separado y muy simple**, pero resuelve un problema real de hardware: `rx` viene de un pin externo, de otro dominio de tiempo (el transmisor que la generó no está sincronizado con el `clk` de esta FPGA). Si se leyera `rx` directamente y esta cambiara justo en el instante del flanco de reloj, el flip-flop podría entrar en un estado **metaestable** (ni '0' ni '1' definido por un tiempo), lo que puede propagar un valor corrupto o inconsistente al resto del circuito.

La solución estándar es este **sincronizador de dos etapas**: `rx_ff1` captura `rx` (puede quedar metaestable), y `rx_ff2` captura a `rx_ff1` un ciclo después — le da tiempo a la metaestabilidad de resolverse antes de que ese valor se use en cualquier lógica real. Es la razón por la que todo el resto del diseño lee `rx_ff2`, nunca `rx` directamente.

Nota que se inicializan en `'1'`: en UART, la línea reposa en alto (`'1'`) cuando no hay transmisión — así que al arrancar o resetear, el diseño asume correctamente que la línea está en reposo.

### 2. La máquina de estados de recepción

```
type state_type is (IDLE, START_BIT, DATA_BITS_STATE, STOP_BIT);
```

`IDLE` --Esperando el bit de inicio

```VHDL
when IDLE => 
	clk_count <= 0;
	bit_index <= 0;
	if rx_ff2 = '0' then
		state <= START_BIT;
	end if;
```

En UART, una transmisión empieza cuando la línea cae de `'1'` a `'0'` (el "start bit"). Este estado simplemente espera ese flanco de bajada. Nota que aquí se reinician `clk_count` y `bit_index` — dejando todo listo para la próxima recepción.

`START_BIT` -- confirmar y centrar el muestreo

```vhdl
when START_BIT =>
    if clk_count = (CLKS_PER_BIT / 2) then
        if rx_ff2 = '0' then
            clk_count <= 0;
            state <= DATA_BITS_STATE;
        else
            state <= IDLE;
        end if;
    else
        clk_count <= clk_count + 1;
    end if;
    
```


Aquí está el detalle más importante de todo el módulo: en vez de avanzar inmediatamente al detectar el flanco de bajada, el diseño **espera hasta la mitad de un período de bit** (`CLKS_PER_BIT / 2`) antes de volver a comprobar `rx_ff2`.

¿Por qué? Dos razones:

1. **Filtrar ruido/glitches**: si esa caída fue un pulso espurio muy corto y la línea ya volvió a `'1'`, aquí se detecta (`else state <= IDLE`) y se cancela la recepción, evitando leer un byte basura.
2. **Centrar el punto de muestreo**: al confirmar el start bit en la _mitad_ de su duración, todos los muestreos siguientes (que ocurren cada `CLKS_PER_BIT` ciclos completos desde ese punto) caen justo en el **centro** de cada bit de dato, no en sus bordes — donde la señal es más estable y hay menos riesgo de leer un valor en transición.
`DATA_BITS_STATE` -capturar los 8 bist de datos

```vhdl
when DATA_BITS_STATE =>
    if clk_count = CLKS_PER_BIT - 1 then
        clk_count <= 0;
        data_reg(bit_index) <= rx_ff2;
        if bit_index = DATA_BITS - 1 then
            state <= STOP_BIT;
        else
            bit_index <= bit_index + 1;
        end if;
    else
        clk_count <= clk_count + 1;
    end if;
```

Cada `CLKS_PER_BIT` ciclos (un período de bit completo, ya centrado gracias al paso anterior), se captura el valor actual de `rx_ff2` y se guarda en `data_reg(bit_index)`. UART transmite típicamente **LSB primero**, así que `bit_index` empezando en 0 va llenando el registro desde el bit menos significativo. Cuando se completan los `DATA_BITS` bits (8 en este caso), pasa a esperar el stop bit.

#### `STOP_BIT` — validar el fin de trama y publicar el byte

Espera un período de bit más (el stop bit, que en UART estándar es `'1'`), y al completarse, **publica** el byte completo en `data_out` y levanta `data_valid <= '1'` por exactamente un ciclo de reloj — gracias a que `data_valid <= '0'` se ejecuta al principio de cada ciclo del proceso (antes del `case`), así que solo queda en `'1'` el ciclo en que se ejecuta esta rama.

Nota que este estado, a diferencia de `START_BIT`, **no vuelve a comprobar** si `rx_ff2` realmente vale `'1'` (el stop bit esperado) — simplemente asume que sí y publica el dato. Es una simplificación razonable para un diseño educativo/hobby: un receptor UART más robusto normalmente validaría el stop bit y señalizaría un error de trama (framing error) si no lo encuentra en `'1'`.

### 3. Cómo encaja `CLKS_PER_BIT` con el resto del sistema

El generic por defecto es `10417`. Con un reloj de 50 MHz: 50,000,000 / 10417 ≈ **4800 baudios** — de hecho es el mismo valor que usa `command_parser` no directamente, pero sí lo hereda `pwmservo` al instanciar `uart_rx` con el mismo generic. Este número **debe coincidir** con la velocidad configurada en el terminal serial que envía los comandos (`P090\r`, etc.) — si no coinciden, el receptor muestrearía los bits en el momento equivocado y produciría bytes corruptos.