`timescale 1ns / 1ps

module tb_system();

// =========================================================
// 1. Declare External Pins & Clocks
// =========================================================
wire usb_uart_rxd = 1'b1;
wire usb_uart_txd;

reg clk;

initial begin
    clk = 0;
    forever #5 clk = ~clk;   // 100 MHz clock
end

// =========================================================
// 2. Instantiate Block Design Wrapper
// ===================================================
design_1_wrapper dut (
    .usb_uart_rxd(usb_uart_rxd),
    .usb_uart_txd(usb_uart_txd)
);

// =========================================================
// 3. VIP Variables
// =========================================================
reg [1:0]  resp;
reg [31:0] read_data;

integer i;

// =========================================================
// 4. Random Data Variables
// =========================================================
integer num_vectors;

reg [31:0] rand_input;
reg [31:0] rand_weight;

// =========================================================
// 5. Performance Variables
// =========================================================
integer cycle_counter;
integer start_cycle;
integer end_cycle;
integer latency_cycles;

real clock_period_ns;
real execution_time_ns;
real execution_time_us;

real peak_ops_per_cycle;
real peak_gops;

real effective_ops;
real effective_gops;

integer total_pes;

// =========================================================
// 6. Cycle Counter
// =========================================================
always @(posedge clk) begin
    cycle_counter <= cycle_counter + 1;
end

initial begin
    cycle_counter = 0;
end
// =========================================================
// 7. VIP Hierarchy Mapping
// =========================================================
`define ZYNQ_VIP dut.design_1_i.processing_system7_0.inst

// =========================================================
// 8. SYSTEM MEMORY MAP
// =========================================================
localparam SYSTOLIC_BASE  = 32'h4000_2000;
localparam BRAM_CTRL_BASE = 32'h4000_0000;

localparam ADDR_CTRL       = SYSTOLIC_BASE + 32'h00;
localparam ADDR_STATUS     = SYSTOLIC_BASE + 32'h04;
localparam ADDR_BIAS_PTR   = SYSTOLIC_BASE + 32'h08;
localparam ADDR_INPUT_PTR  = SYSTOLIC_BASE + 32'h10;
localparam ADDR_WEIGHT_PTR = SYSTOLIC_BASE + 32'h14;
localparam ADDR_RESULT_PTR = SYSTOLIC_BASE + 32'h18;
localparam ADDR_NO_ADD     = SYSTOLIC_BASE + 32'h1C;
localparam ADDR_M_VAL      = SYSTOLIC_BASE + 32'h20;
localparam ADDR_SHIFT_VAL  = SYSTOLIC_BASE + 32'h24;

localparam REGION_BIAS   = 32'h00000;
localparam REGION_INPUT  = 32'h00100;
localparam REGION_WEIGHT = 32'h00200;
localparam REGION_RESULT = 32'h00300;

// =========================================================
// 9. Array Parameters
// =========================================================
localparam ARRAY_DIM = 4;
localparam NUM_PES   = ARRAY_DIM * ARRAY_DIM;

// =========================================================
// 10. Main Test Sequence
// =========================================================
initial begin

    $display("==================================================");
    $display(" PARAMETERIZED SYSTOLIC ARRAY PERFORMANCE TEST ");
    $display("==================================================");

    // -----------------------------------------------------
    // Initialize Performance Variables
    // -----------------------------------------------------
    clock_period_ns = 10.0; // 100 MHz

    // -----------------------------------------------------
    // Set Workload Size
    // -----------------------------------------------------
    // CHANGE THIS VALUE TO SCALE WORKLOAD
    num_vectors = 2;

    // -----------------------------------------------------
    // VIP Initialization
    // -----------------------------------------------------
    `ZYNQ_VIP.set_debug_level_info(1);
    `ZYNQ_VIP.set_stop_on_error(1);

    // FPGA Reset
    `ZYNQ_VIP.fpga_soft_reset(32'h1);
    #200;

    `ZYNQ_VIP.fpga_soft_reset(32'h0);

    // Allow reset propagation
    #1000;

    // =====================================================
    // STEP 1: LOAD BIASES
    // =====================================================
    $display("\n[TB] Loading Biases...");

    for(i = 0; i < 16; i = i + 1) begin

        `ZYNQ_VIP.write_data(
            BRAM_CTRL_BASE + REGION_BIAS + (i*4),
            4,
            (i+1)*10,
            resp
        );

    end
// =====================================================
    // STEP 2: LOAD RANDOM INPUTS & WEIGHTS
    // =====================================================
    $display("\n[TB] Loading Random Inputs and Weights...");

    for(i = 0; i < num_vectors; i = i + 1) begin

        // -------------------------------------------------
        // Generate Random Packed 8-bit INPUTS
        // -------------------------------------------------
        rand_input = {
            $random & 8'h7F,
            $random & 8'h7F,
            $random & 8'h7F,
            $random & 8'h7F
        };

        // -------------------------------------------------
        // Generate Random Packed 8-bit WEIGHTS
        // -------------------------------------------------
        rand_weight = {
            $random & 8'h7F,
            $random & 8'h7F,
            $random & 8'h7F,
            $random & 8'h7F
        };

        // -------------------------------------------------
        // Write INPUT Vector
        // -------------------------------------------------
        `ZYNQ_VIP.write_data(
            BRAM_CTRL_BASE + REGION_INPUT + (i*4),
            4,
            rand_input,
            resp
        );

        // -------------------------------------------------
        // Write WEIGHT Vector
        // -------------------------------------------------
        `ZYNQ_VIP.write_data(
            BRAM_CTRL_BASE + REGION_WEIGHT + (i*4),
            4,
            rand_weight,
            resp
        );

        // -------------------------------------------------
        // Debug Prints
        // -------------------------------------------------
        $display(
            "Vector[%0d] INPUT = %h   WEIGHT = %h",
            i,
            rand_input,
            rand_weight
        );

    end

// =====================================================
    // STEP 3: CONFIGURE WRAPPER REGISTERS
    // =====================================================
    $display("\n[TB] Configuring Accelerator Registers...");

    `ZYNQ_VIP.write_data(ADDR_BIAS_PTR,   4, REGION_BIAS,   resp);
    `ZYNQ_VIP.write_data(ADDR_INPUT_PTR,  4, REGION_INPUT,  resp);
    `ZYNQ_VIP.write_data(ADDR_WEIGHT_PTR, 4, REGION_WEIGHT, resp);
    `ZYNQ_VIP.write_data(ADDR_RESULT_PTR, 4, REGION_RESULT, resp);

    // -----------------------------------------------------
    // Workload Size
    // -----------------------------------------------------
    `ZYNQ_VIP.write_data(
        ADDR_NO_ADD,
        4,
        num_vectors,
        resp
    );

    `ZYNQ_VIP.write_data(ADDR_M_VAL,     4, 32'd1, resp);
    `ZYNQ_VIP.write_data(ADDR_SHIFT_VAL, 4, 32'd0, resp);

    // =====================================================
    // STEP 4: START ACCELERATOR
    // =====================================================
    $display("\n[TB] Starting Accelerator...");

    start_cycle = cycle_counter;

    `ZYNQ_VIP.write_data(
        ADDR_CTRL,
        4,
        32'h0001,
        resp
    );

    // =====================================================
    // STEP 5: POLL STATUS UNTIL DONE
    // =====================================================
    read_data = 0;

    while((read_data & 32'h0000_0002) == 0) begin

        `ZYNQ_VIP.read_data(
            ADDR_STATUS,
            4,
            read_data,
            resp
        );

        #100;

    end

    end_cycle = cycle_counter;

    latency_cycles = end_cycle - start_cycle;

    $display("\n[TB] Hardware Execution Complete!");

    // =====================================================
    // STEP 6: READ RESULTS
    // =====================================================
    $display("\n==================================================");
    $display(" ARRAY RESULTS ");
    $display("==================================================");

    for(i = 0; i < NUM_PES; i = i + 1) begin

        `ZYNQ_VIP.read_data(
            BRAM_CTRL_BASE + REGION_RESULT + (i*4),
            4,
            read_data,
            resp
        );

        $display(
            "PE[%0d] Result = %0d",
            i,
            read_data
        );

    end

    // =====================================================
    // STEP 7: PERFORMANCE CALCULATIONS
    // =====================================================

    execution_time_ns =
        latency_cycles * clock_period_ns;

    execution_time_us =
        execution_time_ns / 1000.0;

    total_pes = NUM_PES;

    // -----------------------------------------------------
    // Peak Throughput
    // -----------------------------------------------------
    peak_ops_per_cycle =
        2.0 * total_pes;

    peak_gops =
        (peak_ops_per_cycle * 100.0e6)
        / 1.0e9;

    // -----------------------------------------------------
    // Effective Operations
    // -----------------------------------------------------
    // 4 packed int8 values per 32-bit transfer
    // Each MAC = multiply + accumulate = 2 ops
    effective_ops =
        2.0 *
        total_pes *
        num_vectors *
        4.0;

    // -----------------------------------------------------
    // Effective Throughput
    // -----------------------------------------------------
    effective_gops =
        effective_ops / execution_time_ns;

    // =====================================================
    // STEP 8: PERFORMANCE REPORT
    // =====================================================
    $display("\n==================================================");
    $display(" PERFORMANCE REPORT ");
    $display("==================================================");

    $display(" Array Dimension           : %0d x %0d",
             ARRAY_DIM,
             ARRAY_DIM);

    $display(" Total Processing Elements : %0d",
             total_pes);

    $display(" Workload Size             : %0d vectors",
             num_vectors);

    $display(" Clock Frequency           : 100 MHz");

    $display(" Clock Period              : %0f ns",
             clock_period_ns);

    $display(" Start Cycle               : %0d",
             start_cycle);

    $display(" End Cycle                 : %0d",
             end_cycle);

    $display(" Total Latency Cycles      : %0d",
             latency_cycles);

    $display(" Execution Time            : %0f ns",
             execution_time_ns);

    $display(" Execution Time            : %0f us",
             execution_time_us);

    $display(" Peak Ops/Cycle            : %0f",
             peak_ops_per_cycle);

    $display(" Theoretical Peak GOPS     : %0f",
             peak_gops);

    $display(" Effective Operations      : %0f",
             effective_ops);

    $display(" Measured Effective GOPS   : %0f",
             effective_gops);
  
    $finish;

end

endmodule
