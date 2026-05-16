/ ============================================================
/  axi_systolic_wrapper.v                                     
/                                                             
/  AXI4-Lite slave wrapper around the Array module.           
/                                                             
/  MEMORY MAP (all offsets from S_AXI_BASEADDR):              
/  -----------------------------------------------            
/  0x0000  CTRL        [0]=start  [1]=rst_array               
/  0x0004  STATUS      [0]=busy   [1]=done                    
/  0x0008  BIAS        [7:0] bias value for this inference    
/  0x000C  RESULT_CNT  how many results have been written to B
/  0x0010  INPUT_PTR   [15:0] Base byte address for input_a   
/  0x0014  WEIGHT_PTR  [15:0] Base byte address for input_b   
/  0x0018  RESULT_PTR  [15:0] Base byte address for results   
/  0x001C  NO_ADD      [15:0] Number of MAC operations (depth)
/  0x0020  M_VAL       [31:0] Multiplier for quantization     
/  0x0024  SHIFT_VAL   [7:0]  Shift amount for quantization   
/ ============================================================
  
module axi_systolic_wrapper #(
    parameter WIDTH      = 8,
    parameter INSTS      = 4,
    parameter RES_WIDTH  = 32,
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 6
)(
    input  wire        S_AXI_ACLK,
    input  wire        S_AXI_ARESETN,
    input  wire [5:0]  S_AXI_AWADDR,
    input  wire        S_AXI_AWVALID,
    output reg         S_AXI_AWREADY,
    input  wire [31:0] S_AXI_WDATA,
    input  wire [3:0]  S_AXI_WSTRB,
    input  wire        S_AXI_WVALID,
    output reg         S_AXI_WREADY,
    output reg  [1:0]  S_AXI_BRESP,
    output reg         S_AXI_BVALID,
    input  wire        S_AXI_BREADY,
    input  wire [5:0]  S_AXI_ARADDR,
    input  wire        S_AXI_ARVALID,
    output reg         S_AXI_ARREADY,
    output reg  [31:0] S_AXI_RDATA,
    output reg  [1:0]  S_AXI_RRESP,
    output reg         S_AXI_RVALID,
    input  wire        S_AXI_RREADY,

    output reg  [31:0] bram_addr,
    input  wire [31:0] bram_rd_data,
    output reg  [31:0] bram_wr_data,
    output reg  [3:0]  bram_we,
    output reg         bram_en
);

reg        reg_start;
reg        reg_rst_array;
reg        reg_busy;
reg        reg_done;
reg [15:0] reg_result_cnt;

reg [15:0] reg_bias_ptr;
reg [15:0] reg_input_ptr;
reg [15:0] reg_weight_ptr;
reg [15:0] reg_result_ptr;

reg [15:0]          reg_no_add;
reg [RES_WIDTH-1:0] reg_M;
reg [WIDTH-1:0]     reg_shift;

localparam ADDR_CTRL       = 6'h00;
localparam ADDR_STATUS     = 6'h04;
localparam ADDR_BIAS_PTR   = 6'h08;
localparam ADDR_RESULT_CNT = 6'h0C;
localparam ADDR_INPUT_PTR  = 6'h10;
localparam ADDR_WEIGHT_PTR = 6'h14;
localparam ADDR_RESULT_PTR = 6'h18;
localparam ADDR_NO_ADD     = 6'h1C;
localparam ADDR_M_VAL      = 6'h20;
localparam ADDR_SHIFT_VAL  = 6'h24;

localparam TOTAL_RESULTS = INSTS * INSTS;
localparam NUM_BIASES    = INSTS * INSTS;

localparam IDLE      = 4'd0;
localparam RD_BIAS_A = 4'd1;
localparam WAIT_BIAS = 4'd2;
localparam RD_BIAS_B = 4'd3;
localparam RD_A      = 4'd4;
localparam WAIT_A    = 4'd5;
localparam RD_B      = 4'd6;
localparam WAIT_B    = 4'd7;
localparam FEED      = 4'd8;
localparam WAIT      = 4'd9;
localparam COLLECT   = 4'd10;
localparam FINISHED  = 4'd11;

reg [3:0] feed_state;

reg [15:0] feed_idx;
reg [15:0] bias_idx;
reg [15:0] result_idx;

reg [INSTS*WIDTH-1:0] latched_a;

reg                    array_valid;
reg [INSTS*WIDTH-1:0]  array_a;
reg [INSTS*WIDTH-1:0]  array_b;

reg [RES_WIDTH-1:0] array_bias_data;
reg                  array_bias_valid;

wire [WIDTH-1:0] array_result;
wire             array_result_valid;

Array #(
    .width(WIDTH),
    .insts(INSTS),
    .res_width(RES_WIDTH)
) u_array (
    .clk(S_AXI_ACLK),
    .rst(reg_rst_array | ~S_AXI_ARESETN),
    .a(array_a),
    .b(array_b),
    .no_add(reg_no_add),
    .valid(array_valid),
    .bias(array_bias_data),
    .bias_valid(array_bias_valid),
    .M(reg_M),
    .shift(reg_shift),
    .result(array_result),
    .result_valid(array_result_valid)
);

always @(posedge S_AXI_ACLK) begin

    if (!S_AXI_ARESETN) begin

        feed_state       <= IDLE;
        feed_idx         <= 0;
        bias_idx         <= 0;
        result_idx       <= 0;

        array_valid      <= 0;
        array_a          <= 0;
        array_b          <= 0;

        array_bias_data  <= 0;
        array_bias_valid <= 0;

        bram_addr        <= 0;
        bram_we          <= 4'b0000;
        bram_en          <= 0;
        bram_wr_data     <= 0;

        reg_busy         <= 0;
        reg_done         <= 0;
        reg_result_cnt   <= 0;

        latched_a        <= 0;

    end

    else begin

        bram_we          <= 4'b0000;
        bram_en          <= 0;
        array_valid      <= 0;
        array_bias_valid <= 0;
        reg_start        <= 0;

        case(feed_state)

            IDLE: begin

                reg_busy <= 0;

                if(reg_start && reg_no_add > 0) begin

                    reg_busy       <= 1;
                    reg_done       <= 0;

                    result_idx     <= 0;
                    feed_idx       <= 0;
                    bias_idx       <= 0;

                    reg_result_cnt <= 0;

                    feed_state     <= RD_BIAS_A;

                end
            end

            RD_BIAS_A: begin
                bram_en   <= 1;
                bram_addr <= reg_bias_ptr + (bias_idx << 2);
                feed_state <= WAIT_BIAS;
            end

            WAIT_BIAS: begin
                feed_state <= RD_BIAS_B;
            end

            RD_BIAS_B: begin

                array_bias_data  <= bram_rd_data;
                array_bias_valid <= 1;

                if(bias_idx == NUM_BIASES-1)
                    feed_state <= RD_A;
                else begin
                    bias_idx   <= bias_idx + 1;
                    feed_state <= RD_BIAS_A;
                end
            end

            RD_A: begin
                bram_en   <= 1;
                bram_addr <= reg_input_ptr + (feed_idx << 2);
                feed_state <= WAIT_A;
            end

            WAIT_A: begin
                feed_state <= RD_B;
            end

            RD_B: begin

                latched_a <= bram_rd_data[INSTS*WIDTH-1:0];

                bram_en   <= 1;
                bram_addr <= reg_weight_ptr + (feed_idx << 2);

                feed_state <= WAIT_B;

            end

            WAIT_B: begin
                feed_state <= FEED;
            end

            FEED: begin

                array_a     <= latched_a;
                array_b     <= bram_rd_data[INSTS*WIDTH-1:0];
                array_valid <= 1;

                if(feed_idx == reg_no_add - 1) begin
                    feed_idx   <= 0;
                    feed_state <= WAIT;
                end
                else begin
                    feed_idx   <= feed_idx + 1;
                    feed_state <= RD_A;
                end
            end

            WAIT: begin

                if(array_result_valid) begin

                    feed_state   <= COLLECT;

                    bram_en      <= 1;
                    bram_we      <= 4'b1111;

                    bram_addr    <= reg_result_ptr + (result_idx << 2);

                    bram_wr_data <= {{(32-WIDTH){1'b0}}, array_result};

                    result_idx   <= result_idx + 1;
                    reg_result_cnt <= 1;

                end
            end

            COLLECT: begin

                if(array_result_valid) begin

                    bram_en      <= 1;
                    bram_we      <= 4'b1111;

                    bram_addr    <= reg_result_ptr + (result_idx << 2);

                    bram_wr_data <= {{(32-WIDTH){1'b0}}, array_result};

                    result_idx   <= result_idx + 1;
                    reg_result_cnt <= result_idx + 1;

                    if(result_idx == TOTAL_RESULTS - 1)
                        feed_state <= FINISHED;

                end
            end

            FINISHED: begin
                reg_busy   <= 0;
                reg_done   <= 1;
                feed_state <= IDLE;
            end

        endcase
    end
end
// ============================================================
//  AXI4-Lite Write logic
// ============================================================
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        S_AXI_AWREADY  <= 0;
        S_AXI_WREADY   <= 0;
        S_AXI_BVALID   <= 0;
        S_AXI_BRESP    <= 2'b00;
        reg_start      <= 0;
        reg_rst_array  <= 0;
        reg_bias_ptr   <= 16'h0800;
        reg_input_ptr  <= 16'h0000;
        reg_weight_ptr <= 16'h0C40;
        reg_result_ptr <= 16'h1880;
        reg_no_add     <= 16'h0001; // Default to 1 to prevent underflow
        reg_M          <= 32'h0000_0001;
        reg_shift      <= 0;
    end
    else begin
        if (S_AXI_AWVALID && S_AXI_WVALID && !S_AXI_AWREADY) begin
            S_AXI_AWREADY <= 1;
            S_AXI_WREADY  <= 1;

            case (S_AXI_AWADDR[5:0]) // [FIXED] Check against 6 bits now
                ADDR_CTRL: begin
                    reg_start     <= S_AXI_WDATA[0];  
                    reg_rst_array <= S_AXI_WDATA[1];
                end
                ADDR_BIAS_PTR:   reg_bias_ptr   <= S_AXI_WDATA[15:0];
                ADDR_INPUT_PTR:  reg_input_ptr  <= S_AXI_WDATA[15:0]; 
                ADDR_WEIGHT_PTR: reg_weight_ptr <= S_AXI_WDATA[15:0]; 
                ADDR_RESULT_PTR: reg_result_ptr <= S_AXI_WDATA[15:0]; 
                ADDR_NO_ADD:     reg_no_add     <= S_AXI_WDATA[15:0]; // [NEW]
                ADDR_M_VAL:      reg_M          <= S_AXI_WDATA;       // [NEW]
                ADDR_SHIFT_VAL:  reg_shift      <= S_AXI_WDATA[WIDTH-1:0]; // [NEW]
            endcase

            S_AXI_BVALID <= 1;
            S_AXI_BRESP  <= 2'b00;  
        end
        else begin
            S_AXI_AWREADY <= 0;
            S_AXI_WREADY  <= 0;
            if (S_AXI_BREADY) S_AXI_BVALID <= 0;
        end
    end
end

// ============================================================
//  AXI4-Lite Read logic
// ============================================================
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        S_AXI_ARREADY <= 0;
        S_AXI_RVALID  <= 0;
        S_AXI_RDATA   <= 0;
        S_AXI_RRESP   <= 2'b00;
    end
    else begin
        if (S_AXI_ARVALID && !S_AXI_ARREADY) begin
            S_AXI_ARREADY <= 1;
            S_AXI_RVALID  <= 1;
            S_AXI_RRESP   <= 2'b00;

            case (S_AXI_ARADDR[5:0]) // [FIXED] Check against 6 bits now
                ADDR_CTRL:       S_AXI_RDATA <= {30'b0, reg_rst_array, reg_start};
                ADDR_STATUS:     S_AXI_RDATA <= {30'b0, reg_done, reg_busy};
                ADDR_BIAS_PTR:   S_AXI_RDATA <= {16'b0, reg_bias_ptr};
                ADDR_RESULT_CNT: S_AXI_RDATA <= {16'b0, reg_result_cnt};
                ADDR_INPUT_PTR:  S_AXI_RDATA <= {16'b0, reg_input_ptr};  
                ADDR_WEIGHT_PTR: S_AXI_RDATA <= {16'b0, reg_weight_ptr}; 
                ADDR_RESULT_PTR: S_AXI_RDATA <= {16'b0, reg_result_ptr}; 
                ADDR_NO_ADD:     S_AXI_RDATA <= {16'b0, reg_no_add};     // [NEW]
                ADDR_M_VAL:      S_AXI_RDATA <= reg_M;                   // [NEW]
                ADDR_SHIFT_VAL:  S_AXI_RDATA <= {{(32-WIDTH){1'b0}}, reg_shift}; // [NEW]
                default:         S_AXI_RDATA <= 32'hDEADBEEF;
            endcase
        end
        else begin
            S_AXI_ARREADY <= 0;
            if (S_AXI_RREADY) S_AXI_RVALID <= 0;
        end
    end
end

endmodule
