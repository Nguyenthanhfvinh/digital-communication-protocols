// =============================================================
// SPI Master - Mode 0 (CPOL=0, CPHA=0)
// - MSB first
// - Data shifted out on falling edge of SCK
// - Data sampled on rising edge of SCK
// - SCK frequency = clk / (2 * CLK_DIV)
// =============================================================
module master_spi
  (
    input             clk,
    input             rst_n,
    input             start,
    input [7:0]       tx_data,

    input             miso,
    output reg        mosi,
    output reg        sck,
    output reg        cs_n,

    output reg        busy,
    output reg        done,
    output reg [7:0]  rx_data
  );
  // -----------------------------------------------------------
  // Parameter
  // -----------------------------------------------------------
  parameter CLK_DIV = 4;   // SCK half-period = CLK_DIV clock cycles

  localparam CLK_CNT_WIDTH = (CLK_DIV <= 1) ? 1 : $clog2(CLK_DIV);
  reg [CLK_CNT_WIDTH-1:0] clk_count;
  // -----------------------------------------------------------
  // Internal registers
  // -----------------------------------------------------------
  reg [2:0]  bit_count;
  // reg [15:0] clk_count;
  reg [7:0]  tx_shift;
  reg [7:0]  rx_shift;
  reg        start_d;

  // -----------------------------------------------------------
  // FSM state encoding
  // -----------------------------------------------------------
  localparam
    IDLE     = 2'b00,
    START    = 2'b01,
    TRANSFER = 2'b10,
    STOP     = 2'b11;

  reg [1:0] state;

  // -----------------------------------------------------------
  // Main sequential logic
  // -----------------------------------------------------------
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
    begin
      state     <= IDLE;
      bit_count <= 3'b0;
      clk_count <= 0;
      tx_shift  <= 8'b0;
      rx_shift  <= 8'b0;
      start_d   <= 1'b0;
      mosi      <= 1'b0;
      sck       <= 1'b0;
      cs_n      <= 1'b1;
      busy      <= 1'b0;
      done      <= 1'b0;
      rx_data   <= 8'b0;
    end
    else
    begin
      start_d <= start;

      // done is a single-cycle pulse, clear by default
      done <= 1'b0;

      case (state)
        // -------------------------------------------------------
        // IDLE: Wait for start command
        // -------------------------------------------------------
        IDLE:
        begin
          clk_count <= 0;
          bit_count <= 0;
          sck  <= 1'b0;
          cs_n <= 1'b1;
          busy <= 1'b0;
          mosi <= 1'b0;
          if (start && !start_d)
          begin
            busy  <= 1'b1;
            state <= START;
          end
        end

        // -------------------------------------------------------
        // START: Assert CS, load shift register, setup first bit
        // -------------------------------------------------------
        START:
        begin
          cs_n      <= 1'b0;
          busy  <= 1'b1;       // assert chip select
          tx_shift  <= tx_data;        // latch transmit data
          rx_shift  <= 8'b0;
          bit_count <= 3'b0;
          clk_count <= 0;
          sck       <= 1'b0;
          mosi      <= tx_data[7];     // MSB first: setup bit 7
          state     <= TRANSFER;
        end

        // -------------------------------------------------------
        // TRANSFER: Clock out/in 8 bits using SCK
        // -------------------------------------------------------
        TRANSFER:
        begin
          busy  <= 1'b1;
          if (clk_count == CLK_DIV - 1)
          begin
            clk_count <= 0;

            if (!sck)
            begin
              // --- Rising edge of SCK: sample MISO ---
              sck      <= 1'b1;
              rx_shift <= {rx_shift[6:0], miso};
            end
            else
            begin
              // --- Falling edge of SCK: shift next bit ---
              sck <= 1'b0;

              if (bit_count == 3'd7)
              begin
                // All 8 bits transferred
                state <= STOP;
              end
              else
              begin
                bit_count <= bit_count + 1'b1;
                tx_shift  <= {tx_shift[6:0], 1'b0};
                mosi      <= tx_shift[6]; // next MSB
              end
            end
          end
          else
          begin
            clk_count <= clk_count + 1'b1;
          end
        end

        // -------------------------------------------------------
        // STOP: Deassert CS, output received data, signal done
        // -------------------------------------------------------
        STOP:
        begin
          cs_n    <= 1'b1;
          sck     <= 1'b0;
          mosi    <= 1'b0;
          busy    <= 1'b0;
          done    <= 1'b1;            // pulse done for 1 cycle
          rx_data <= rx_shift;        // latch received data
          state   <= IDLE;
        end

        default:
          state <= IDLE;
      endcase
    end
  end

endmodule
