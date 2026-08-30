module uart_top #(
    parameter integer CLK_FREQ   = 100_000_000,
    parameter integer BAUD       = 115200,
    parameter integer FIFO_DEPTH = 16
  )(
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] tx_data_in,
    input  wire       tx_wr_en,
    output wire       tx_full,
    output wire       tx_busy,
    output wire       tx_done,
    output wire       txd,

    input  wire       rxd,

    output wire [7:0] rx_data_out,
    input  wire       rx_rd_en,
    output wire       rx_empty,
    output wire       rx_valid,
    output wire       rx_busy,
    output wire       frame_error,

    output wire       tx_overflow,
    output wire       rx_overflow
  );

  // TX FIFO signals
  wire [7:0] tx_fifo_data;
  wire       tx_fifo_empty;
  wire       tx_fifo_pop;
  wire       tx_fifo_underflow;

  // TX handshake signals
  wire tx_valid;
  wire tx_ready;

  // RX signals
  wire [7:0] rx_byte;
  wire       rx_byte_valid;

  // RX FIFO signals
  wire rx_fifo_full;
  wire rx_fifo_underflow;

  // TX FIFO has data available
  assign tx_valid = !tx_fifo_empty;

  // Remove one byte when UART TX accepts it
  assign tx_fifo_pop =
         tx_valid && tx_ready;

  // RX data is available when RX FIFO is not empty
  assign rx_valid = !rx_empty;

  // TX FIFO
  fifo_sync #(
              .DATA_WIDTH (8),
              .FIFO_DEPTH (FIFO_DEPTH)
            ) u_tx_fifo (
              .clk       (clk),
              .rst_n     (rst_n),

              .wr_en     (tx_wr_en),
              .rd_en     (tx_fifo_pop),

              .data_in   (tx_data_in),
              .data_out  (tx_fifo_data),

              .full      (tx_full),
              .empty     (tx_fifo_empty),

              .overflow  (tx_overflow),
              .underflow (tx_fifo_underflow)
            );

  // UART transmitter
  uart_tx #(
            .CLK_FREQ (CLK_FREQ),
            .BAUD     (BAUD)
          ) u_uart_tx (
            .clk      (clk),
            .rst_n    (rst_n),

            .tx_valid (tx_valid),
            .tx_ready (tx_ready),
            .tx_data  (tx_fifo_data),

            .tx_busy  (tx_busy),
            .tx_done  (tx_done),
            .txd      (txd)
          );

  // UART receiver
  uart_rx #(
            .CLK_FREQ   (CLK_FREQ),
            .BAUD       (BAUD),
            .OVERSAMPLE (8)
          ) u_uart_rx (
            .clk         (clk),
            .rst_n       (rst_n),
            .rxd         (rxd),

            .rx_data     (rx_byte),
            .rx_valid    (rx_byte_valid),
            .rx_busy     (rx_busy),
            .frame_error (frame_error)
          );

  // RX FIFO
  fifo_sync #(
              .DATA_WIDTH (8),
              .FIFO_DEPTH (FIFO_DEPTH)
            ) u_rx_fifo (
              .clk       (clk),
              .rst_n     (rst_n),

              .wr_en     (rx_byte_valid),
              .rd_en     (rx_rd_en),

              .data_in   (rx_byte),
              .data_out  (rx_data_out),

              .full      (rx_fifo_full),
              .empty     (rx_empty),

              .overflow  (rx_overflow),
              .underflow (rx_fifo_underflow)
            );

endmodule
