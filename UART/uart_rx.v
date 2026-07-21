
module uart_rx #(
    parameter CLKS_PER_BIT = 234
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rxd,
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    output reg        rx_busy,
    output reg        frame_error
);

    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam DATA  = 3'd2;
    localparam STOP  = 3'd3;
    localparam CLEAN = 3'd4;

    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_reg;          // ★ SIPO ★

    // Double synchronizer
    reg rxd_sync1, rxd_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rxd_sync1 <= 1'b1;
            rxd_sync2 <= 1'b1;
        end else begin
            rxd_sync1 <= rxd;
            rxd_sync2 <= rxd_sync1;
        end
    end
    wire rxd_stable = rxd_sync2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            rx_data     <= 8'h00;
            rx_valid    <= 1'b0;
            rx_busy     <= 1'b0;
            frame_error <= 1'b0;
            clk_cnt     <= 0;
            bit_idx     <= 0;
            shift_reg   <= 8'h00;
        end else begin
            rx_valid    <= 1'b0;
            frame_error <= 1'b0;

            case (state)
                IDLE: begin
                    rx_busy <= 1'b0;
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (rxd_stable == 1'b0) begin
                        rx_busy <= 1'b1;
                        state   <= START;
                    end
                end

                START: begin
                    if (clk_cnt == (CLKS_PER_BIT-1)/2) begin
                        if (rxd_stable == 1'b0) begin
                            clk_cnt <= 0;
                            state   <= DATA;
                        end else
                            state <= IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end

                DATA: begin
                    if (clk_cnt < CLKS_PER_BIT-1)
                        clk_cnt <= clk_cnt + 1;
                    else begin
                        clk_cnt <= 0;
                        // ★ SIPO: sample mid-bit, LSB first
                        shift_reg <= {rxd_stable, shift_reg[7:1]};
                        if (bit_idx < 7)
                            bit_idx <= bit_idx + 1;
                        else begin
                            bit_idx <= 0;
                            state   <= STOP;
                        end
                    end
                end

                STOP: begin
                    if (clk_cnt < CLKS_PER_BIT-1)
                        clk_cnt <= clk_cnt + 1;
                    else begin
                        clk_cnt <= 0;
                        if (rxd_stable == 1'b1) begin
                            rx_data  <= shift_reg;
                            rx_valid <= 1'b1;
                        end else
                            frame_error <= 1'b1;
                        state <= CLEAN;
                    end
                end

                CLEAN: begin
                    rx_busy <= 1'b0;
                    state   <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule