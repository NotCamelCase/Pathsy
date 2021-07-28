module true_rom
#(
    parameter ROM_FILE      = "",
    parameter ADDR_WIDTH    = 6,
    parameter DATA_WIDTH    = 8
)
(
    input logic[ADDR_WIDTH-1:0]     addr,
    output logic[DATA_WIDTH-1:0]    data
);
    logic[DATA_WIDTH-1:0]   rom[2**ADDR_WIDTH-1:0];

    initial
    begin
        $readmemb(ROM_FILE, rom);
    end
    
    assign data = rom[addr];
endmodule