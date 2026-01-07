// Execute stage - ALU ops, branch eval, jump target calc

module execute_stage
  import pkg_opengpu::*;
(
  input  logic                       clk,
  input  logic                       rst_n,

  // From decode
  input  decoded_instr_t             decoded,
  input  logic [ADDR_WIDTH-1:0]      pc_in,
  input  logic                       valid_in,

  // Register data
  input  logic [DATA_WIDTH-1:0]      rs1_data,
  input  logic [DATA_WIDTH-1:0]      rs2_data,

  // Control
  input  logic                       stall,
  input  logic                       flush,

  // To memory stage
  output logic [DATA_WIDTH-1:0]      alu_result,
  output logic [DATA_WIDTH-1:0]      mem_wdata,
  output decoded_instr_t             decoded_out,
  output logic [ADDR_WIDTH-1:0]      pc_out,
  output logic                       valid_out,

  // Branch control
  output logic                       branch_taken,
  output logic [ADDR_WIDTH-1:0]      branch_target
);

  logic [DATA_WIDTH-1:0] operand_a, operand_b;
  logic [DATA_WIDTH-1:0] alu_out;
  logic alu_zero, alu_neg;

  // Operand selection
  assign operand_a = (decoded.opcode == OP_AUIPC) ? pc_in : rs1_data;
  assign operand_b = decoded.use_imm ? decoded.imm : rs2_data;

  // ALU
  int_alu u_int_alu (
    .operand_a (operand_a),
    .operand_b (operand_b),
    .alu_op    (decoded.alu_op),
    .result    (alu_out),
    .zero_flag (alu_zero),
    .neg_flag  (alu_neg)
  );

  // Branch condition
  logic branch_cond;
  always_comb begin
    branch_cond = 1'b0;
    if (decoded.branch) begin
      case (decoded.opcode)
        OP_BEQ:  branch_cond = (rs1_data == rs2_data);
        OP_BNE:  branch_cond = (rs1_data != rs2_data);
        OP_BLT:  branch_cond = ($signed(rs1_data) < $signed(rs2_data));
        OP_BGE:  branch_cond = ($signed(rs1_data) >= $signed(rs2_data));
        OP_BLTU: branch_cond = (rs1_data < rs2_data);
        OP_BGEU: branch_cond = (rs1_data >= rs2_data);
        default: branch_cond = 1'b0;
      endcase
    end
  end

  // Branch/jump target
  logic [ADDR_WIDTH-1:0] target_addr;
  assign target_addr = (decoded.opcode == OP_JALR) ? (rs1_data + decoded.imm) : (pc_in + decoded.imm);

  // Result (JAL/JALR store return address)
  logic [DATA_WIDTH-1:0] result;
  assign result = decoded.jump ? (pc_in + 4) : alu_out;

  // Output registers
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      alu_result    <= '0;
      mem_wdata     <= '0;
      decoded_out   <= '0;
      pc_out        <= '0;
      valid_out     <= 1'b0;
      branch_taken  <= 1'b0;
      branch_target <= '0;
    end else if (flush) begin
      alu_result    <= '0;
      valid_out     <= 1'b0;
      branch_taken  <= 1'b0;
    end else if (!stall) begin
      alu_result    <= result;
      mem_wdata     <= rs2_data;
      decoded_out   <= decoded;
      pc_out        <= pc_in;
      valid_out     <= valid_in;
      branch_taken  <= valid_in && ((decoded.branch && branch_cond) || decoded.jump);
      branch_target <= target_addr;
    end
  end

endmodule
