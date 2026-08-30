module baud_gen #(
    parameter integer CLK_FREQ  = 100_000_000,
    parameter integer TICK_RATE = 115_200
  )(
    input  wire clk,
    input  wire rst_n,
    input  wire enable,
    input  wire restart,
    output wire tick
  );

  localparam integer ACC_WIDTH = $clog2(CLK_FREQ + TICK_RATE + 1);

  reg  [ACC_WIDTH-1:0] accumulator;
  wire [ACC_WIDTH:0]   sum;

  assign sum = {1'b0, accumulator} + TICK_RATE;

  assign tick =
         enable &&
         !restart &&
         (sum >= CLK_FREQ);

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
    begin
      accumulator <= {ACC_WIDTH{1'b0}};

    end
    else if (restart || !enable)
    begin
      accumulator <= {ACC_WIDTH{1'b0}};

    end
    else if (tick)
    begin
      accumulator <= sum - CLK_FREQ;

    end
    else
    begin
      accumulator <= sum[ACC_WIDTH-1:0];
    end

  end

endmodule
