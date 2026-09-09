Este codigo es logica combinacional pura qe convierte un angulo ( entero 0-180) en los codigos necesarios para prender 4 displays de 7 segmentos. Se ejecuta continuamente, sin reloj -- cada vez cambia angle o axis, se recalcula todo.
![[display_ctrl_digit_extraction (1).png]]

![[display_ctrl_encoding.png]]

### 1. Entidad y puertos 

``` vhdl
axis : in std_logic;
angle : in integer range 0 to 180;
hex0 .. hex3 : out std_logic_vector ( 6 downto 0);
```

mostrar el angulo actual como 3 digitos decimales ( hex2 hex1 hex0 = centenas, decenas, unidades) y usar el cuarto display (hex3) como etiquet de eje -- para indicar si lo que se esta mostrando es el pan o el tilt 

### 2. la funcion `digit_to_7seg`

``` vhdl
function digit_to_7seg(digit : integer) return std_logic_vector is
```

convierte un dígito 0-9 en el patrón de 7 bits que enciende los segmentos correctos. Los valores están codificados en **lógica negativa (activo bajo)** — típico de los displays de 7 segmentos de placas como la DE10-Lite: un `'0'` en un bit _enciende_ ese segmento, un `'1'` lo _apaga_. Por eso `"1000000"` (solo el bit 0 en cero) dibuja un "0" con todos los segmentos menos el del medio.

Es una función pura (sin efectos secundarios), reutilizable para los tres displays numéricos — buena práctica: evita repetir el mismo `case` tres veces.

### 3. El proceso combinacional 

```vhdl 
process(axis, angle)
```

Lista de sensibilidad correcta: como es combinacional ( sin reloj ), debe reaccionar a cualquier señal que lea dentro del proceso -- y efectivamente solo lee axis y angle. Si faltara alguna aqui en simulacion se veria una salida "vieja" hasta el proximo cambio de una señal que si este en la lista 

#### Separacion en centenas / decenas / unidades 

```vhdl
if temp >= 100 then
	hundreds :=1;
	temp := temp -100;
end if;
```

como el anguno nunca pasa de 180, la centena solo puede ser 0 o 1 -- no hace falta un case, basta un if

```vhdl
for 1 in 0 to 9 loop 
	if temp >= 10 then 
		temp := temp - 10;
		tens := tens + 1;
	end if;
end loop;
```

Aquí, en vez de usar el operador `/` o `mod` de VHDL, el diseño **extrae las decenas por resta repetida**: itera hasta 10 veces, y cada vez que `temp` todavía tiene al menos 10, resta 10 y cuenta una decena más. Como `temp` en este punto está entre 0 y 80 (180-100), el bucle nunca necesita más de 8 iteraciones reales, pero está acotado a 10 por seguridad/generalidad.

Esto es intencional o pedagógico: describe el algoritmo de división como lo harías a mano, en vez de depender del operador de división del lenguaje. Funcionalmente es correcto, pero en síntesis esto se "desenrolla" (unroll) en 10 comparadores y restadores en cascada — más lógica combinacional de la que haría una sola operación `angle / 10` y `angle mod 10`, aunque para un contador tan pequeño (0-180) el costo es insignificante.

```vhdl
ones := temp;
```

Lo que sobra despues de restar centenas y decenas es, por definicion, la unidad.

Asignacion a las salidas


```vhdl
hex0 <= digit_to_7seg(ones);
hex1 <= digit_to_7seg(tens);
hex2 <= digit_to_7seg(hundreds);
```

Orden claro: `hex0` = unidades (dígito menos significativo, normalmente el de más a la derecha en la placa), `hex1` = decenas, `hex2` = centenas (que solo mostrará "0" o "1").

```vhdl
if axis = '0' then
    hex3 <= "0001100";
else
    hex3 <= "0000111";
end if;
```

El cuarto display no muestra un número, sino una **letra fija** que indica qué eje se está viendo — probablemente una "P" (pan) y una "t" o "L" (tilt), codificadas directamente como patrones de segmentos en vez de pasar por `digit_to_7seg` (que solo maneja 0-9). Sin ver la hoja de datos exacta del display no puedo confirmar qué letra dibuja cada patrón, pero la lógica es: es una tabla de 2 entradas en vez de 10.


