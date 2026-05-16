module Array #(
    parameter width = 8,
    parameter insts = 4,
    parameter res_width = 32
)
(
    input wire [insts*width-1:0] a,
    input wire [insts*width-1:0] b,
    input wire clk,
    input wire rst,
    input wire [15:0] no_add,
    input wire valid,
    
    // -- Serial Bias Interface --
    input wire signed [res_width-1:0] bias,
    input wire bias_valid, 
    
    input wire [res_width-1:0] M,
    input wire [width-1:0] shift,
    output reg signed [width-1:0] result,
    output reg result_valid
);

wire signed [width-1:0] a_bus [0:insts-1][0:insts-1];
wire signed [width-1:0] b_bus [0:insts-1][0:insts-1];
wire v_bus [0:insts-1][0:insts-1];
reg signed [width-1:0] a_delay [0:insts-1][0:insts-1];
reg signed [width-1:0] b_delay [0:insts-1][0:insts-1];
reg v_delay [0:insts-1][0:insts-1];
wire signed [res_width-1:0] result_bus [0:insts-1][0:insts-1];
wire done_wire;
reg signed [res_width-1:0] intr;
reg signed [res_width-1:0] result_reg [0:insts-1][0:insts-1];
reg [insts-1:0] row;
reg [insts-1:0] col;

genvar i;
genvar j;

generate
    for(i=0; i<insts; i=i+1) begin
        for(j=0; j<insts; j=j+1) begin
            if (i==insts-1 && j == insts-1) begin
                Core #(
                    .width(width),
                    .res_width(res_width)
                ) 
                Core_inst(
                    .clk(clk),
                    .rst(rst),
                    .a(a_bus[i][j]),
                    .b(b_bus[i][j]),
                    .no_add(no_add),
                    .valid(v_bus[i][j]),
                    .valid_out(),
                    .a_out(a_bus[i][j+1]),
                    .b_out(b_bus[i+1][j]),
                    .result(result_bus[i][j]),
                    .done(done_wire)
                );
            end
            else begin
                Core #(
                    .width(width),
                    .res_width(res_width)
                ) 
                Core_inst(
                    .clk(clk),
                    .rst(rst),
                    .a(a_bus[i][j]),
                    .b(b_bus[i][j]),
                    .no_add(no_add),
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

integer c, d;

always @(posedge clk) begin
    if (rst) begin
        for (c=0; c<insts; c=c+1)
            for (d=0; d<insts; d=d+1) begin
                a_delay[c][d] <= 0;
                b_delay[c][d] <= 0;
                v_delay[c][d] <= 0;
            end
    end else begin
        for (c=0; c<insts; c=c+1) begin
            // A skew (row-wise)
            a_delay[c][0] <= a[c*width +: width];
            v_delay[c][0] <= valid;

            for (d=1; d<insts; d=d+1) begin
                a_delay[c][d] <= a_delay[c][d-1];
                v_delay[c][d] <= v_delay[c][d-1];
            end
        end

        for (d=0; d<insts; d=d+1) begin
            // B skew (column-wise)
            b_delay[d][0] <= b[d*width +: width];

            for (c=1; c<insts; c=c+1) begin
                b_delay[d][c] <= b_delay[d][c-1];
            end
        end
    end
end

genvar k;

generate
for (k=0; k<insts; k=k+1) begin
    assign a_bus[k][0] = a_delay[k][k];   // skewed A
    assign b_bus[0][k] = b_delay[k][k];   // skewed B
    assign v_bus[k][0] = v_delay[k][k];   // skewed valid
end
endgenerate

integer m;
integer n;
reg signed [res_width-1:0] bias_reg [0:insts-1][0:insts-1];

// ------------------------------------------------------------
// Result Storage and Serial Bias Shift Register
// ------------------------------------------------------------
always @(posedge clk) begin
    if (rst) begin
        for(m=0; m<insts; m=m+1) begin
            for(n=0; n<insts; n=n+1) begin
                result_reg[m][n] <= 0;
                bias_reg[m][n]   <= 0;
            end
        end
    end     
    else begin
        // Constantly store computational results
        for(m=0; m<insts; m=m+1) begin
            for(n=0; n<insts; n=n+1) begin
                result_reg[m][n] <= result_bus[m][n];
            end
        end
        
        // Daisy-chain shift register for loading biases
        if (bias_valid) begin
            // The newest bias enters at the very last register in the array
            bias_reg[insts-1][insts-1] <= bias;
            
            for(m=0; m<insts; m=m+1) begin
                for(n=0; n<insts; n=n+1) begin
                    if (m == insts-1 && n == insts-1) begin
                        // Handled above (entry point)
                    end else if (n == insts-1) begin
                        // The last element of a row pulls from the first element of the NEXT row
                        bias_reg[m][n] <= bias_reg[m+1][0];
                    end else begin
                        // Shift "left" across the columns in the same row
                        bias_reg[m][n] <= bias_reg[m][n+1];
                    end
                end
            end
        end
    end
end

localparam COMPUTE = 1'b0;
localparam DRAIN   = 1'b1;

reg state;
reg reading_done; 
reg valid_pipe_1;
reg [res_width-1:0] M_reg;
reg [width-1:0] shift_reg;
reg signed [(res_width*2)-1:0] scaled;
reg signed [res_width-1:0] shifted;
reg valid_pipe_2;
reg valid_pipe_3;

// ------------------------------------------------------------
// Drain FSM
// ------------------------------------------------------------
always @(posedge clk) begin
    M_reg <= M;
    shift_reg <= shift;
    
    if (rst) begin
        row <= 0;
        col <= 0;
        result <= 0;
        intr <= 0;
        state <= COMPUTE;
        result_valid <= 0;
        valid_pipe_1 <= 0;
        valid_pipe_2 <= 0;
        valid_pipe_3 <= 0;
        reading_done <= 0;
        M_reg <= 0;
        shift_reg <= 0;
        scaled <= 0;
        shifted <= 0;
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
                    // Add the locally stored bias during the drain state
                    intr <= result_reg[row][col] + bias_reg[row][col];
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
                
                scaled <= intr * M_reg;
                valid_pipe_2 <= valid_pipe_1;
                
                shifted <= scaled >>> shift_reg;
                valid_pipe_3 <= valid_pipe_2;
                
                result <= (shifted > 127) ? 8'd127 :
                          (shifted < 0)   ? 8'd0 :
                          shifted[width-1:0];
                result_valid <= valid_pipe_3; 
                
                if (reading_done && !valid_pipe_3) begin
                    state <= COMPUTE;
                    result_valid <= 0;
                end
            end
        endcase
    end
end
endmodule
