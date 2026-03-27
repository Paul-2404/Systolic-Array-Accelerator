module Array_tb();

parameter width=8;
parameter insts=3;
parameter no_add = 15;
parameter res_width = 2*width + $clog2(no_add+1);

reg [width-1:0]a,b,bias;
reg clk,rst,valid;
//wire valid_out;
wire[res_width-1:0]result;

Array #(
        .width(width),
        .insts(insts),
        .no_add(no_add),
        .res_width(res_width)
       ) 
       dut (
            .a(a),
            .b(b),
            .clk(clk),
            .valid(valid),
            //.valid_out(valid_out),
            .rst(rst),
            .bias(bias),
            .result(result)
           );
    
initial begin
    clk =0;
    forever #5 clk=~clk;
end

integer i;
initial begin
    rst = 1;
    a = 0;
    b = 0;
    valid = 0;
    bias = 0;
    
    #10;
    rst = 0;
    
    for(i=0;i<5;i=i+1) begin
        a = $random;
        b = $random;
        bias = $random;
        #10;
    end
    
    #10;
    valid = 1;
    for(i=5;i<50;i=i+1) begin
        a = $random;
        b = $random;
        bias = $random;
        #10;
    end
    
    #10;
    $finish;
end
endmodule
