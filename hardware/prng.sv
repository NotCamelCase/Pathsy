module prng
#(parameter SEED = 16'hbeef)
(
    input logic         clk, rst,
    input logic         enable,
    output logic[15:0]  rand_number
);
    logic[15:0] lfsr_reg;

    // LFSR
    always_ff @(posedge clk)
    begin
        if (rst)
            lfsr_reg <= SEED;
        else if (enable) // P(x) = x^16 + x^14 + x^13 + x^11 + 1
            lfsr_reg <= {(lfsr_reg[5] ^ lfsr_reg[3] ^ lfsr_reg[2] ^ lfsr_reg[0]), lfsr_reg[15:1]};
    end

    // Output
    assign rand_number = lfsr_reg;
endmodule