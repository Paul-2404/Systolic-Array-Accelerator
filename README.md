# Systolic-Array-Accelerator

This project implements a parametrized Systolic Array Accelerator for FPGA platforms, designed for high-throughput MAC operations accelerating matrix multiplication workloads typical in deep learning and signal processing applications.

The architecture adopts an output-stationary dataflow with diagonal wavefront scheduling, maximizing data reuse while minimizing memory bandwidth requirements. Each Processing Element (PE) performs multiple MAC operations and locally accumulates results, significantly reducing off-chip communication overhead.

The design is specialised in batch processing and the batch size is determined by the size of the array initialised in the design. 

The current design is implemented with an array size of 4x4 for simplicity. The size of the array which is initialsed can be easily modified by changing the **insts** parameter and reconfiguring the blocks in the block design accordingly.

🔧 Key Features
Custom Processing Elements (PEs) optimized for signed arithmetic and efficient accumulation
Output-stationary dataflow to minimize data movement and improve energy efficiency
Diagonal input streaming for sustained pipeline utilization
Double buffering to overlap computation and data transfer, reducing idle cycles
Parameterizable design for scalability across different array sizes and bit-widths
AXI-based memory interfacing for integration with processing systems (PS)

⚙️ Hardware & Tools:
FPGA Board: ZedBoard (Xilinx Zynq-7000 SoC)
Design Tools: Vivado
Languages: Verilog, TCL

📊 Design Goals:
Maximize compute throughput via parallel MAC operations
Reduce memory bottlenecks through data reuse strategies
Enable scalable architecture for larger workloads

📁 Repository Structure:
/rtl/ – Verilog modules (PE, systolic array, control logic)
/sim/ – Testbenches and simulation files
/ip/ – Custom and integrated IP blocks

🔍 Future Work:
Develop Processing System (PS) program in C.
Emulate the FPGA using Vitis' hardware emulation feature to simulate both PS and PL.
Calculate performance metrics in Emulation.
Program FPGA and test with random test data.
Develop an application in the host PC to send data over to the FPGA.
Test the complete system.
Modify the application to be capable of running any neural network.
