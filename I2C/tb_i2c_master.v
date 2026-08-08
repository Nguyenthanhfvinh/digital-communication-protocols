`timescale 1ns / 1ps

module tb_i2c_master;

    // Parameters
    localparam SYS_CLK_FREQ = 50_000_000;
    localparam I2C_FREQ     = 100_000;

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

    assign sda = sda_drive_en ? sda_drive_val : 1'bz;

    reg        slave_ack_addr;
    reg        slave_ack_data;
    reg [7:0]  slave_data;

    integer scl_edges;

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
        if (dut.state   != prev_state ||
            dut.phase   != prev_phase ||
            dut.bit_cnt != prev_bit) begin

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
            else if (scl_edges >= 9 && scl_edges <= 16) begin

                if (rw) begin
                    sda_drive_en  = 1;
                    sda_drive_val = slave_data[16 - scl_edges];
                end
                else begin
                    sda_drive_en = 0;
                end
            end

            // Data ACK
            else if (scl_edges == 17) begin

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

        repeat (5) @(posedge clk);

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

                $error("TIMEOUT!");

                $display("state     = %0d", dut.state);
                $display("phase     = %0d", dut.phase);
                $display("bit_cnt   = %0d", dut.bit_cnt);
                $display("busy      = %b", busy);
                $display("scl       = %b", scl);
                $display("sda       = %b", sda);

                $finish;
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

        if (ack_error !== ~(a_ack & d_ack)) begin
            $error("[TC%0d] FAIL: ack_error=%b expected=%b",
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

        if (a_ack) begin

            if (ack_error) begin
                $error("[TC%0d] FAIL: Unexpected ACK error", tc);
            end
            else if (data_out !== t_slave_data) begin
                $error("[TC%0d] FAIL: recv=%02h expected=%02h",
                        tc, data_out, t_slave_data);
            end
            else begin
                $display("[TC%0d] PASS", tc);
            end
        end
        else begin

            if (!ack_error) begin
                $error("[TC%0d] FAIL: Expected ACK error", tc);
            end
            else begin
                $display("[TC%0d] PASS (NACK detected)", tc);
            end
        end

        repeat (5) @(posedge clk);
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

        repeat (20) @(posedge clk);

        rst = 1;
        repeat (3) @(posedge clk);
        rst = 0;

        repeat (5) @(posedge clk);

        if (busy !== 1'b0)
            $error("[TC10] FAIL: busy not cleared by reset");
        else
            $display("[TC10] PASS");

        // Clock stretching
        $display("\n[TC11] CLOCK STRETCHING");

        fork
            begin
                do_write(7'h50, 8'h99, 1, 1, 11);
            end

            begin
                wait (scl_edges == 8);

                @(negedge scl);

                force scl = 1'b0;

                $display("[%0t] Slave stretches SCL", $time);

                #20us;

                release scl;

                $display("[%0t] Slave releases SCL", $time);
            end
        join


        $display(" ALL TESTS COMPLETED");


        #1000;
        $finish;
    end

endmodule