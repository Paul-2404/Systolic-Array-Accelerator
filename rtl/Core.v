module Core #(
    parameter width = 8,
    parameter no_add = 15,
    parameter res_width = 2*width + $clog2(no_add)
    )
(
    input wire clk,
    input wire rst,
    input wire valid,
    input wire [width-1:0]a,
    input wire[width-1:0]b,
    //input wire [res_width-1:0] partial,
    output reg valid_out,
    output reg [width-1:0]a_out,
    output reg [width-1:0]b_out,
    output reg [res_width-1:0]result,
    output reg done
);

reg [res_width-1:0]acc;
reg [$clog2(no_add-1):0]count;
 
always @ (posedge clk) begin
if (rst) begin
    acc <= 0;
    count <= 0;
    result <= 0;
    a_out <= 0;
    b_out <= 0;
    valid_out <= 0;
    done <= 0;
end
else begin
done <= 0;
if (valid) begin
        acc <= acc + (a*b);

        if (count == no_add-1) begin
            result <= acc + (a*b) ;
            acc <= 0;
            count <= 0;
            done <= 1;
        end
        else begin
            count <= count+1;
        end
        a_out <= a;
        b_out <= b;
    end
valid_out <= valid;
end
end
endmodule
