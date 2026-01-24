# OpenGPU Simulation Makefile
# Uses Icarus Verilog for simulation

IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave

# RTL directories
RTL_DIR = ../rtl
COMMON_DIR = $(RTL_DIR)/common
CORE_DIR = $(RTL_DIR)/core
EXEC_DIR = $(RTL_DIR)/exec
SIMT_DIR = $(RTL_DIR)/simt
MEMORY_DIR = $(RTL_DIR)/memory
PIPELINE_DIR = $(CORE_DIR)/pipeline
REGFILE_DIR = $(CORE_DIR)/regfile
FPU_DIR = $(EXEC_DIR)/fpu

# Testbench and model directories
TB_DIR = tb
MODEL_DIR = models

# Common source files
COMMON_SRCS = \
	$(COMMON_DIR)/pkg_opengpu.sv

# Execution unit sources
EXEC_SRCS = \
	$(EXEC_DIR)/int_alu.sv \
	$(EXEC_DIR)/simd_int_alu.sv \
	$(EXEC_DIR)/vote_unit.sv \
	$(EXEC_DIR)/shuffle_unit.sv \
	$(EXEC_DIR)/simd_fpu.sv \
	$(FPU_DIR)/fp_alu.sv \
	$(FPU_DIR)/fp_addsub.sv \
	$(FPU_DIR)/fp_mul.sv \
	$(FPU_DIR)/fp_div.sv \
	$(FPU_DIR)/fp_sqrt.sv \
	$(FPU_DIR)/fp_fma.sv \
	$(FPU_DIR)/fp_misc.sv \
	$(FPU_DIR)/fp_compare.sv \
	$(FPU_DIR)/fp_convert.sv

# SIMT infrastructure sources
SIMT_SRCS = \
	$(SIMT_DIR)/simt_stack.sv \
	$(SIMT_DIR)/warp_context.sv \
	$(SIMT_DIR)/warp_scheduler.sv \
	$(SIMT_DIR)/thread_mask_unit.sv

# Memory sources
MEMORY_SRCS = \
	$(MEMORY_DIR)/mem_coalescing_unit.sv \
	$(MEMORY_DIR)/shared_memory.sv

# Cache sources
CACHE_DIR = $(MEMORY_DIR)/cache
CACHE_SRCS = \
	$(CACHE_DIR)/l1_data_cache.sv \
	$(CACHE_DIR)/l1_instr_cache.sv \
	$(CACHE_DIR)/l2_cache.sv

# Pipeline sources
PIPELINE_SRCS = \
	$(PIPELINE_DIR)/simt_fetch_stage.sv \
	$(PIPELINE_DIR)/simt_decode_stage.sv \
	$(PIPELINE_DIR)/simt_execute_stage.sv \
	$(PIPELINE_DIR)/simt_memory_stage.sv \
	$(PIPELINE_DIR)/simt_writeback_stage.sv \
	$(PIPELINE_DIR)/hazard_scoreboard.sv \
	$(PIPELINE_DIR)/forwarding_unit.sv \
	$(PIPELINE_DIR)/branch_predictor.sv

# Register file sources
REGFILE_SRCS = \
	$(REGFILE_DIR)/simt_regfile.sv

# Core sources
CORE_SRCS = \
	$(CORE_DIR)/simt_core_top.sv

# All SIMT-related sources
ALL_SIMT_SRCS = $(COMMON_SRCS) $(EXEC_SRCS) $(SIMT_SRCS) $(MEMORY_SRCS) \
	$(CACHE_SRCS) $(REGFILE_SRCS) $(PIPELINE_SRCS) $(CORE_SRCS)

# Compilation flags
IVFLAGS = -g2012 -Wall -DSIMULATION

# Output directory
OUT_DIR = out

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

# SIMT Stack testbench
tb_simt_stack: $(OUT_DIR)
	$(IVERILOG) $(IVFLAGS) -o $(OUT_DIR)/$@.vvp \
		$(COMMON_SRCS) \
		$(SIMT_DIR)/simt_stack.sv \
		$(TB_DIR)/tb_simt_stack.sv
	$(VVP) $(OUT_DIR)/$@.vvp

# Warp Scheduler testbench
tb_warp_scheduler: $(OUT_DIR)
	$(IVERILOG) $(IVFLAGS) -o $(OUT_DIR)/$@.vvp \
		$(COMMON_SRCS) \
		$(SIMT_DIR)/warp_scheduler.sv \
		$(TB_DIR)/tb_warp_scheduler.sv
	$(VVP) $(OUT_DIR)/$@.vvp

# SIMT Core testbench
tb_simt_core: $(OUT_DIR)
	$(IVERILOG) $(IVFLAGS) -o $(OUT_DIR)/$@.vvp \
		$(ALL_SIMT_SRCS) \
		$(TB_DIR)/tb_simt_core.sv
	$(VVP) $(OUT_DIR)/$@.vvp

# L1 Data Cache testbench
tb_l1_data_cache: $(OUT_DIR)
	$(IVERILOG) $(IVFLAGS) -o $(OUT_DIR)/$@.vvp \
		$(COMMON_SRCS) \
		$(CACHE_DIR)/l1_data_cache.sv \
		$(TB_DIR)/tb_l1_data_cache.sv
	$(VVP) $(OUT_DIR)/$@.vvp

# Shared Memory testbench
tb_shared_memory: $(OUT_DIR)
	$(IVERILOG) $(IVFLAGS) -o $(OUT_DIR)/$@.vvp \
		$(COMMON_SRCS) \
		$(MEMORY_DIR)/shared_memory.sv \
		$(TB_DIR)/tb_shared_memory.sv
	$(VVP) $(OUT_DIR)/$@.vvp

# Hazard Scoreboard testbench
tb_hazard_scoreboard: $(OUT_DIR)
	$(IVERILOG) $(IVFLAGS) -o $(OUT_DIR)/$@.vvp \
		$(COMMON_SRCS) \
		$(PIPELINE_DIR)/hazard_scoreboard.sv \
		$(TB_DIR)/tb_hazard_scoreboard.sv
	$(VVP) $(OUT_DIR)/$@.vvp

# Forwarding Unit testbench
tb_forwarding_unit: $(OUT_DIR)
	$(IVERILOG) $(IVFLAGS) -o $(OUT_DIR)/$@.vvp \
		$(COMMON_SRCS) \
		$(PIPELINE_DIR)/forwarding_unit.sv \
		$(TB_DIR)/tb_forwarding_unit.sv
	$(VVP) $(OUT_DIR)/$@.vvp

# Run all hazard handling tests
test_hazards: tb_hazard_scoreboard tb_forwarding_unit
	@echo "All hazard handling tests completed"

# Run all memory hierarchy tests
test_memory: tb_l1_data_cache tb_shared_memory
	@echo "All memory hierarchy tests completed"

# Original core testbench (if exists)
tb_core: $(OUT_DIR)
	$(IVERILOG) $(IVFLAGS) -o $(OUT_DIR)/$@.vvp \
		$(COMMON_SRCS) \
		$(EXEC_DIR)/int_alu.sv \
		$(FPU_DIR)/*.sv \
		$(CORE_DIR)/core_top.sv \
		$(MODEL_DIR)/memory_model.sv \
		$(TB_DIR)/tb_core.sv
	$(VVP) $(OUT_DIR)/$@.vvp

# Run all SIMT tests
test_simt: tb_simt_stack tb_warp_scheduler tb_simt_core
	@echo "All SIMT tests completed"

# View waveforms
waves_%:
	$(GTKWAVE) $*.vcd &

# Clean
clean:
	rm -rf $(OUT_DIR) *.vcd

# Help
help:
	@echo "OpenGPU Simulation Makefile"
	@echo ""
	@echo "SIMT Targets:"
	@echo "  tb_simt_stack      - Run SIMT stack testbench"
	@echo "  tb_warp_scheduler  - Run warp scheduler testbench"
	@echo "  tb_simt_core       - Run full SIMT core testbench"
	@echo "  test_simt          - Run all SIMT tests"
	@echo ""
	@echo "Hazard Handling Targets:"
	@echo "  tb_hazard_scoreboard - Run hazard scoreboard testbench"
	@echo "  tb_forwarding_unit   - Run forwarding unit testbench"
	@echo "  test_hazards         - Run all hazard handling tests"
	@echo ""
	@echo "Memory Hierarchy Targets:"
	@echo "  tb_l1_data_cache   - Run L1 data cache testbench"
	@echo "  tb_shared_memory   - Run shared memory testbench"
	@echo "  test_memory        - Run all memory hierarchy tests"
	@echo ""
	@echo "Utility:"
	@echo "  waves_<name>       - View waveforms (e.g., waves_tb_simt_stack)"
	@echo "  clean              - Remove generated files"
	@echo "  help               - Show this message"

.PHONY: tb_simt_stack tb_warp_scheduler tb_simt_core tb_core test_simt \
	tb_l1_data_cache tb_shared_memory test_memory \
	tb_hazard_scoreboard tb_forwarding_unit test_hazards clean help
