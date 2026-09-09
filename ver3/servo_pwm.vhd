library ieee;
use ieee.std_logic_1164.all;

entity servo_pwm is
    generic (
        PWM_PERIOD_CYCLES       : positive := 1000000;
        MIN_ANGLE               : integer  := 0;
        MAX_ANGLE               : integer  := 180;
        BASE_PULSE_CYCLES       : positive := 50000;
        PULSE_CYCLES_PER_DEGREE : positive := 278
    );
    port (
        clk   : in  std_logic;
        reset : in  std_logic;
        angle : in  integer range 0 to 180;
        pwm   : out std_logic
    );
end entity servo_pwm;

architecture rtl of servo_pwm is

    signal counter     : integer range 0 to PWM_PERIOD_CYCLES - 1 := 0;
    signal pulse_width : integer range 0 to PWM_PERIOD_CYCLES - 1 := BASE_PULSE_CYCLES;

    signal angle_reg   : integer range 0 to 180 := MIN_ANGLE;
    signal calc_accum  : integer range 0 to PWM_PERIOD_CYCLES - 1 := BASE_PULSE_CYCLES;
    signal calc_count  : integer range 0 to 180 := 0;
    signal calc_target : integer range 0 to 180 := 0;
    signal calc_busy   : std_logic := '0';

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                counter <= 0;
                pulse_width <= BASE_PULSE_CYCLES;
                angle_reg <= MIN_ANGLE;
                calc_accum <= BASE_PULSE_CYCLES;
                calc_count <= 0;
                calc_target <= 0;
                calc_busy <= '0';
                pwm <= '0';
            else

                if calc_busy = '0' and angle /= angle_reg then
                    angle_reg <= angle;
                    calc_target <= angle - MIN_ANGLE;
                    calc_accum <= BASE_PULSE_CYCLES;
                    calc_count <= 0;
                    calc_busy <= '1';
                elsif calc_busy = '1' then
                    if calc_count = calc_target then
                        pulse_width <= calc_accum;
                        calc_busy <= '0';
                    else
                        calc_accum <= calc_accum + PULSE_CYCLES_PER_DEGREE;
                        calc_count <= calc_count + 1;
                    end if;
                end if;

                if counter = PWM_PERIOD_CYCLES - 1 then
                    counter <= 0;
                else
                    counter <= counter + 1;
                end if;

                if counter < pulse_width then
                    pwm <= '1';
                else
                    pwm <= '0';
                end if;

            end if;
        end if;
    end process;

end architecture rtl;