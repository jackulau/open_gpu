// Fetch stage - PC management and instruction fetch

module fetch_stage
  import pkg_opengpu::*;
(
  input  logic                       clk,
  input  logic                       rst_n,
  
  // Control
  input  logic                       enable,
  input  logic                       stall,
  input  logic                       flush,

  // PC control
  input  logic                       pc_load,
  input  logic [ADDR_WIDTH-1:0]      pc_load_val,
  input  logic [ADDR_WIDTH-1:0]      pc_start,
  input  logic                       start,

  // Instruction memory
  output logic                       imem_req,
  output logic [ADDR_WIDTH-1:0]      imem_addr,
  input  logic [INSTR_WIDTH-1:0]     imem_rdata,
  input  logic                       imem_valid,

  // To decode
  output logic [INSTR_WIDTH-1:0]     instr,
  output logic [ADDR_WIDTH-1:0]      pc,
  output logic                       valid
);

  logic [ADDR_WIDTH-1:0] pc_reg, pc_next;
  logic fetch_pending;

  // Next PC
  always_comb begin
    if (start)
      pc_next = pc_start;
    else if (pc_load)
      pc_next = pc_load_val;
    else if (enable && !stall && imem_valid)
      pc_next = pc_reg + 4;
    else
      pc_next = pc_reg;
  end

  // PC register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      pc_reg <= '0;
    else if (flush)
      pc_reg <= pc_load_val;
    else if (!stall)
      pc_reg <= pc_next;
  end

  // Fetch pending
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      fetch_pending <= 1'b0;
    else if (flush)
      fetch_pending <= 1'b0;
    else if (imem_req && !imem_valid)
      fetch_pending <= 1'b1;
    else if (imem_valid)
      fetch_pending <= 1'b0;
  end

  assign imem_req  = enable && !stall && !fetch_pending;
  assign imem_addr = pc_reg;

  // Output to decode
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr <= INSTR_NOP;
      pc    <= '0;
      valid <= 1'b0;
    end else if (flush) begin
      instr <= INSTR_NOP;
      valid <= 1'b0;
    end else if (!stall && imem_valid) begin
      instr <= imem_rdata;
      pc    <= pc_reg;
      valid <= 1'b1;
    end else if (!stall) begin
      instr <= INSTR_NOP;
      valid <= 1'b0;
    end
  end

endmodule
