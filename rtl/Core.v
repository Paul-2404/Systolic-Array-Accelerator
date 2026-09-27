module Core #(
    parameter width = 8,
    parameter res_width = 32
    )
(
    input  wire clk,
    input  wire rst,
    input  wire valid,
    input  wire [15:0] no_add,
    input  wire signed [width-1:0]a,
    input  wire signed [width-1:0]b,
    output reg valid_out,
    output reg signed [width-1:0]a_out,
    output reg signed [width-1:0]b_out,
    output reg signed [res_width-1:0]result,
    output reg done
);

reg signed [res_width-1:0]acc;
reg [11:0]count;
reg [15:0] no_add_reg;
 
always @ (posedge clk) begin
if (rst) begin
    acc <= 0;
    count <= 0;
    result <= 0;
    no_add_reg <= 0;
    a_out <= 0;
    b_out <= 0;
    valid_out <= 0;
    done <= 0;
end

else begin
done <= 0;
no_add_reg <= no_add;
if (valid) begin
        acc <= acc + (a*b);

        if (count == no_add_reg-1) begin
            done <= 1;
            result <= acc + (a*b) ;
            acc <= 0;
            count <= 0;
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
