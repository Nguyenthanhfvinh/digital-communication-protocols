module i2c_master #(
    parameter SYS_CLK_FREQ = 50_000_000,
    parameter I2C_FREQ     = 100_000
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire       rw,
    input  wire [6:0] addr,
    input  wire [7:0] data_in,

    output reg  [7:0] data_out,
    output reg        busy,
    output reg        ack_error,

    inout  wire scl,
    inout  wire sda
);

    // Clock Divider (4x oversampling)
    localparam integer TICK_DIV =
        (SYS_CLK_FREQ / (I2C_FREQ * 4) < 1) ?
        1 : SYS_CLK_FREQ / (I2C_FREQ * 4);

    localparam integer CLK_CNT_WIDTH = (TICK_DIV <= 1) ? 1 : $clog2(TICK_DIV);
    reg [CLK_CNT_WIDTH-1:0] clk_cnt;
    reg tick;

    // A released SCL can still be held low by the slave. Restart the
    // quarter-period timer while waiting so the subsequent high phase
    // gets its full duration, even if the slave releases SCL between ticks.
    wire stretch_wait;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_cnt <= 0;
            tick    <= 0;
        end
        else if (stretch_wait) begin
            clk_cnt <= 0;
            tick    <= 0;
        end
        else begin
            if (clk_cnt == TICK_DIV-1) begin
                clk_cnt <= 0;
                tick    <= 1;
            end
            else begin
                clk_cnt <= clk_cnt + 1;
                tick    <= 0;
            end
        end
    end

    // FSM States
    localparam IDLE      = 4'd0,
               START1    = 4'd1,
               START2    = 4'd2,
               ADDR      = 4'd3,
               ACK_ADDR  = 4'd4,
               DATA      = 4'd5,
               ACK_DATA  = 4'd6,
               STOP1     = 4'd7,
               STOP2     = 4'd8;

    reg [3:0] state;
    reg [1:0] phase;
    reg [2:0] bit_cnt;

    reg [7:0] tx_shift;
    reg [7:0] rx_shift;
    reg [7:0] write_data;

    reg is_read;

    // Open-Drain Drivers
    reg scl_out;
    reg sda_out;

    assign scl = (scl_out == 1'b0) ? 1'b0 : 1'bz;
    assign sda = (sda_out == 1'b0) ? 1'b0 : 1'bz;
    assign stretch_wait = scl_out && !scl;

    // Main FSM
    always @(posedge clk or posedge rst) begin

        if (rst) begin
            state      <= IDLE;
            phase      <= 0;
            bit_cnt    <= 7;

            scl_out    <= 1;
            sda_out    <= 1;

            tx_shift   <= 0;
            rx_shift   <= 0;
            write_data <= 0;

            data_out   <= 0;
            busy       <= 0;
            ack_error  <= 0;
            is_read    <= 0;
        end

        else begin

            if (state == IDLE && start) begin

                busy      <= 1'b1;
                ack_error <= 1'b0;

                tx_shift  <= {addr, rw};
                is_read   <= rw;
                write_data <= data_in;
                rx_shift  <= 0;

                bit_cnt   <= 3'd7;
                phase     <= 2'd0;

                state     <= START1;
            end

            else if (tick && !stretch_wait) begin

                case (state)

                IDLE: begin
                    scl_out <= 1;
                    sda_out <= 1;
                    busy    <= 0;
                end

                START1: begin
                    scl_out <= 1;
                    sda_out <= 0;
                    phase   <= 0;
                    state   <= START2;
                end

                START2: begin
                    // Hold START for two quarter periods before lowering SCL.
                    if (phase == 0)
                        phase <= 1;
                    else begin
                        scl_out <= 0;
                        phase   <= 0;
                        state   <= ADDR;
                    end
                end

                ADDR: begin

                    case (phase)

                    0: begin
                        scl_out <= 0;
                        sda_out <= tx_shift[bit_cnt];
                        phase   <= 1;
                    end

                    1: begin
                        scl_out <= 1;
                        phase   <= 2;
                    end

                    2: begin
                        phase <= 3;
                    end

                    3: begin
                        scl_out <= 0;

                        if (bit_cnt == 0) begin
                            phase <= 0;
                            state <= ACK_ADDR;
                        end
                        else begin
                            bit_cnt <= bit_cnt - 1;
                            phase   <= 0;
                        end
                    end

                    endcase
                end

                ACK_ADDR: begin

                    case (phase)

                    0: begin
                        scl_out <= 0;
                        sda_out <= 1; // Release SDA for slave ACK
                        phase   <= 1;
                    end

                    1: begin
                        scl_out <= 1;
                        phase   <= 2;
                    end

                    2: begin
                        ack_error <= sda; // Sample slave ACK (0=ACK, 1=NACK)
                        phase     <= 3;
                    end

                    3: begin
                        scl_out <= 0;
                        bit_cnt <= 7;

                        if (!is_read)
                            tx_shift <= write_data;

                        phase <= 0;
                        // An unacknowledged address ends the transaction.
                        state <= ack_error ? STOP1 : DATA;
                    end

                    endcase
                end

                DATA: begin

                    case (phase)

                    0: begin
                        scl_out <= 0;

                        if (!is_read)
                            sda_out <= tx_shift[bit_cnt];
                        else
                            sda_out <= 1; // Release SDA for slave read

                        phase <= 1;
                    end

                    1: begin
                        scl_out <= 1;
                        phase   <= 2;
                    end

                    2: begin
                        if (is_read)
                            rx_shift <= {rx_shift[6:0], sda};

                        phase <= 3;
                    end

                    3: begin
                        scl_out <= 0;

                        if (bit_cnt == 0) begin

                            if (is_read)
                                data_out <= rx_shift;

                            phase <= 0;
                            state <= ACK_DATA;
                        end
                        else begin
                            bit_cnt <= bit_cnt - 1;
                            phase   <= 0;
                        end
                    end

                    endcase
                end

                ACK_DATA: begin

                    case (phase)

                    0: begin
                        scl_out <= 0;

                        if (is_read)
                            sda_out <= 1; // Send NACK after read
                        else
                            sda_out <= 1; // Release SDA for slave ACK

                        phase <= 1;
                    end

                    1: begin
                        scl_out <= 1;
                        phase   <= 2;
                    end

                    2: begin
                        if (!is_read)
                            ack_error <= ack_error | sda;

                        phase <= 3;
                    end

                    3: begin
                        scl_out <= 0;
                        state   <= STOP1;
                    end

                    endcase
                end

                STOP1: begin
                    scl_out <= 0;
                    sda_out <= 0;
                    phase   <= 0;
                    state   <= STOP2;
                end

                STOP2: begin
                    case (phase)
                    0: begin
                        // Raise SCL first, keeping SDA low. stretch_wait
                        // prevents advancing until SCL actually rises.
                        scl_out <= 1;
                        phase   <= 1;
                    end
                    1: phase <= 2;
                    2: begin
                        // SDA rising while SCL is high creates STOP.
                        sda_out <= 1;
                        phase   <= 3;
                    end
                    3: begin
                        busy    <= 0;
                        phase   <= 0;
                        state   <= IDLE;
                    end
                    endcase
                end

                default: begin
                    state   <= IDLE;
                    scl_out <= 1;
                    sda_out <= 1;
                    busy    <= 0;
                end

                endcase
            end
        end
    end

endmodule
