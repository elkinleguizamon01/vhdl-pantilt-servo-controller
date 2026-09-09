library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity command_parser is
    generic (
        PAN_INITIAL_ANGLE  : integer := 90;
        PAN_MIN_ANGLE      : integer := 0;
        PAN_MAX_ANGLE      : integer := 180;

        TILT_INITIAL_ANGLE : integer := 90;
        TILT_MIN_ANGLE     : integer := 50;
        TILT_MAX_ANGLE     : integer := 130;

        SWEEP_STEP_CYCLES  : positive := 972222
    );
    port (
        clk   : in  std_logic;
        reset : in  std_logic;

        rx_data  : in  std_logic_vector(7 downto 0);
        rx_valid : in  std_logic;

        pan_angle  : out integer range 0 to 180;
        tilt_angle : out integer range 0 to 180;

        cmd_valid   : out std_logic;
        cmd_invalid : out std_logic
    );
end entity command_parser;

architecture rtl of command_parser is

    type state_type is (WAIT_CMD, WAIT_DIGIT1, WAIT_DIGIT2, WAIT_DIGIT3, WAIT_ENTER);
    signal state : state_type := WAIT_CMD;

    type cmd_type_t is (CMD_PAN, CMD_TILT, CMD_HOME, CMD_SWEEP, CMD_STOP, CMD_REARM);
    signal cmd_type : cmd_type_t := CMD_PAN;

    type pan_mode_t is (MANUAL, SWEEP_MODE);
    signal pan_mode : pan_mode_t := MANUAL;

    signal digit1 : integer range 0 to 9 := 0;
    signal digit2 : integer range 0 to 9 := 0;
    signal digit3 : integer range 0 to 9 := 0;

    signal pan_reg  : integer range 0 to 180 := PAN_INITIAL_ANGLE;
    signal tilt_reg : integer range 0 to 180 := TILT_INITIAL_ANGLE;

    signal stopped : std_logic := '0';

    signal sweep_angle : integer range 0 to 180 := PAN_MIN_ANGLE;
    signal sweep_dir   : std_logic := '1';
    signal sweep_timer : integer range 0 to SWEEP_STEP_CYCLES - 1 := 0;

    signal led_valid   : std_logic := '0';
    signal led_invalid : std_logic := '0';

begin

    tilt_angle <= tilt_reg;
    pan_angle  <= sweep_angle when pan_mode = SWEEP_MODE else pan_reg;

    cmd_valid   <= led_valid;
    cmd_invalid <= led_invalid;

    process(clk)
        variable digit1_value : integer range 0 to 900;
        variable digit2_value : integer range 0 to 90;
        variable digit3_value : integer range 0 to 9;
        variable angle_value  : integer range 0 to 999;
    begin
        if rising_edge(clk) then
            if reset = '1' then

                state <= WAIT_CMD;
                cmd_type <= CMD_PAN;
                pan_mode <= MANUAL;

                digit1 <= 0;
                digit2 <= 0;
                digit3 <= 0;

                pan_reg  <= PAN_INITIAL_ANGLE;
                tilt_reg <= TILT_INITIAL_ANGLE;

                stopped <= '0';

                sweep_angle <= PAN_MIN_ANGLE;
                sweep_dir <= '1';
                sweep_timer <= 0;

                led_valid <= '0';
                led_invalid <= '0';

            else

                if pan_mode = SWEEP_MODE and stopped = '0' then
                    if sweep_timer = SWEEP_STEP_CYCLES - 1 then
                        sweep_timer <= 0;
                        if sweep_dir = '1' then
                            if sweep_angle = PAN_MAX_ANGLE then
                                sweep_dir <= '0';
                                sweep_angle <= sweep_angle - 1;
                            else
                                sweep_angle <= sweep_angle + 1;
                            end if;
                        else
                            if sweep_angle = PAN_MIN_ANGLE then
                                sweep_dir <= '1';
                                sweep_angle <= sweep_angle + 1;
                            else
                                sweep_angle <= sweep_angle - 1;
                            end if;
                        end if;
                    else
                        sweep_timer <= sweep_timer + 1;
                    end if;
                end if;

                if rx_valid = '1' then

                    case state is

                        when WAIT_CMD =>
                            case rx_data is
                                when x"50" | x"70" =>
                                    cmd_type <= CMD_PAN;
                                    state <= WAIT_DIGIT1;
                                when x"54" | x"74" =>
                                    cmd_type <= CMD_TILT;
                                    state <= WAIT_DIGIT1;
                                when x"48" | x"68" =>
                                    cmd_type <= CMD_HOME;
                                    state <= WAIT_ENTER;
                                when x"53" | x"73" =>
                                    cmd_type <= CMD_SWEEP;
                                    state <= WAIT_ENTER;
                                when x"58" | x"78" =>
                                    cmd_type <= CMD_STOP;
                                    state <= WAIT_ENTER;
                                when x"52" | x"72" =>
                                    cmd_type <= CMD_REARM;
                                    state <= WAIT_ENTER;
                                when others =>
                                    led_valid <= '0';
                                    led_invalid <= '1';
                            end case;

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
                                    state <= WAIT_CMD;
                                    led_valid <= '0';
                                    led_invalid <= '1';
                            end case;

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
                                    state <= WAIT_CMD;
                                    led_valid <= '0';
                                    led_invalid <= '1';
                            end case;

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
                                    state <= WAIT_CMD;
                                    led_valid <= '0';
                                    led_invalid <= '1';
                            end case;

                        when WAIT_ENTER =>

                            if (rx_data = x"0D") or (rx_data = x"0A") then

                                if cmd_type = CMD_REARM then

                                    stopped <= '0';
                                    led_valid <= '1';
                                    led_invalid <= '0';

                                elsif stopped = '1' then

                                    led_valid <= '0';
                                    led_invalid <= '1';

                                else

                                    case cmd_type is

                                        when CMD_PAN =>

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
                                            angle_value := digit1_value + digit2_value + digit3_value;

                                            if (angle_value >= PAN_MIN_ANGLE) and (angle_value <= PAN_MAX_ANGLE) then
                                                pan_reg <= angle_value;
                                                pan_mode <= MANUAL;
                                                led_valid <= '1';
                                                led_invalid <= '0';
                                            else
                                                led_valid <= '0';
                                                led_invalid <= '1';
                                            end if;

                                        when CMD_TILT =>

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
                                            angle_value := digit1_value + digit2_value + digit3_value;

                                            if (angle_value >= TILT_MIN_ANGLE) and (angle_value <= TILT_MAX_ANGLE) then
                                                tilt_reg <= angle_value;
                                                led_valid <= '1';
                                                led_invalid <= '0';
                                            else
                                                led_valid <= '0';
                                                led_invalid <= '1';
                                            end if;

                                        when CMD_HOME =>
                                            pan_reg  <= PAN_INITIAL_ANGLE;
                                            tilt_reg <= TILT_INITIAL_ANGLE;
                                            pan_mode <= MANUAL;
                                            led_valid <= '1';
                                            led_invalid <= '0';

                                        when CMD_SWEEP =>
                                            pan_mode <= SWEEP_MODE;
                                            sweep_angle <= PAN_MIN_ANGLE;
                                            sweep_dir <= '1';
                                            sweep_timer <= 0;
                                            led_valid <= '1';
                                            led_invalid <= '0';

                                        when CMD_STOP =>
                                            stopped <= '1';
                                            led_valid <= '1';
                                            led_invalid <= '0';

                                        when others =>
                                            led_valid <= '0';
                                            led_invalid <= '1';

                                    end case;

                                end if;

                                state <= WAIT_CMD;

                            else

                                state <= WAIT_CMD;
                                led_valid <= '0';
                                led_invalid <= '1';

                            end if;

                    end case;

                end if;

            end if;

        end if;

    end process;

end architecture rtl;