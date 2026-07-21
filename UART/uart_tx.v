//============================================================
// uart_tx.v
// UART Transmitter with ★PISO★
// 8N1
//============================================================
module uart_tx #(
    parameter CLKS_PER_BIT = 234
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx_busy,
    output reg        tx_done,
    output reg        txd
);

    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam DATA  = 3'd2;
    localparam STOP  = 3'd3;
    localparam CLEAN = 3'd4;

    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_reg;          // ★ PISO ★

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            txd       <= 1'b1;
            tx_busy   <= 1'b0;
            tx_done   <= 1'b0;
            clk_cnt   <= 0;
            bit_idx   <= 0;
            shift_reg <= 8'h00;
        end else begin
            tx_done <= 1'b0;

            case (state)
                IDLE: begin
                    txd     <= 1'b1;
                    tx_busy <= 1'b0;
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (tx_start) begin
                        shift_reg <= tx_data;      // Load PISO
                        tx_busy   <= 1'b1;
                        state     <= START;
                    end
                end

                START: begin
                    txd <= 1'b0;                   // Start bit
                    if (clk_cnt < CLKS_PER_BIT-1)
                        clk_cnt <= clk_cnt + 1;
                    else begin
                        clk_cnt <= 0;
                        state   <= DATA;
                    end
                end

                DATA: begin
                    txd <= shift_reg[0];           // LSB first (PISO)
                    if (clk_cnt < CLKS_PER_BIT-1)
                        clk_cnt <= clk_cnt + 1;
                    else begin
                        clk_cnt   <= 0;
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        if (bit_idx < 7)
                            bit_idx <= bit_idx + 1;
                        else begin
                            bit_idx <= 0;
                            state   <= STOP;
                        end
                    end
                end

                STOP: begin
                    txd <= 1'b1;                   // Stop bit
                    if (clk_cnt < CLKS_PER_BIT-1)
                        clk_cnt <= clk_cnt + 1;
                    else begin
                        clk_cnt <= 0;
                        state   <= CLEAN;
                    end
                end

                CLEAN: begin
                    tx_busy <= 1'b0;
                    tx_done <= 1'b1;
                    state   <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule