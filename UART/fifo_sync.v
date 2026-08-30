module fifo_sync #(
    parameter integer DATA_WIDTH = 8,
    parameter integer FIFO_DEPTH = 16
  )(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  wr_en,
    input  wire                  rd_en,
    input  wire [DATA_WIDTH-1:0] data_in,

    output wire [DATA_WIDTH-1:0] data_out,
    output wire                  full,
    output wire                  empty,
    output reg                   overflow,
    output reg                   underflow
  );

  localparam integer ADDR_WIDTH =
             (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH);

  localparam integer COUNT_WIDTH =
             $clog2(FIFO_DEPTH + 1);

  reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

  reg [ADDR_WIDTH-1:0] rd_ptr;
  reg [ADDR_WIDTH-1:0] wr_ptr;

  reg [COUNT_WIDTH-1:0] count;

  wire do_read;
  wire do_write;

  assign empty = (count == 0);
  assign full  = (count == FIFO_DEPTH);

  assign data_out =
         empty ? {DATA_WIDTH{1'b0}} : mem[rd_ptr];

  assign do_read =
         rd_en && !empty;

  assign do_write =
         wr_en && (!full || do_read);

  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
    begin
      rd_ptr    <= {ADDR_WIDTH{1'b0}};
      wr_ptr    <= {ADDR_WIDTH{1'b0}};
      count     <= {COUNT_WIDTH{1'b0}};
      overflow  <= 1'b0;
      underflow <= 1'b0;
    end
    else
    begin
      overflow  <= wr_en && full && !do_read;
      underflow <= rd_en && empty;

      if (do_write)
      begin
        mem[wr_ptr] <= data_in;
        if (wr_ptr == FIFO_DEPTH-1)
          wr_ptr <= {ADDR_WIDTH{1'b0}};
        else
          wr_ptr <= wr_ptr + 1'b1;
      end

      if (do_read)
      begin
        if (rd_ptr == FIFO_DEPTH-1)
          rd_ptr <= {ADDR_WIDTH{1'b0}};
        else
          rd_ptr <= rd_ptr + 1'b1;
      end

      case ({do_write, do_read})
        2'b10:
          count <= count + 1'b1;
        2'b01:
          count <= count - 1'b1;
        default:
          count <= count;
      endcase
    end
  end

endmodule
