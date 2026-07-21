module uart_top #(
    parameter CLK_FREQ     = 27_000_000,
    parameter BAUD         = 115200,
    parameter CLKS_PER_BIT = CLK_FREQ / BAUD,
    parameter FIFO_DEPTH   = 16
)(
    input  wire       clk,
    input  wire       rst_n,

    // TX interface
    input  wire       tx_wr_en,
    input  wire [7:0] tx_data_in,
    output wire       tx_full,
    output wire       tx_busy,

    // RX interface
    input  wire       rx_rd_en,
    output wire [7:0] rx_data_out,
    output wire       rx_empty,
    output wire       rx_valid,

    // Pins
    output wire       txd,
    input  wire       rxd
);

    wire       tx_start;
    wire [7:0] tx_data_from_fifo;
    wire       tx_fifo_empty;
    wire [7:0] rx_data_from_uart;
    wire       rx_valid_from_uart;
    wire       rx_busy;
    wire       frame_error;
    wire       tx_done;

    //---------------- TX FIFO ----------------
    fifo_sync #(
        .data_width (8),
        .fifo_depth (FIFO_DEPTH)
    ) u_tx_fifo (
        .clk      (clk),
        .rst      (rst_n),
        .wr_en    (tx_wr_en),
        .rd_en    (tx_start),
        .data_in  (tx_data_in),
        .data_out (tx_data_from_fifo),
        .full     (tx_full),
        .empty    (tx_fifo_empty)
    );

    assign tx_start = !tx_fifo_empty && !tx_busy;

    //---------------- UART TX (PISO) ----------------
    uart_tx #(
        .CLKS_PER_BIT (CLKS_PER_BIT)
    ) u_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_data  (tx_data_from_fifo),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done),
        .txd      (txd)
    );

    //---------------- UART RX (SIPO) ----------------
    uart_rx #(
        .CLKS_PER_BIT (CLKS_PER_BIT)
    ) u_rx (
        .clk         (clk),
        .rst_n       (rst_n),
        .rxd         (rxd),
        .rx_data     (rx_data_from_uart),
        .rx_valid    (rx_valid_from_uart),
        .rx_busy     (rx_busy),
        .frame_error (frame_error)
    );

    //---------------- RX FIFO ----------------
    fifo_sync #(
        .data_width (8),
        .fifo_depth (FIFO_DEPTH)
    ) u_rx_fifo (
        .clk      (clk),
        .rst      (rst_n),
        .wr_en    (rx_valid_from_uart),
        .rd_en    (rx_rd_en),
        .data_in  (rx_data_from_uart),
        .data_out (rx_data_out),
        .full     (),
        .empty    (rx_empty)
    );

    assign rx_valid = rx_valid_from_uart;

endmodule