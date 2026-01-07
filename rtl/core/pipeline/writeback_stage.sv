// Writeback stage - register file write and completion signals

module writeback_stage
  import pkg_opengpu::*;
(
  input  logic                       clk,
  input  logic                       rst_n,

  // From memory stage
  input  logic [DATA_WIDTH-1:0]      result,
  input  decoded_instr_t             decoded,
  input  logic [ADDR_WIDTH-1:0]      pc_in,
  input  logic                       valid_in,

  // Control
  input  logic                       stall,
  input  logic                       flush,

  // Register file write
  output logic                       rf_we,
  output logic [REG_ADDR_WIDTH-1:0]  rf_waddr,
  output logic [DATA_WIDTH-1:0]      rf_wdata,

  // Completion
  output logic                       instr_done,
  output logic                       thread_done
);

  assign rf_we    = valid_in && decoded.reg_write && (decoded.rd != REG_ZERO) && !stall && !flush;
  assign rf_waddr = decoded.rd;
  assign rf_wdata = result;

  assign instr_done  = valid_in && !stall && !flush;
  assign thread_done = valid_in && decoded.is_ret && !stall && !flush;

endmodule
