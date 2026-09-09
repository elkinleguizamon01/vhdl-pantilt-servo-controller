**Cómo funciona, paso a paso:**

1. Cada ciclo de reloj se compara `angle` (la entrada actual) contra `angle_reg` (el último ángulo procesado). Si son distintos y no hay un cálculo en curso (`calc_busy = '0'`), arranca uno nuevo.
2. `calc_target` guarda cuántos grados hay que "sumar" (el ángulo relativo a `MIN_ANGLE`).
3. Durante los siguientes ciclos, mientras `calc_busy = '1'`, cada ciclo suma `PULSE_CYCLES_PER_DEGREE` una vez a `calc_accum` y avanza `calc_count` — es literalmente hacer `angle × PULSE_CYCLES_PER_DEGREE` **un grado por ciclo de reloj**, en vez de con un multiplicador combinacional.
4. Cuando `calc_count` alcanza `calc_target`, el resultado acumulado se publica en `pulse_width`, y `calc_busy` vuelve a `'0'`