library ieee;
use ieee.std_logic_1164.all;

entity display_ctrl is
    port (
        axis  : in std_logic;
        angle : in integer range 0 to 180;

        hex0 : out std_logic_vector(6 downto 0);
        hex1 : out std_logic_vector(6 downto 0);
        hex2 : out std_logic_vector(6 downto 0);
        hex3 : out std_logic_vector(6 downto 0)
    );
end entity display_ctrl;

architecture rtl of display_ctrl is

    function digit_to_7seg(digit : integer) return std_logic_vector is
        variable result : std_logic_vector(6 downto 0);
    begin
        case digit is
            when 0 => result := "1000000";
            when 1 => result := "1111001";
            when 2 => result := "0100100";
            when 3 => result := "0110000";
            when 4 => result := "0011001";
            when 5 => result := "0010010";
            when 6 => result := "0000010";
            when 7 => result := "1111000";
            when 8 => result := "0000000";
            when 9 => result := "0010000";
            when others => result := "1111111";
        end case;
        return result;
    end function;

begin

    process(axis, angle)
        variable temp     : integer range 0 to 180;
        variable hundreds : integer range 0 to 1;
        variable tens     : integer range 0 to 9;
        variable ones     : integer range 0 to 9;
        variable i        : integer;
    begin
        temp := angle;
        hundreds := 0;
        tens := 0;
        ones := 0;

        if temp >= 100 then
            hundreds := 1;
            temp := temp - 100;
        end if;

        for i in 0 to 9 loop
            if temp >= 10 then
                temp := temp - 10;
                tens := tens + 1;
            end if;
        end loop;

        ones := temp;

        hex0 <= digit_to_7seg(ones);
        hex1 <= digit_to_7seg(tens);
        hex2 <= digit_to_7seg(hundreds);

        if axis = '0' then
            hex3 <= "0001100";
        else
            hex3 <= "0000111";
        end if;
    end process;

end architecture rtl;