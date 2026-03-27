# Systolic-Array-Accelerator

This project implements a scalable 20×20 systolic array accelerator on FPGA, designed for high-throughput matrix multiplication workloads typical in deep learning and signal processing applications.

The architecture adopts an output-stationary dataflow with diagonal wavefront scheduling, maximizing data reuse while minimizing memory bandwidth requirements. Each Processing Element (PE) performs multiple MAC operations and locally accumulates results, significantly reducing off-chip communication overhead.

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
Support for larger matrices and batching along with matrix tiling
Quantization-aware optimizations for neural network inference
Performance benchmarking (throughput, latency, resource utilization)

Note: This accelerator is still a work in progress but the key component which is the the systolic array has been completely designed with a few minor tweaks related to quantization of the data still in progress.
