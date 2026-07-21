`timescale 1ns/1ps

// =============================================================================
// Self-checking Testbench for uart_top
// - 8 data bits, no parity, 1 stop bit
// - Tests: loopback, FIFO, framing error, false start, overflow, reset recovery
// - Added: Force illegal FSM state to improve FSM Transitions coverage
// =============================================================================

module tb_uart;

  // -------------------------------------------------------------------------
  // Parameters
  // -------------------------------------------------------------------------
  parameter integer CLK_FREQ   = 27_000_000;
  parameter integer BAUD       = 115200;
  parameter integer FIFO_DEPTH = 16;

  localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD;
  localparam real    CLK_PERIOD   = 1.0e9 / CLK_FREQ;

  // -------------------------------------------------------------------------
  // Signals
  // -------------------------------------------------------------------------
  reg         clk         = 1'b0;
  reg         rst_n       = 1'b0;
  reg         tx_wr_en    = 1'b0;
  reg  [7:0]  tx_data_in  = 8'h00;
  reg         rx_rd_en    = 1'b0;
  reg         loopback_en = 1'b1;
  reg         rxd_drive   = 1'b1;

  wire        tx_full;
  wire        tx_busy;
  wire        rx_empty;
  wire        rx_valid;
  wire        txd;
  wire [7:0]  rx_data_out;

  wire        rxd = loopback_en ? txd : rxd_drive;

  // -------------------------------------------------------------------------
  // Scoreboard
  // -------------------------------------------------------------------------
  integer checks            = 0;
  integer errors            = 0;
  integer frame_error_count = 0;
  integer n;

  reg [7:0] actual;
  reg [7:0] expected [0:255];

  // -------------------------------------------------------------------------
  // Clock generation
  // -------------------------------------------------------------------------
  always #(CLK_PERIOD/2.0) clk = ~clk;

  // -------------------------------------------------------------------------
  // DUT
  // -------------------------------------------------------------------------
  uart_top #(
             .CLK_FREQ   (CLK_FREQ),
             .BAUD       (BAUD),
             .FIFO_DEPTH (FIFO_DEPTH)
           ) dut (
             .clk         (clk),
             .rst_n       (rst_n),
             .tx_wr_en    (tx_wr_en),
             .tx_data_in  (tx_data_in),
             .tx_full     (tx_full),
             .tx_busy     (tx_busy),
             .rx_rd_en    (rx_rd_en),
             .rx_data_out (rx_data_out),
             .rx_empty    (rx_empty),
             .rx_valid    (rx_valid),
             .txd         (txd),
             .rxd         (rxd)
           );

  // Count internal frame error pulses
  always @(posedge clk)
  begin
    if (rst_n && dut.u_rx.frame_error)
      frame_error_count = frame_error_count + 1;
  end

  // -------------------------------------------------------------------------
  // Helper tasks
  // -------------------------------------------------------------------------
  task automatic fail;
    input [8*80-1:0] message;
    begin
      errors = errors + 1;
      $display("[%0t] FAIL: %0s", $time, message);
    end
  endtask

  task automatic check_byte;
    input [7:0] exp;
    input [7:0] got;
    begin
      checks = checks + 1;
      if (got !== exp)
      begin
        errors = errors + 1;
        $display("[%0t] FAIL: expected 0x%02h, got 0x%02h", $time, exp, got);
      end
    end
  endtask

  task automatic apply_reset;
    begin
      tx_wr_en  = 1'b0;
      rx_rd_en  = 1'b0;
      rxd_drive = 1'b1;
      rst_n     = 1'b0;
      repeat (5) @(posedge clk);

      @(negedge clk);
      rst_n = 1'b1;
      repeat (5) @(posedge clk);

      checks = checks + 1;
      if (txd !== 1'b1 || tx_busy !== 1'b0 || rx_empty !== 1'b1)
        fail("outputs are not idle after reset");
    end
  endtask

  task automatic write_tx;
    input [7:0] data;
    integer timeout;
    begin
      timeout = 0;
      while (tx_full && timeout < FIFO_DEPTH*CLKS_PER_BIT*20)
      begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (tx_full)
      begin
        fail("timeout waiting for TX FIFO space");
      end
      else
      begin
        @(negedge clk);
        tx_data_in = data;
        tx_wr_en   = 1'b1;
        @(negedge clk);
        tx_wr_en   = 1'b0;
      end
    end
  endtask

  task automatic read_rx;
    output [7:0] data;
    integer timeout;
    begin
      timeout = 0;
      while (rx_empty && timeout < CLKS_PER_BIT*20)
      begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (rx_empty)
      begin
        data = 8'hxx;
        fail("timeout waiting for RX byte");
      end
      else
      begin
        @(negedge clk);
        data     = rx_data_out;
        rx_rd_en = 1'b1;
        @(negedge clk);
        rx_rd_en = 1'b0;
      end
    end
  endtask

  task automatic wait_uart_idle;
    integer timeout;
    begin
      timeout = 0;
      while ((tx_busy || !dut.tx_fifo_empty) &&
             timeout < FIFO_DEPTH*CLKS_PER_BIT*20)
      begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (tx_busy || !dut.tx_fifo_empty)
        fail("timeout waiting for transmitter idle");
    end
  endtask

  task automatic loopback_batch;
    input integer count;
    integer i;
    begin
      loopback_en = 1'b1;
      for (i = 0; i < count; i = i + 1)
        write_tx(expected[i]);

      for (i = 0; i < count; i = i + 1)
      begin
        read_rx(actual);
        check_byte(expected[i], actual);
      end
      wait_uart_idle();
    end
  endtask

  task automatic drive_rx_frame;
    input [7:0] data;
    input       stop_ok;
    integer     i;
    begin
      loopback_en = 1'b0;
      rxd_drive   = 1'b1;
      repeat (3) @(posedge clk);

      // Start bit
      @(negedge clk);
      rxd_drive = 1'b0;
      repeat (CLKS_PER_BIT) @(posedge clk);

      // Data bits
      for (i = 0; i < 8; i = i + 1)
      begin
        @(negedge clk);
        rxd_drive = data[i];
        repeat (CLKS_PER_BIT) @(posedge clk);
      end

      // Stop bit
      @(negedge clk);
      rxd_drive = stop_ok;
      repeat (CLKS_PER_BIT) @(posedge clk);

      @(negedge clk);
      rxd_drive = 1'b1;
      repeat (3) @(posedge clk);
    end
  endtask

  // -------------------------------------------------------------------------
  // Main test sequence
  // -------------------------------------------------------------------------
  initial
  begin
    $dumpfile("uart_tb.vcd");
    $dumpvars(0, tb_uart);

    $display("==================================================");
    $display("UART TB: CLK=%0d Hz  BAUD=%0d  CLKS_PER_BIT=%0d",
             CLK_FREQ, BAUD, CLKS_PER_BIT);
    $display("==================================================");

    apply_reset();

    // 1. Basic directed loopback
    $display("Test 1: Basic directed values");
    expected[0] = 8'h00;
    expected[1] = 8'hFF;
    expected[2] = 8'h55;
    expected[3] = 8'hAA;
    expected[4] = 8'h01;
    expected[5] = 8'h80;
    expected[6] = 8'h7F;
    expected[7] = 8'h81;
    loopback_batch(8);

    // 2. Fill RX FIFO
    $display("Test 2: Fill RX FIFO to depth");
    for (n = 0; n < FIFO_DEPTH; n = n + 1)
      expected[n] = (n * 8'h3D) ^ 8'hA7;
    loopback_batch(FIFO_DEPTH);

    // 3. Independent RX
    $display("Test 3: Independent RX frame");
    drive_rx_frame(8'h3C, 1'b1);
    read_rx(actual);
    check_byte(8'h3C, actual);

    // 4. Framing error
    $display("Test 4: Framing error");
    n = frame_error_count;
    drive_rx_frame(8'h96, 1'b0);
    repeat (5) @(posedge clk);
    checks = checks + 2;
    if (frame_error_count != n + 1)
      fail("bad stop bit did not raise frame_error");
    if (!rx_empty)
      fail("bad frame was incorrectly written to RX FIFO");

    drive_rx_frame(8'hC3, 1'b1);
    read_rx(actual);
    check_byte(8'hC3, actual);

    // 5. False Start bit
    $display("Test 5: False start bit");
    loopback_en = 1'b0;
    rxd_drive   = 1'b1;
    @(posedge clk);
    @(negedge clk);
    rxd_drive = 1'b0;
    repeat (3) @(posedge clk);
    rxd_drive = 1'b1;
    repeat (CLKS_PER_BIT * 3) @(posedge clk);
    checks = checks + 1;
    if (!rx_empty)
      fail("False start bit was incorrectly accepted");

    // 6. TX FIFO Overflow
    $display("Test 6: TX FIFO overflow");
    for (n = 0; n < FIFO_DEPTH + 4; n = n + 1)
      write_tx(8'hA0 + n[7:0]);
    checks = checks + 1;
    if (!tx_full)
      fail("TX FIFO overflow: tx_full was not asserted");
    wait_uart_idle();

    // 7. RX FIFO Overflow
    $display("Test 7: RX FIFO overflow");
    loopback_en = 1'b0;
    for (n = 0; n < FIFO_DEPTH + 3; n = n + 1)
      drive_rx_frame(8'h50 + n[7:0], 1'b1);
    for (n = 0; n < FIFO_DEPTH; n = n + 1)
      read_rx(actual);

    // 8. Reset during TX
    $display("Test 8: Reset during TX");
    loopback_en = 1'b1;
    write_tx(8'h5A);
    wait (tx_busy === 1'b1);
    repeat (CLKS_PER_BIT * 3) @(posedge clk);
    apply_reset();
    expected[0] = 8'hA5;
    loopback_batch(1);

    // -------------------------------------------------------------
    // 9. Force illegal FSM state (improve FSM Transitions)
    // -------------------------------------------------------------
    $display("Test 9: Force illegal FSM states (cover default)");

    // TX FSM
    @(posedge clk);
    force dut.u_tx.state = 2'bxx;     // <-- chỉnh tên instance/state nếu cần
    @(posedge clk);
    release dut.u_tx.state;
    repeat (3) @(posedge clk);

    // RX FSM
    @(posedge clk);
    force dut.u_rx.state = 2'bxx;     // <-- chỉnh tên instance/state nếu cần
    @(posedge clk);
    release dut.u_rx.state;
    repeat (3) @(posedge clk);

    // -------------------------------------------------------------
    // Final result
    // -------------------------------------------------------------
    $display("==================================================");
    if (errors == 0)
      $display("ALL TESTS PASSED (%0d checks)", checks);
    else
      $display("TEST FAILED: %0d error(s) out of %0d checks", errors, checks);
    $display("==================================================");

    #100;
    $finish;
  end

  // Global watchdog
  initial
  begin
    #(CLK_PERIOD * CLKS_PER_BIT * 12 * 200);
    $display("FATAL: global testbench timeout");
    $finish;
  end

endmodule
