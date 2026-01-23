# OpenGPU Makefile
# =================
# Build and simulation targets for the OpenGPU project

# Tools
IVERILOG = iverilog
VVP = vvp
PYTHON = python3

# Directories
RTL_DIR = rtl
SIM_DIR = sim
SW_DIR = sw
BUILD_DIR = build

# Source files
PKG_SRC = $(RTL_DIR)/common/pkg_opengpu.sv
CORE_SRC = \
	$(RTL_DIR)/exec/int_alu.sv \
	$(RTL_DIR)/core/regfile/vector_regfile.sv \
	$(RTL_DIR)/core/pipeline/fetch_stage.sv \
	$(RTL_DIR)/core/pipeline/decode_stage.sv \
	$(RTL_DIR)/core/pipeline/execute_stage.sv \
	$(RTL_DIR)/core/pipeline/memory_stage.sv \
	$(RTL_DIR)/core/pipeline/writeback_stage.sv \
	$(RTL_DIR)/core/core_top.sv

SIM_SRC = \
	$(SIM_DIR)/models/memory_model.sv \
	$(SIM_DIR)/tb/tb_core.sv

ALL_SRC = $(PKG_SRC) $(CORE_SRC) $(SIM_SRC)

# Flags
IVERILOG_FLAGS = -g2012 -Wall -DSIMULATION

# Targets
.PHONY: all clean sim test assemble

all: sim

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Compile testbench
$(BUILD_DIR)/tb_core: $(ALL_SRC) | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $(ALL_SRC)

# Run simulation
sim: $(BUILD_DIR)/tb_core
	cd $(BUILD_DIR) && $(VVP) tb_core

# Run tests (alias for sim)
test: sim

# Assemble a program
# Usage: make assemble SRC=sw/kernels/test.asm
assemble:
	$(PYTHON) $(SW_DIR)/assembler/opengpu_asm.py $(SRC)

# Assemble all test kernels
assemble-all:
	$(PYTHON) $(SW_DIR)/assembler/opengpu_asm.py $(SW_DIR)/kernels/test_arithmetic.asm
	$(PYTHON) $(SW_DIR)/assembler/opengpu_asm.py $(SW_DIR)/kernels/test_loop.asm
	$(PYTHON) $(SW_DIR)/assembler/opengpu_asm.py $(SW_DIR)/kernels/vector_add.asm
	$(PYTHON) $(SW_DIR)/assembler/opengpu_asm.py $(SW_DIR)/kernels/matrix_mul.asm
	$(PYTHON) $(SW_DIR)/assembler/opengpu_asm.py $(SW_DIR)/kernels/reduction.asm
	$(PYTHON) $(SW_DIR)/assembler/opengpu_asm.py $(SW_DIR)/kernels/fp_test.asm

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	rm -f *.vcd
	rm -f $(SW_DIR)/kernels/*.hex

# View waveforms (requires gtkwave)
wave:
	gtkwave $(BUILD_DIR)/tb_core.vcd &

# Lint check
lint: | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -o /dev/null $(PKG_SRC) $(CORE_SRC)
	@echo "Lint check passed!"

# Help
help:
	@echo "OpenGPU Build Targets:"
	@echo "  make sim        - Compile and run simulation"
	@echo "  make test       - Same as sim"
	@echo "  make lint       - Run lint checks"
	@echo "  make assemble SRC=file.asm - Assemble a program"
	@echo "  make assemble-all - Assemble all test kernels"
	@echo "  make wave       - View waveforms in gtkwave"
	@echo "  make clean      - Clean build artifacts"
