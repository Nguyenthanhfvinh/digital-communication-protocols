module uart_tx #(
    parameter integer CLK_FREQ = 100_000_000,
    parameter integer BAUD     = 115200
  )(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       tx_valid,
    output wire       tx_ready,
    input  wire [7:0] tx_data,

    output reg        tx_busy,
    output reg        tx_done,
    output reg        txd
  );

  localparam [1:0] IDLE  = 2'd0;
  localparam [1:0] START = 2'd1;
  localparam [1:0] DATA  = 2'd2;
  localparam [1:0] STOP  = 2'd3;

  reg [1:0] state;
  reg [2:0] bit_idx;
  reg [7:0] shift_reg;

  wire baud_tick;
  wire start_from_idle;
  wire stop_complete;
  wire accept_byte;

  assign stop_complete   = (state == STOP) && baud_tick;
  assign tx_ready        = (state == IDLE) || stop_complete;
  assign accept_byte     = tx_valid && tx_ready;
  assign start_from_idle = (state == IDLE) && tx_valid;

  baud_gen #(
             .CLK_FREQ  (CLK_FREQ),
             .TICK_RATE (BAUD)
           ) u_tx_baud (
             .clk     (clk),
             .rst_n   (rst_n),
             .enable  (tx_busy),
             .restart (start_from_idle),
             .tick    (baud_tick)
           );

  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
    begin
      state     <= IDLE;
      bit_idx   <= 3'd0;
      shift_reg <= 8'h00;
      tx_busy   <= 1'b0;
      tx_done   <= 1'b0;
      txd       <= 1'b1;
    end
    else
    begin
      tx_done <= 1'b0;

      case (state)
        IDLE:
        begin
          tx_busy <= 1'b0;
          txd     <= 1'b1;
          bit_idx <= 3'd0;

          if (accept_byte)
          begin
            shift_reg <= tx_data;
            tx_busy   <= 1'b1;
            txd       <= 1'b0;  // start bit begins now
            state     <= START;
          end
        end

        START:
        begin
          tx_busy <= 1'b1;
          txd     <= 1'b0;
          if (baud_tick)
          begin
            txd   <= shift_reg[0];
            state <= DATA;
          end
        end

        DATA:
        begin
          tx_busy <= 1'b1;
          if (baud_tick)
          begin
            if (bit_idx == 3'd7)
            begin
              bit_idx <= 3'd0;
              txd     <= 1'b1;
              state   <= STOP;
            end
            else
            begin
              shift_reg <= {1'b0, shift_reg[7:1]};
              bit_idx   <= bit_idx + 1'b1;
              txd       <= shift_reg[1];
            end
          end
        end

        STOP:
        begin
          tx_busy <= 1'b1;
          txd     <= 1'b1;
          if (baud_tick)
          begin
            tx_done <= 1'b1;

            if (tx_valid)
            begin
              shift_reg <= tx_data;
              bit_idx   <= 3'd0;
              txd       <= 1'b0;
              state     <= START;
            end
            else
            begin
              tx_busy <= 1'b0;
              state   <= IDLE;
            end
          end
        end

        default:
        begin
          state     <= IDLE;
          bit_idx   <= 3'd0;
          shift_reg <= 8'h00;
          tx_busy   <= 1'b0;
          tx_done   <= 1'b0;
          txd       <= 1'b1;
        end
      endcase
    end
  end

endmodule
