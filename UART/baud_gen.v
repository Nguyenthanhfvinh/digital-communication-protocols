module baud_gen #(
    parameter CLK_FREQ = 27_000_000,   // System clock (Hz)
    parameter BAUD     = 115200        // Desired baud rate
)(
    input  wire clk,
    input  wire rst_n,
    output reg  baud_tick             // 1-cycle pulse every bit time
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD;   // ≈ 234
    localparam CNT_WIDTH    = $clog2(CLKS_PER_BIT);

    reg [CNT_WIDTH-1:0] counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter   <= 0;
            baud_tick <= 1'b0;
        end else begin
            if (counter == CLKS_PER_BIT - 1) begin
                counter   <= 0;
                baud_tick <= 1'b1;
            end else begin
                counter   <= counter + 1'b1;
                baud_tick <= 1'b0;
            end
        end
    end
endmodule