// Forwarding Unit - Muxes data from pipeline stages for hazard bypass
// Supports forwarding from EX, MEM, and WB stages with proper priority

module forwarding_unit
  import pkg_opengpu::*;
#(
  parameter int NUM_WARPS = WARPS_PER_CORE
)(
  // ========================================================================
  // Current instruction info (from decode stage)
  // ========================================================================
  input  logic [WARP_ID_WIDTH-1:0]      decode_warp_id,
  input  logic [REG_ADDR_WIDTH-1:0]     decode_rs1,
  input  logic [REG_ADDR_WIDTH-1:0]     decode_rs2,
  input  logic [REG_ADDR_WIDTH-1:0]     decode_rs3,

  // ========================================================================
  // Register file data (default source)
  // ========================================================================
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rf_rs1_data,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rf_rs2_data,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rf_rs3_data,

  // ========================================================================
  // Execute stage data (highest priority for forwarding)
  // ========================================================================
  input  logic                          ex_valid,
  input  logic [WARP_ID_WIDTH-1:0]      ex_warp_id,
  input  logic [REG_ADDR_WIDTH-1:0]     ex_rd,
  input  logic                          ex_reg_write,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] ex_result,

  // ========================================================================
  // Memory stage data (medium priority)
  // ========================================================================
  input  logic                          mem_valid,
  input  logic [WARP_ID_WIDTH-1:0]      mem_warp_id,
  input  logic [REG_ADDR_WIDTH-1:0]     mem_rd,
  input  logic                          mem_reg_write,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] mem_result,

  // ========================================================================
  // Writeback stage data (lowest forwarding priority)
  // ========================================================================
  input  logic                          wb_valid,
  input  logic [WARP_ID_WIDTH-1:0]      wb_warp_id,
  input  logic [REG_ADDR_WIDTH-1:0]     wb_rd,
  input  logic                          wb_reg_write,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] wb_result,

  // ========================================================================
  // Forwarded outputs
  // ========================================================================
  output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] fwd_rs1_data,
  output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] fwd_rs2_data,
  output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] fwd_rs3_data,

  // Forwarding status (for debugging/monitoring)
  output logic [1:0]                    fwd_rs1_src,  // 0=RF, 1=EX, 2=MEM, 3=WB
  output logic [1:0]                    fwd_rs2_src,
  output logic [1:0]                    fwd_rs3_src
);

  // ========================================================================
  // Source encoding
  // ========================================================================
  localparam logic [1:0] SRC_RF  = 2'd0;
  localparam logic [1:0] SRC_EX  = 2'd1;
  localparam logic [1:0] SRC_MEM = 2'd2;
  localparam logic [1:0] SRC_WB  = 2'd3;

  // ========================================================================
  // Match detection
  // ========================================================================

  // Check if EX stage has matching write
  logic ex_match_rs1, ex_match_rs2, ex_match_rs3;
  assign ex_match_rs1 = ex_valid && ex_reg_write &&
                        (ex_warp_id == decode_warp_id) &&
                        (ex_rd == decode_rs1) && (decode_rs1 != '0);

  assign ex_match_rs2 = ex_valid && ex_reg_write &&
                        (ex_warp_id == decode_warp_id) &&
                        (ex_rd == decode_rs2) && (decode_rs2 != '0);

  assign ex_match_rs3 = ex_valid && ex_reg_write &&
                        (ex_warp_id == decode_warp_id) &&
                        (ex_rd == decode_rs3) && (decode_rs3 != '0);

  // Check if MEM stage has matching write
  logic mem_match_rs1, mem_match_rs2, mem_match_rs3;
  assign mem_match_rs1 = mem_valid && mem_reg_write &&
                         (mem_warp_id == decode_warp_id) &&
                         (mem_rd == decode_rs1) && (decode_rs1 != '0);

  assign mem_match_rs2 = mem_valid && mem_reg_write &&
                         (mem_warp_id == decode_warp_id) &&
                         (mem_rd == decode_rs2) && (decode_rs2 != '0);

  assign mem_match_rs3 = mem_valid && mem_reg_write &&
                         (mem_warp_id == decode_warp_id) &&
                         (mem_rd == decode_rs3) && (decode_rs3 != '0);

  // Check if WB stage has matching write
  logic wb_match_rs1, wb_match_rs2, wb_match_rs3;
  assign wb_match_rs1 = wb_valid && wb_reg_write &&
                        (wb_warp_id == decode_warp_id) &&
                        (wb_rd == decode_rs1) && (decode_rs1 != '0);

  assign wb_match_rs2 = wb_valid && wb_reg_write &&
                        (wb_warp_id == decode_warp_id) &&
                        (wb_rd == decode_rs2) && (decode_rs2 != '0);

  assign wb_match_rs3 = wb_valid && wb_reg_write &&
                        (wb_warp_id == decode_warp_id) &&
                        (wb_rd == decode_rs3) && (decode_rs3 != '0);

  // ========================================================================
  // Forwarding MUX for RS1
  // Priority: EX > MEM > WB > RF
  // ========================================================================

  always_comb begin
    if (ex_match_rs1) begin
      fwd_rs1_data = ex_result;
      fwd_rs1_src = SRC_EX;
    end else if (mem_match_rs1) begin
      fwd_rs1_data = mem_result;
      fwd_rs1_src = SRC_MEM;
    end else if (wb_match_rs1) begin
      fwd_rs1_data = wb_result;
      fwd_rs1_src = SRC_WB;
    end else begin
      fwd_rs1_data = rf_rs1_data;
      fwd_rs1_src = SRC_RF;
    end
  end

  // ========================================================================
  // Forwarding MUX for RS2
  // ========================================================================

  always_comb begin
    if (ex_match_rs2) begin
      fwd_rs2_data = ex_result;
      fwd_rs2_src = SRC_EX;
    end else if (mem_match_rs2) begin
      fwd_rs2_data = mem_result;
      fwd_rs2_src = SRC_MEM;
    end else if (wb_match_rs2) begin
      fwd_rs2_data = wb_result;
      fwd_rs2_src = SRC_WB;
    end else begin
      fwd_rs2_data = rf_rs2_data;
      fwd_rs2_src = SRC_RF;
    end
  end

  // ========================================================================
  // Forwarding MUX for RS3
  // ========================================================================

  always_comb begin
    if (ex_match_rs3) begin
      fwd_rs3_data = ex_result;
      fwd_rs3_src = SRC_EX;
    end else if (mem_match_rs3) begin
      fwd_rs3_data = mem_result;
      fwd_rs3_src = SRC_MEM;
    end else if (wb_match_rs3) begin
      fwd_rs3_data = wb_result;
      fwd_rs3_src = SRC_WB;
    end else begin
      fwd_rs3_data = rf_rs3_data;
      fwd_rs3_src = SRC_RF;
    end
  end

endmodule
