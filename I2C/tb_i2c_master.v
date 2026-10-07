`timescale 1ns / 1ps

module tb_i2c_master;

    // Parameters
    parameter SYS_CLK_FREQ = 50_000_000;
    parameter I2C_FREQ     = 100_000;
    parameter DEBUG        = 0;
    parameter EXHAUSTIVE   = 1;

    // DUT signals
    reg         clk;
    reg         rst;
    reg         start;
    reg         rw;
    reg  [6:0]  addr;
    reg  [7:0]  data_in;

    wire [7:0]  data_out;
    wire        busy;
    wire        ack_error;

    wire scl;
    wire sda;

    // Pull-ups
    pullup (scl);
    pullup (sda);

    // Slave Model
    reg sda_drive_en;
    reg sda_drive_val;

    assign sda = (sda_drive_en && !sda_drive_val) ? 1'b0 : 1'bz;
    reg stretch_scl;
    assign scl = stretch_scl ? 1'b0 : 1'bz;

    reg        slave_ack_addr;
    reg        slave_ack_data;
    reg [7:0]  slave_data;

    integer scl_edges;
    reg [7:0] captured_addr;
    reg [7:0] captured_data;
    integer data_bits;
    integer bus_clocks;
    integer start_count;
    reg stop_seen;

    // Observe the bus independently of the master's data registers.
    always @(posedge busy) begin
        captured_addr = 0;
        captured_data = 0;
        data_bits = 0;
        bus_clocks = 0;
        start_count = 0;
        stop_seen = 0;
    end

    always @(posedge scl) begin
        if (busy && !rst) begin
            bus_clocks = bus_clocks + 1;
            if (scl_edges >= 1 && scl_edges <= 8)
                captured_addr = {captured_addr[6:0], sda};
            else if (scl_edges >= 10 && scl_edges <= 17 && slave_ack_addr) begin
                captured_data = {captured_data[6:0], sda};
                data_bits = data_bits + 1;
            end
            else if (scl_edges == 18 && rw && slave_ack_addr && sda !== 1'b1)
                $fatal(1, "Master did not send NACK after its single-byte read");
        end
    end

    always @(posedge sda)
        if (busy && !rst && scl === 1'b1)
            stop_seen = 1;

    always @(negedge sda)
        if (busy && !rst && scl === 1'b1)
            start_count = start_count + 1;

    // DUT Instantiation
    i2c_master #(
        .SYS_CLK_FREQ(SYS_CLK_FREQ),
        .I2C_FREQ(I2C_FREQ)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .rw(rw),
        .addr(addr),
        .data_in(data_in),
        .data_out(data_out),
        .busy(busy),
        .ack_error(ack_error),
        .scl(scl),
        .sda(sda)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #10 clk = ~clk; // 50 MHz
    end

    // Debug Monitor
    reg [3:0] prev_state;
    reg [1:0] prev_phase;
    reg [2:0] prev_bit;

    initial begin
        prev_state = 4'hF;
        prev_phase = 2'h3;
        prev_bit   = 3'h7;
    end

    always @(posedge clk) begin
        if (DEBUG && (dut.state   != prev_state ||
            dut.phase   != prev_phase ||
            dut.bit_cnt != prev_bit)) begin

            $display("[%0t] state=%0d phase=%0d bit=%0d busy=%b scl=%b sda=%b ack=%b",
                     $time,
                     dut.state,
                     dut.phase,
                     dut.bit_cnt,
                     busy,
                     scl,
                     sda,
                     ack_error);

            prev_state <= dut.state;
            prev_phase <= dut.phase;
            prev_bit   <= dut.bit_cnt;
        end
    end

    // Slave Behavior
    always @(negedge scl or negedge busy) begin

        if (!busy) begin
            scl_edges     = 0;
            sda_drive_en  = 0;
            sda_drive_val = 1'b1;
        end
        else begin

            // Address bits
            if (scl_edges <= 7) begin
                sda_drive_en = 0;
            end

            // Address ACK
            else if (scl_edges == 8) begin
                sda_drive_en  = 1;
                sda_drive_val = slave_ack_addr ? 1'b0 : 1'b1;
            end

            // Data phase
            else if (scl_edges >= 9 && scl_edges <= 16 && slave_ack_addr) begin

                if (rw) begin
                    sda_drive_en  = 1;
                    sda_drive_val = slave_data[16 - scl_edges];
                end
                else begin
                    sda_drive_en = 0;
                end
            end

            // Data ACK
            else if (scl_edges == 17 && slave_ack_addr) begin

                if (!rw) begin
                    sda_drive_en  = 1;
                    sda_drive_val = slave_ack_data ? 1'b0 : 1'b1;
                end
                else begin
                    sda_drive_en = 0;
                end
            end

            else begin
                sda_drive_en = 0;
            end

            scl_edges = scl_edges + 1;
        end
    end

    // Tasks
    task reset_dut;
    begin
        $display("\n==== RESET DUT ====");

        rst   = 1;
        start = 0;

        repeat (5) @(negedge clk);

        rst = 0;

        repeat (5) @(posedge clk);

        $display("==== RESET DONE ====\n");
    end
    endtask


    task wait_done;
    begin
        fork
            begin
                wait (busy == 1'b0);
                $display("[%0t] Transaction finished", $time);
            end

            begin
                #2ms;

                $fatal(1, "TIMEOUT: state=%0d phase=%0d busy=%b scl=%b sda=%b",
                       dut.state, dut.phase, busy, scl, sda);
            end
        join_any

        disable fork;
    end
    endtask


    task pulse_start;
    begin
        @(posedge clk);
        start <= 1'b1;

        @(posedge clk);
        start <= 1'b0;
    end
    endtask


    task do_write;
        input [6:0] t_addr;
        input [7:0] t_data;
        input       a_ack;
        input       d_ack;
        input integer tc;
    begin

        $display("[TC%0d] WRITE addr=%02h data=%02h", tc, t_addr, t_data);


        addr           = t_addr;
        data_in        = t_data;
        rw             = 0;
        slave_ack_addr = a_ack;
        slave_ack_data = d_ack;

        pulse_start();

        wait (busy == 1'b1);

        wait_done();

        if (start_count != 1 || !stop_seen || scl !== 1'b1 || sda !== 1'b1)
            $fatal(1, "[TC%0d] Missing STOP or bus not released", tc);
        if (captured_addr !== {t_addr, 1'b0})
            $fatal(1, "[TC%0d] Incorrect write address on bus: %02h", tc, captured_addr);
        if (a_ack && (data_bits != 8 || captured_data !== t_data))
            $fatal(1, "[TC%0d] Incorrect write data on bus: %02h (%0d bits)",
                   tc, captured_data, data_bits);
        if (!a_ack && data_bits != 0)
            $fatal(1, "[TC%0d] Data transmitted after address NACK", tc);
        if (bus_clocks != (a_ack ? 19 : 10))
            $fatal(1, "[TC%0d] Incorrect transaction length: %0d clocks", tc, bus_clocks);

        if (ack_error !== ~(a_ack & d_ack)) begin
            $fatal(1, "[TC%0d] FAIL: ack_error=%b expected=%b",
                    tc, ack_error, ~(a_ack & d_ack));
        end
        else begin
            $display("[TC%0d] PASS", tc);
        end

        repeat (5) @(posedge clk);
    end
    endtask


    task do_read;
        input [6:0] t_addr;
        input [7:0] t_slave_data;
        input       a_ack;
        input integer tc;
    begin
        $display("[TC%0d] READ addr=%02h expect=%02h", tc, t_addr, t_slave_data);


        addr           = t_addr;
        rw             = 1;
        slave_ack_addr = a_ack;
        slave_data     = t_slave_data;

        pulse_start();

        wait (busy == 1'b1);

        wait_done();

        if (start_count != 1 || !stop_seen || scl !== 1'b1 || sda !== 1'b1)
            $fatal(1, "[TC%0d] Missing STOP or bus not released", tc);
        if (captured_addr !== {t_addr, 1'b1})
            $fatal(1, "[TC%0d] Incorrect read address on bus: %02h", tc, captured_addr);
        if (data_bits != (a_ack ? 8 : 0))
            $fatal(1, "[TC%0d] Incorrect read length: %0d bits", tc, data_bits);
        if (bus_clocks != (a_ack ? 19 : 10))
            $fatal(1, "[TC%0d] Incorrect transaction length: %0d clocks", tc, bus_clocks);

        if (a_ack) begin

            if (ack_error) begin
                $fatal(1, "[TC%0d] FAIL: Unexpected ACK error", tc);
            end
            else if (data_out !== t_slave_data) begin
                $fatal(1, "[TC%0d] FAIL: recv=%02h expected=%02h",
                        tc, data_out, t_slave_data);
            end
            else begin
                $display("[TC%0d] PASS", tc);
            end
        end
        else begin

            if (!ack_error) begin
                $fatal(1, "[TC%0d] FAIL: Expected ACK error", tc);
            end
            else begin
                $display("[TC%0d] PASS (NACK detected)", tc);
            end
        end

        repeat (5) @(posedge clk);
    end
    endtask

    task hold_scl_low;
        input integer edge_index;
        integer clocks_before;
        reg sda_before;
    begin
        // Start while SCL is already low: stretching must not introduce
        // an artificial falling edge into the slave's bit counter.
        wait (scl_edges == edge_index);
        @(negedge scl);
        stretch_scl = 1'b1;
        wait (dut.scl_out == 1'b1);
        @(negedge clk);
        clocks_before = bus_clocks;
        sda_before = sda;
        #20us;
        if (!busy || scl !== 1'b0 || bus_clocks != clocks_before || sda !== sda_before)
            $fatal(1, "Master advanced its transaction while slave stretched SCL");
        // Release away from the system clock edge to exercise divider restart.
        #7;
        stretch_scl = 1'b0;
    end
    endtask

    integer i;

    // Main Test
    initial begin

        rst             = 1;
        start           = 0;
        rw              = 0;
        addr            = 0;
        data_in         = 0;
        slave_ack_addr  = 1;
        slave_ack_data  = 1;
        slave_data      = 8'h3C;
        sda_drive_en    = 0;
        sda_drive_val   = 1'b1;
        stretch_scl     = 0;
        scl_edges       = 0;
        captured_addr   = 0;
        captured_data   = 0;
        data_bits       = 0;
        bus_clocks      = 0;
        start_count     = 0;
        stop_seen       = 0;

        reset_dut();

        // Basic
        do_write(7'h50, 8'hA5, 1, 1, 1);
        do_read (7'h50, 8'h3C, 1, 2);

        // Error cases
        do_write(7'h50, 8'hA5, 0, 1, 3);
        do_write(7'h50, 8'hA5, 1, 0, 4);
        do_read (7'h50, 8'h3C, 0, 5);

        // Data patterns
        do_write(7'h50, 8'h00, 1, 1, 6);
        do_write(7'h50, 8'hFF, 1, 1, 6);
        do_write(7'h50, 8'hAA, 1, 1, 6);
        do_write(7'h50, 8'h55, 1, 1, 6);

        // Address patterns
        do_write(7'h00, 8'h01, 1, 1, 7);
        do_write(7'h7F, 8'h02, 1, 1, 7);
        do_write(7'h27, 8'h03, 1, 1, 7);
        do_write(7'h2A, 8'h04, 1, 1, 7);

        // Read patterns
        do_read(7'h50, 8'h00, 1, 8);
        do_read(7'h50, 8'hFF, 1, 8);
        do_read(7'h50, 8'hA5, 1, 8);
        do_read(7'h50, 8'h5A, 1, 8);

        // Back-to-back
        $display("\n[TC9] BACK-TO-BACK");

        for (i = 0; i < 4; i = i + 1) begin
            do_write(7'h30 + i[6:0],
                     8'h10 + i[7:0],
                     1, 1, 9);
        end

        // Reset while busy
        $display("\n[TC10] RESET MID-TRANSACTION");

        addr           = 7'h50;
        data_in        = 8'hCC;
        rw             = 0;
        slave_ack_addr = 1;
        slave_ack_data = 1;

        pulse_start();

        wait (busy);

        wait (scl_edges >= 4);

        @(negedge clk);
        rst = 1;
        repeat (3) @(negedge clk);
        rst = 0;

        repeat (5) @(posedge clk);

        if (busy !== 1'b0 || scl !== 1'b1 || sda !== 1'b1)
            $fatal(1, "[TC10] FAIL: reset did not release the bus");
        else
            $display("[TC10] PASS");

        // Clock stretching
        $display("\n[TC11] CLOCK STRETCHING");

        fork
            begin
                do_write(7'h50, 8'h99, 1, 1, 11);
            end

            begin
                hold_scl_low(8);
            end
        join


        // Stretch an address bit, a read data bit, a write ACK and STOP.
        fork
            do_write(7'h27, 8'h96, 1, 1, 12);
            hold_scl_low(3);
        join
        fork
            do_read(7'h50, 8'hA5, 1, 13);
            hold_scl_low(12);
        join
        fork
            do_write(7'h50, 8'h69, 1, 1, 14);
            hold_scl_low(17);
        join
        fork
            do_write(7'h50, 8'h81, 1, 1, 15);
            hold_scl_low(18);
        join

        // Capture the write byte with start, before a later host update.
        fork
            do_write(7'h50, 8'hA5, 1, 1, 16);
            begin
                @(posedge busy);
                @(negedge clk);
                data_in = 8'h5A;
            end
        join

        // Check the opposite ACK combination and recovery after NACK.
        do_write(7'h50, 8'hA5, 0, 0, 17);
        do_write(7'h50, 8'h5A, 1, 1, 18);

        if (EXHAUSTIVE) begin
            for (i = 0; i < 256; i = i + 1) begin
                do_read(7'h50, i[7:0], 1, 19);
                do_write(7'h27, i[7:0], 1, 1, 20);
            end
            $display("PASS exhaustive: all 256 read and write byte values");
        end

        $display("ALL TESTS PASSED");


        #1000;
        $finish;
    end

    initial begin
        #200ms;
        $fatal(1, "Global testbench timeout");
    end

endmodule
