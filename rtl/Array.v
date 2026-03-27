module Array #(
parameter width = 8,
parameter insts = 20,
parameter no_add = 15,
parameter res_width = 2*width + $clog2(no_add+1)
)
(
    input wire [width-1:0]a,
    input wire [width-1:0]b,
    input wire clk,
    input wire rst,
    input wire valid,
    input wire [width-1:0]bias,
    output reg [res_width-1:0] result,
    output reg result_valid
    );

wire [width-1:0] a_bus [0:insts-1][0:insts-1];
wire [width-1:0] b_bus [0:insts-1][0:insts-1];
wire v_bus [0:insts-1][0:insts-1];
wire [res_width-1:0] result_bus [0:insts-1][0:insts-1];
wire done_wire;
reg [res_width-1:0] intr;
reg [res_width-1:0] result_reg [0:insts-1][0:insts-1];
reg [insts-1:0] row;
reg [insts-1:0] col;

genvar i;
genvar j;

generate
    for(i=0;i<insts;i=i+1) begin
        for(j=0;j<insts;j=j+1) begin
            if (i==insts-1 && j == insts-1) begin
                Core #(
                    .no_add(no_add),
                    .width(width),
                    .res_width(res_width)
                    ) 
                Core_inst(
                    .clk(clk),
                    .rst(rst),
                    .a(a_bus[i][j]),
                    .b(b_bus[i][j]),
                    .valid(v_bus[i][j]),
                    .valid_out(v_bus[i][j+1]),
                    .a_out(a_bus[i][j+1]),
                    .b_out(b_bus[i+1][j]),
                    .result(result_bus[i][j]),
                    .done(done_wire)
                );
            end
            else begin
                Core #(
                    .no_add(no_add),
                    .width(width),
                    .res_width(res_width)
                    ) 
                Core_inst(
                    .clk(clk),
                    .rst(rst),
                    .a(a_bus[i][j]),
                    .b(b_bus[i][j]),
                    .valid(v_bus[i][j]),
                    .valid_out(v_bus[i][j+1]),
                    .a_out(a_bus[i][j+1]),
                    .b_out(b_bus[i+1][j]),
                    .result(result_bus[i][j]),
                    .done()
                );
            end
        end
      end
endgenerate

reg [width-1:0] a_skew [0:insts-1];
reg [width-1:0] b_skew [0:insts-1];
reg v_skew [0:insts-1];

integer x;

always @(posedge clk) begin
    if (rst) begin
        for (x = 0; x < insts; x = x + 1) begin
            a_skew[x] <= 0;
            b_skew[x] <= 0;
            v_skew[x] <= 0;
         end
    end
    else begin
        a_skew[0] <= a;
        b_skew[0] <= b;
        v_skew[0] <= valid;

        for (x = 1; x < insts; x = x + 1) begin
            a_skew[x] <= a_skew[x-1];
            b_skew[x] <= b_skew[x-1];
            v_skew[x] <= v_skew[x-1];
        end
    end
end

genvar k;
generate
    for(k=0; k<insts; k=k+1) begin
        assign a_bus[k][0] = a_skew[k];   
        assign b_bus[0][k] = b_skew[k];
        assign v_bus[k][0] = v_skew[k];
    end
endgenerate

integer m;
integer n;
always @(posedge clk) begin
    if (rst) begin
        for(m=0;m<insts;m=m+1) begin
            for(n=0;n<insts;n=n+1) begin
                result_reg[m][n] <= 0;
            end
         end
    end     
    else begin
        for(m=0;m<insts;m=m+1) begin
            for(n=0;n<insts;n=n+1) begin
                result_reg[m][n] <= result_bus[m][n];
            end
        end
    end
end

localparam COMPUTE = 1'b0;
localparam DRAIN   = 1'b1;

reg state;
reg reading_done; 
reg valid_pipe_1; 

always @(posedge clk) begin
    if (rst) begin
        row <= 0;
        col <= 0;
        result <= 0;
        intr <= 0;
        state <= COMPUTE;
        result_valid <= 0;
        valid_pipe_1 <= 0;
        reading_done <= 0;
    end
    else begin
        case (state)
            COMPUTE: begin
                result_valid <= 0;
                valid_pipe_1 <= 0;
                
                if (done_wire) begin
                    state <= DRAIN;
                    reading_done <= 0;
                end
            end
            
            DRAIN: begin
                if (!reading_done) begin
                    intr <= result_reg[row][col] + bias;
                    valid_pipe_1 <= 1'b1;
                    
                    if (col == insts-1) begin
                        col <= 0;
                        if (row == insts-1) begin
                            row <= 0;
                            reading_done <= 1'b1; 
                        end else begin
                            row <= row + 1;
                        end
                    end else begin
                        col <= col + 1;
                    end
                end else begin
                    valid_pipe_1 <= 1'b0; 
                end
                result <= (intr[res_width-1]) ? 0 : intr;
                result_valid <= valid_pipe_1; 
                if (reading_done && !valid_pipe_1) begin
                    state <= COMPUTE;
                    result_valid <= 0;
                end
            end
        endcase
    end
end
endmodule
