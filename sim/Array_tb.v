module Array_tb();

parameter width = 8;
parameter insts = 4;
parameter res_width = 32;

reg signed [insts*width-1:0] a, b;
reg signed [res_width-1:0] bias;
reg bias_valid;
reg [res_width-1:0] M;
reg [width-1:0] shift;

reg [15:0] no_add;
reg clk, rst, valid;

wire signed [width-1:0] result;
wire result_valid;

Array #(
        .width(width),
        .insts(insts),
        .res_width(res_width)
       ) 
       dut (
            .a(a),
            .b(b),
            .clk(clk),
            .valid(valid),
            .no_add(no_add),
            .rst(rst),
            .bias(bias),
            .bias_valid(bias_valid),
            .M(M),
            .shift(shift),
            .result(result),
            .result_valid(result_valid)
           );

// Clock
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

integer i;
integer j;

initial begin
    bias = 0;
    bias_valid = 0;
    #10;
    
    bias_valid = 1;
    for (j = 0; j < 16; j = j+1) begin
        bias = $random;
        #10;
    end
    bias_valid = 0;
end

initial begin
    rst = 1;
    no_add = 10;
    a = 0;
    b = 0;
    valid = 0;
  
    // IMPORTANT: scaling config
    M = 32'd1;       // simple pass-through scaling
    shift = 0;

    #10;
    rst = 0;

    // Warmup phase (valid = 0)
    for(i = 0; i < 5; i = i + 1) begin
        a = $random;
        b = $random;
        #10;
    end

    #10;
    valid = 1;
    // Main test
    for(i = 5; i < 50; i = i + 1) begin
        a = $random;
        b = $random;
        #10;
    end

    #20;
    $finish;
end

// ================= DEBUG VISIBILITY =================
always @(posedge clk) begin
    if (result_valid) begin
        $display("TIME=%0t | RESULT=%0d", $time, result);
    end
end

endmodule
