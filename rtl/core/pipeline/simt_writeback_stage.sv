// SIMT Writeback Stage - Masked register writeback for all lanes
// Writes results to register file respecting active mask

module simt_writeback_stage
  import pkg_opengpu::*;
(
  input  logic                          clk,
  input  logic                          rst_n,

  // Control
  input  logic                          stall,
  input  logic                          flush,

  // From memory stage
  input  simt_decoded_instr_t           decoded,
  input  logic [ADDR_WIDTH-1:0]         pc_in,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] result,
  input  logic                          valid_in,

  // Register file write interface
  output logic [WARP_ID_WIDTH-1:0]      rf_warp_id,
  output logic [REG_ADDR_WIDTH-1:0]     rf_rd_addr,
  output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rf_rd_data,
  output logic [WARP_SIZE-1:0]          rf_wr_mask,
  output logic                          rf_we,

  // Completion signals
  output logic                          instr_complete,
  output logic [WARP_ID_WIDTH-1:0]      complete_warp_id
);

  // Writeback control
  logic do_writeback;
  assign do_writeback = valid_in && decoded.base.reg_write && !stall && !flush;

  // Register file write signals
  assign rf_warp_id = decoded.warp_id;
  assign rf_rd_addr = decoded.base.rd;
  assign rf_rd_data = result;
  assign rf_wr_mask = decoded.active_mask;  // Only write to active lanes
  assign rf_we = do_writeback && (decoded.base.rd != '0);  // Never write to x0

  // Instruction completion
  assign instr_complete = valid_in && !stall && !flush;
  assign complete_warp_id = decoded.warp_id;

endmodule
