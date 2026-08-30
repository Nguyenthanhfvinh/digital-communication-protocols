`timescale 1ns/1ps

module tb_uart;

  parameter integer CLK_FREQ   = 100_000_000;
  parameter integer BAUD       = 115200;
  parameter integer FIFO_DEPTH = 16;

  localparam real CLK_PERIOD =
             1_000_000_000.0 / CLK_FREQ;

  localparam real BIT_PERIOD =
             1_000_000_000.0 / BAUD;

  localparam integer TIMEOUT_CYCLES = 200_000;

  reg clk;
  reg rst_n;

  reg  [7:0] tx_data_in;
  reg        tx_wr_en;

  wire       tx_full;
  wire       tx_busy;
  wire       tx_done;
  wire       txd;
  wire       tx_overflow;

  reg        rx_rd_en;

  wire [7:0] rx_data_out;
  wire       rx_empty;
  wire       rx_valid;
  wire       rx_busy;
  wire       frame_error;
  wire       rx_overflow;

  reg rxd_drive;
  reg loopback_en;

  wire rxd;

  integer errors;

  reg frame_error_seen;
  reg frame_error_clear;

  reg [7:0] received_data;

  assign rxd =
         loopback_en ? txd : rxd_drive;

  uart_top #(
             .CLK_FREQ   (CLK_FREQ),
             .BAUD       (BAUD),
             .FIFO_DEPTH (FIFO_DEPTH)
           ) dut (
             .clk          (clk),
             .rst_n        (rst_n),

             .tx_data_in   (tx_data_in),
             .tx_wr_en     (tx_wr_en),
             .tx_full      (tx_full),
             .tx_busy      (tx_busy),
             .tx_done      (tx_done),
             .txd          (txd),

             .rxd           (rxd),

             .rx_data_out   (rx_data_out),
             .rx_rd_en      (rx_rd_en),
             .rx_empty      (rx_empty),
             .rx_valid      (rx_valid),
             .rx_busy       (rx_busy),
             .frame_error   (frame_error),

             .tx_overflow   (tx_overflow),
             .rx_overflow   (rx_overflow)
           );

  // Clock
  initial
  begin
    clk = 1'b0;

    forever
      #(CLK_PERIOD / 2.0)
       clk = ~clk;
  end

  // Capture frame_error pulse
  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      frame_error_seen <= 1'b0;
    else if (frame_error_clear)
      frame_error_seen <= 1'b0;
    else if (frame_error)
      frame_error_seen <= 1'b1;
  end

  // Reset DUT
  task apply_reset;
    begin
      rst_n            = 1'b0;
      tx_data_in       = 8'h00;
      tx_wr_en         = 1'b0;
      rx_rd_en         = 1'b0;
      rxd_drive        = 1'b1;
      loopback_en      = 1'b0;
      frame_error_clear = 1'b0;

      repeat (5)
        @(posedge clk);

      @(negedge clk);
      rst_n = 1'b1;

      repeat (2)
        @(posedge clk);
    end
  endtask

  // Clear captured frame_error
  task clear_frame_error;
    begin
      @(negedge clk);
      frame_error_clear = 1'b1;

      @(negedge clk);
      frame_error_clear = 1'b0;
    end
  endtask

  // Write one byte into TX FIFO
  task write_tx;
    input [7:0] data;

    integer timeout;
    begin
      timeout = 0;

      while (tx_full && timeout < TIMEOUT_CYCLES)
      begin
        @(posedge clk);
        timeout = timeout + 1;
      end

      if (tx_full)
      begin
        $display(
            "ERROR: TX FIFO timeout while writing %h",
            data
          );

        errors = errors + 1;
      end
      else
      begin
        @(negedge clk);

        tx_data_in = data;
        tx_wr_en   = 1'b1;

        @(negedge clk);

        tx_wr_en   = 1'b0;
        tx_data_in = 8'h00;
      end
    end
  endtask

  // Read one byte from RX FIFO
  task read_rx;
    output [7:0] data;

    integer timeout;
    begin
      timeout = 0;
      data    = 8'hXX;

      while (rx_empty && timeout < TIMEOUT_CYCLES)
      begin
        @(posedge clk);
        timeout = timeout + 1;
      end

      if (rx_empty)
      begin
        $display("ERROR: RX FIFO timeout");
        errors = errors + 1;
      end
      else
      begin
        data = rx_data_out;

        @(negedge clk);
        rx_rd_en = 1'b1;

        @(negedge clk);
        rx_rd_en = 1'b0;
      end
    end
  endtask

  // Send asynchronous UART frame into RXD
  task send_rx_byte;
    input [7:0] data;
    input       stop_bit;

    integer i;
    begin
      loopback_en = 1'b0;

      // Begin away from DUT clock edge
      @(negedge clk);
      #(CLK_PERIOD / 4.0);

      // Idle
      rxd_drive = 1'b1;
      #(BIT_PERIOD);

      // Start bit
      rxd_drive = 1'b0;
      #(BIT_PERIOD);

      // Data bits, LSB first
      for (i = 0; i < 8; i = i + 1)
      begin
        rxd_drive = data[i];
        #(BIT_PERIOD);
      end

      // Stop bit
      rxd_drive = stop_bit;
      #(BIT_PERIOD);

      // Return to idle
      rxd_drive = 1'b1;
    end
  endtask

  initial
  begin

    errors            = 0;

    clk               = 1'b0;
    rst_n             = 1'b0;

    tx_data_in        = 8'h00;
    tx_wr_en          = 1'b0;

    rx_rd_en          = 1'b0;

    rxd_drive         = 1'b1;
    loopback_en       = 1'b0;

    frame_error_clear = 1'b0;

    apply_reset();


    // Test 1: Reset
    if (txd !== 1'b1)
    begin
      $display(
          "TEST 1 FAIL: TXD is not HIGH after reset"
        );

      errors = errors + 1;
    end
    else if (rx_empty !== 1'b1)
    begin
      $display(
          "TEST 1 FAIL: RX FIFO is not empty"
        );

      errors = errors + 1;
    end
    else
    begin
      $display("TEST 1 PASS: Reset");
    end


    // Test 2: Single-byte loopback
    loopback_en = 1'b1;

    write_tx(8'hA5);
    read_rx(received_data);

    if (received_data !== 8'hA5)
    begin
      $display(
          "TEST 2 FAIL: expected A5, received %h",
          received_data
        );

      errors = errors + 1;
    end
    else
    begin
      $display(
          "TEST 2 PASS: Loopback A5"
        );
    end


    // Test 3: Multiple bytes
    write_tx(8'h12);
    write_tx(8'h34);
    write_tx(8'h56);
    write_tx(8'h78);

    read_rx(received_data);

    if (received_data !== 8'h12)
    begin
      $display(
          "TEST 3 FAIL: expected 12, received %h",
          received_data
        );

      errors = errors + 1;
    end

    read_rx(received_data);

    if (received_data !== 8'h34)
    begin
      $display(
          "TEST 3 FAIL: expected 34, received %h",
          received_data
        );

      errors = errors + 1;
    end

    read_rx(received_data);

    if (received_data !== 8'h56)
    begin
      $display(
          "TEST 3 FAIL: expected 56, received %h",
          received_data
        );

      errors = errors + 1;
    end

    read_rx(received_data);

    if (received_data !== 8'h78)
    begin
      $display(
          "TEST 3 FAIL: expected 78, received %h",
          received_data
        );

      errors = errors + 1;
    end


    // Test 4: External RX frame
    loopback_en = 1'b0;

    send_rx_byte(
        8'h5A,
        1'b1
      );

    read_rx(received_data);

    if (received_data !== 8'h5A)
    begin
      $display(
          "TEST 4 FAIL: expected 5A, received %h",
          received_data
        );

      errors = errors + 1;
    end
    else
    begin
      $display(
          "TEST 4 PASS: External RX"
        );
    end


    // Test 5: Invalid stop bit
    clear_frame_error();

    send_rx_byte(
        8'hC3,
        1'b0
      );

    repeat (20)
      @(posedge clk);

    if (!frame_error_seen)
    begin
      $display(
          "TEST 5 FAIL: frame_error was not detected"
        );

      errors = errors + 1;
    end
    else
    begin
      $display(
          "TEST 5 PASS: Framing error detected"
        );
    end

    // Invalid frame must not enter RX FIFO
    if (!rx_empty)
    begin
      $display(
          "TEST 5 FAIL: invalid byte entered RX FIFO"
        );

      errors = errors + 1;
    end


    // Final result
    if (errors == 0)
    begin
      $display("");
      $display("ALL TESTS PASSED");
    end
    else
    begin
      $display("");
      $display(
          "TEST FAILED: %0d error(s)",
          errors
        );
    end

    #(BIT_PERIOD * 2);

    $finish;
  end

endmodule
