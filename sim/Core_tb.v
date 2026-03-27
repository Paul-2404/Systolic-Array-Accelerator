module core_tb;

parameter no_add = 4;
parameter width = 8;
parameter res_width = 2*width + $clog2(no_add);

reg [width-1:0] a;
reg [width-1:0] b;
reg clk;
reg rst;
reg valid;
wire valid_out;
wire [width-1:0] a_out;
wire [width-1:0] b_out;
wire [res_width-1:0] result;
integer i;

Core #(
    .no_add(no_add),
    .width(width),
    .res_width(res_width)
    ) 
dut (
    .clk(clk),
    .rst(rst),
    .a(a),
    .b(b),
    .valid(valid),
    .valid_out(valid_out),
    .result(result),
    .a_out(a_out),
    .b_out(b_out)
);

initial begin
    forever #5 clk = ~clk;
end

initial begin  
    clk = 0;
    a = 0;
    b = 0;
    rst = 1;
    valid = 0;
    #10;
    
    rst = 0;
    for (i = 0; i < 5; i=i+1) begin
        a = $random;
        b = $random;
        #10;
    end
    
    valid = 1;
    #10;
    for(i=5;i<20;i=i+1) begin
        a = $random;
        b = $random;
        #10;
    end
    
    #10;
    $finish;
end

endmodule
