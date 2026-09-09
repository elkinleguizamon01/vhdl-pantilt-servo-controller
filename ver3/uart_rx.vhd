library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
    generic (
        CLKS_PER_BIT : positive := 10417;
        DATA_BITS    : positive := 8
    );
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        rx         : in  std_logic;

        data_out   : out std_logic_vector(DATA_BITS-1 downto 0);
        data_valid : out std_logic
    );
end entity uart_rx;

architecture rtl of uart_rx is

    type state_type is (IDLE, START_BIT, DATA_BITS_STATE, STOP_BIT);
    signal state : state_type := IDLE;

    signal rx_ff1 : std_logic := '1';
    signal rx_ff2 : std_logic := '1';

    signal clk_count : integer range 0 to CLKS_PER_BIT - 1 := 0;
    signal bit_index : integer range 0 to DATA_BITS - 1 := 0;

    signal data_reg : std_logic_vector(DATA_BITS-1 downto 0) := (others => '0');

begin

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

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= IDLE;
                clk_count <= 0;
                bit_index <= 0;
                data_reg <= (others => '0');
                data_out <= (others => '0');
                data_valid <= '0';
            else
                data_valid <= '0';

                case state is

                    when IDLE =>
                        clk_count <= 0;
                        bit_index <= 0;
                        if rx_ff2 = '0' then
                            state <= START_BIT;
                        end if;

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

                    when STOP_BIT =>
                        if clk_count = CLKS_PER_BIT - 1 then
                            clk_count <= 0;
                            data_out <= data_reg;
                            data_valid <= '1';
                            state <= IDLE;
                        else
                            clk_count <= clk_count + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;