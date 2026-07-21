module fifo_sync #(
    parameter data_width = 8,
    parameter fifo_depth = 16,
    parameter addr_width = 4   // 4 for depth=16
)(
    input  wire                     clk,
    input  wire                     rst,        // active low (negedge)
    input  wire                     wr_en,
    input  wire                     rd_en,
    input  wire [data_width-1:0]    data_in,
    output wire [data_width-1:0]    data_out,
    output wire                     full,
    output wire                     empty
);

    // memory array
    reg [data_width-1:0] fifo_mem [0:fifo_depth-1];

    // read and write pointers (extra MSB for full/empty)
    reg [addr_width:0] rd_ptr;
    reg [addr_width:0] wr_ptr;

    assign empty = (rd_ptr == wr_ptr);
    assign full  = (wr_ptr[addr_width] != rd_ptr[addr_width]) &&
                   (wr_ptr[addr_width-1:0] == rd_ptr[addr_width-1:0]);

    // First-word fall-through: users may consume the current head on the
    // same clock edge that asserts rd_en.
    assign data_out = empty ? {data_width{1'b0}} :
                            fifo_mem[rd_ptr[addr_width-1:0]];

    // Allow simultaneous write+read when full (to keep data flowing)
    wire do_write = wr_en && (!full || rd_en);
    wire do_read  = rd_en && !empty;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            rd_ptr   <= 0;
            wr_ptr   <= 0;
        end else begin
            if (do_write) begin
                fifo_mem[wr_ptr[addr_width-1:0]] <= data_in;
                wr_ptr <= wr_ptr + 1;
            end
            if (do_read) begin
                rd_ptr   <= rd_ptr + 1;
            end
        end
    end

endmodule
