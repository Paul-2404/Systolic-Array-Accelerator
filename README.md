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
FPGA Board: Pynq ZU (Xilinx Ultrascale MP+SoC)
Design Tools: Vivado
Languages: Verilog, SystemVerilog, python

📊 Design Goals:
Maximize compute throughput via parallel MAC operations
Reduce memory bottlenecks through data reuse strategies
Enable scalable architecture for larger workloads

📁 Repository Structure:
/rtl/ – Verilog modules (PE, systolic array, control logic)
/sim/ – Testbenches and simulation files
/Host PC Scripts/ - Python scripts necessary for NN and value generation 
/main.py/ - Main program to run on the FPGA

🔍 Future Work:
Try running other larger networks apart from MNIST Classifier
Optimising the main.py to reduce software overhead 

Below is a step by step guide on how to implement this project:
1. Use the rtl and sim folders to design and verify the systolic array accelerator's designs.
2. Design and dataflow changes can be made easily to match the user's requirement.
3. Use the Block Design PNG as a reference for your own BD.
4. Copy the Host PC Scripts folder and run the NN.py and image_selector.py respectively.
5. After the quantized_network folder is generated, copy the folder along with the main.py and bitstream and hardware handoff files onto the FPGA.
6. Make sure the main.py, .bit and .hwh files are present inside the quantized_network folder on the FPGA.
7. Run the main.py.
