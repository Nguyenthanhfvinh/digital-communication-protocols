module uart_rx #(
    parameter integer CLK_FREQ   = 100_000_000,
    parameter integer BAUD       = 115200,
    parameter integer OVERSAMPLE = 8
  )(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rxd,

    output reg  [7:0] rx_data,
    output reg        rx_valid,
    output reg        rx_busy,
    output reg        frame_error
  );

  localparam [1:0] IDLE  = 2'd0;
  localparam [1:0] START = 2'd1;
  localparam [1:0] DATA  = 2'd2;
  localparam [1:0] STOP  = 2'd3;

  localparam integer PHASE_WIDTH =
             (OVERSAMPLE <= 2) ? 1 : $clog2(OVERSAMPLE);

  localparam integer MID      = OVERSAMPLE / 2;
  localparam integer SAMPLE_A = MID - 2;
  localparam integer SAMPLE_B = MID - 1;
  localparam integer SAMPLE_C = MID;

  reg [1:0] state;
  reg [2:0] bit_idx;
  reg [7:0] shift_reg;

  reg [PHASE_WIDTH-1:0] phase;
  reg [1:0] sample_ones;

  reg stop_bit_valid;
  reg stop_sampled;

  reg rxd_meta;
  reg rxd_sync;
  reg rxd_sync_d;

  wire sample_tick;
  wire start_detect;
  wire sample_restart;
  wire sample_enable;
  wire majority_bit;

  assign sample_restart = start_detect;

  assign sample_enable =
         (state != IDLE) || start_detect;

  assign majority_bit =
         ((sample_ones + rxd_sync) >= 2);


  wire falling_edge;

  assign falling_edge =
         rxd_sync_d && !rxd_sync;

  assign start_detect =
         (state == IDLE) && falling_edge;

  baud_gen #(
             .CLK_FREQ  (CLK_FREQ),
             .TICK_RATE (BAUD * OVERSAMPLE)
           ) u_rx_sample_baud (
             .clk     (clk),
             .rst_n   (rst_n),
             .enable  (sample_enable),
             .restart (sample_restart),
             .tick    (sample_tick)
           );

  // Synchronize RXD
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
    begin
      rxd_meta   <= 1'b1;
      rxd_sync   <= 1'b1;
      rxd_sync_d <= 1'b1;
    end
    else
    begin
      rxd_meta   <= rxd;
      rxd_sync   <= rxd_meta;
      rxd_sync_d <= rxd_sync;
    end
  end

  // RX FSM
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
    begin
      state          <= IDLE;
      bit_idx        <= 3'd0;
      shift_reg      <= 8'h00;

      phase          <= {PHASE_WIDTH{1'b0}};
      sample_ones    <= 2'd0;

      stop_bit_valid <= 1'b0;
      stop_sampled   <= 1'b0;

      rx_data        <= 8'h00;
      rx_valid       <= 1'b0;
      rx_busy        <= 1'b0;
      frame_error    <= 1'b0;
    end
    else
    begin
      rx_valid    <= 1'b0;
      frame_error <= 1'b0;

      case (state)

        IDLE:
        begin
          rx_busy        <= 1'b0;
          bit_idx        <= 3'd0;
          phase          <= {PHASE_WIDTH{1'b0}};
          sample_ones    <= 2'd0;
          stop_bit_valid <= 1'b0;
          stop_sampled   <= 1'b0;

          if (start_detect)
          begin
            rx_busy <= 1'b1;
            state   <= START;
          end
        end

        START:
        begin
          rx_busy <= 1'b1;

          if (sample_tick)
          begin
            if (phase == OVERSAMPLE - 1)
              phase <= {PHASE_WIDTH{1'b0}};
            else
              phase <= phase + 1'b1;

            if ((phase == SAMPLE_A) ||
                (phase == SAMPLE_B))
            begin

              sample_ones <=
              sample_ones + rxd_sync;
            end

            else if (phase == SAMPLE_C)
            begin
              sample_ones <= 2'd0;

              if (!majority_bit)
              begin
                bit_idx <= 3'd0;
                state   <= DATA;
              end
              else
              begin
                rx_busy <= 1'b0;
                state   <= IDLE;
              end
            end
          end
        end

        DATA:
        begin
          rx_busy <= 1'b1;

          if (sample_tick)
          begin
            if (phase == OVERSAMPLE - 1)
              phase <= {PHASE_WIDTH{1'b0}};
            else
              phase <= phase + 1'b1;

            if ((phase == SAMPLE_A) ||
                (phase == SAMPLE_B))
            begin

              sample_ones <=
              sample_ones + rxd_sync;
            end

            else if (phase == SAMPLE_C)
            begin
              sample_ones <= 2'd0;

              shift_reg <= {
                majority_bit,
                shift_reg[7:1]
              };

              if (bit_idx == 3'd7)
              begin
                bit_idx        <= 3'd0;
                stop_bit_valid <= 1'b0;
                stop_sampled   <= 1'b0;
                state          <= STOP;
              end
              else
              begin
                bit_idx <= bit_idx + 1'b1;
              end
            end
          end
        end

        STOP:
        begin
          rx_busy <= 1'b1;

          if (sample_tick)
          begin

            if ((phase == SAMPLE_A) ||
                (phase == SAMPLE_B))
            begin

              sample_ones <=
              sample_ones + rxd_sync;
            end

            else if (phase == SAMPLE_C)
            begin
              sample_ones    <= 2'd0;
              stop_bit_valid <= majority_bit;
              stop_sampled   <= 1'b1;
            end

            if (phase == OVERSAMPLE - 1)
            begin
              phase <= {PHASE_WIDTH{1'b0}};

              if (stop_sampled)
              begin

                if (stop_bit_valid)
                begin
                  rx_data  <= shift_reg;
                  rx_valid <= 1'b1;

                  // Back-to-back frame
                  if (rxd_sync == 1'b0)
                  begin
                    rx_busy     <= 1'b1;
                    bit_idx     <= 3'd0;
                    sample_ones <= 2'd0;
                    state       <= START;
                  end
                  else
                  begin
                    rx_busy <= 1'b0;
                    state   <= IDLE;
                  end
                end
                else
                begin
                  frame_error <= 1'b1;
                  rx_busy     <= 1'b0;
                  state       <= IDLE;
                end

                stop_bit_valid <= 1'b0;
                stop_sampled   <= 1'b0;
              end
            end
            else
            begin
              phase <= phase + 1'b1;
            end
          end
        end

        default:
        begin
          state          <= IDLE;
          bit_idx        <= 3'd0;
          shift_reg      <= 8'h00;

          phase          <= {PHASE_WIDTH{1'b0}};
          sample_ones    <= 2'd0;

          stop_bit_valid <= 1'b0;
          stop_sampled   <= 1'b0;

          rx_busy        <= 1'b0;
          rx_valid       <= 1'b0;
          frame_error    <= 1'b0;
        end

      endcase
    end
  end

endmodule
