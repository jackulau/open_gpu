// SIMT Decode Stage - Instruction decode with warp ID propagation
// Decodes instructions and propagates warp context

module simt_decode_stage
  import pkg_opengpu::*;
(
  input  logic                          clk,
  input  logic                          rst_n,

  // Control
  input  logic                          stall,
  input  logic                          flush,

  // From fetch
  input  logic [INSTR_WIDTH-1:0]        instr,
  input  logic [ADDR_WIDTH-1:0]         pc_in,
  input  logic [WARP_ID_WIDTH-1:0]      warp_id_in,
  input  logic [WARP_SIZE-1:0]          mask_in,
  input  logic                          valid_in,

  // To execute
  output simt_decoded_instr_t           decoded,
  output logic [ADDR_WIDTH-1:0]         pc_out,
  output logic                          valid_out
);

  // Extract instruction fields
  opcode_t opcode;
  logic [REG_ADDR_WIDTH-1:0] rd, rs1, rs2, rs3;
  logic [FUNC_WIDTH-1:0] func;
  logic [IMM16_WIDTH-1:0] imm16;
  logic [IMM21_WIDTH-1:0] imm21;

  assign opcode = instr[OPCODE_MSB:OPCODE_LSB];
  assign rd     = instr[RD_MSB:RD_LSB];
  assign rs1    = instr[RS1_MSB:RS1_LSB];
  assign rs2    = instr[RS2_MSB:RS2_LSB];
  assign func   = instr[FUNC_MSB:FUNC_LSB];
  assign imm16  = instr[IMM16_MSB:IMM16_LSB];
  assign imm21  = instr[IMM21_MSB:IMM21_LSB];
  assign rs3    = instr[RS2_MSB:RS2_LSB];  // For FMA, rs3 uses rs2 field position

  // Decode combinational logic
  decoded_instr_t base_decoded;

  always_comb begin
    // Defaults
    base_decoded.opcode = opcode;
    base_decoded.itype = ITYPE_R;
    base_decoded.alu_op = ALU_NOP;
    base_decoded.fpu_op = FPU_ADD;
    base_decoded.rd = rd;
    base_decoded.rs1 = rs1;
    base_decoded.rs2 = rs2;
    base_decoded.rs3 = rs3;
    base_decoded.imm = '0;
    base_decoded.reg_write = 1'b0;
    base_decoded.mem_read = 1'b0;
    base_decoded.mem_write = 1'b0;
    base_decoded.branch = 1'b0;
    base_decoded.jump = 1'b0;
    base_decoded.is_ret = 1'b0;
    base_decoded.use_imm = 1'b0;
    base_decoded.is_fpu_op = 1'b0;

    case (opcode)
      // Integer arithmetic R-type
      OP_ADD:  begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_ADD; base_decoded.reg_write = 1'b1; end
      OP_SUB:  begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_SUB; base_decoded.reg_write = 1'b1; end
      OP_MUL:  begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_MUL; base_decoded.reg_write = 1'b1; end
      OP_MULH: begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_MULH; base_decoded.reg_write = 1'b1; end
      OP_DIV:  begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_DIV; base_decoded.reg_write = 1'b1; end
      OP_DIVU: begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_DIVU; base_decoded.reg_write = 1'b1; end
      OP_REM:  begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_REM; base_decoded.reg_write = 1'b1; end
      OP_REMU: begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_REMU; base_decoded.reg_write = 1'b1; end

      // Integer arithmetic I-type
      OP_ADDI: begin
        base_decoded.itype = ITYPE_I;
        base_decoded.alu_op = ALU_ADD;
        base_decoded.imm = sign_extend_16(imm16);
        base_decoded.use_imm = 1'b1;
        base_decoded.reg_write = 1'b1;
      end

      // Logical R-type
      OP_AND: begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_AND; base_decoded.reg_write = 1'b1; end
      OP_OR:  begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_OR; base_decoded.reg_write = 1'b1; end
      OP_XOR: begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_XOR; base_decoded.reg_write = 1'b1; end
      OP_NOT: begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_NOT; base_decoded.reg_write = 1'b1; end

      // Logical I-type
      OP_ANDI: begin base_decoded.itype = ITYPE_I; base_decoded.alu_op = ALU_AND; base_decoded.imm = zero_extend(imm16); base_decoded.use_imm = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_ORI:  begin base_decoded.itype = ITYPE_I; base_decoded.alu_op = ALU_OR; base_decoded.imm = zero_extend(imm16); base_decoded.use_imm = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_XORI: begin base_decoded.itype = ITYPE_I; base_decoded.alu_op = ALU_XOR; base_decoded.imm = zero_extend(imm16); base_decoded.use_imm = 1'b1; base_decoded.reg_write = 1'b1; end

      // Shifts R-type
      OP_SLL: begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_SLL; base_decoded.reg_write = 1'b1; end
      OP_SRL: begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_SRL; base_decoded.reg_write = 1'b1; end
      OP_SRA: begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_SRA; base_decoded.reg_write = 1'b1; end

      // Shifts I-type
      OP_SLLI: begin base_decoded.itype = ITYPE_I; base_decoded.alu_op = ALU_SLL; base_decoded.imm = {27'd0, imm16[4:0]}; base_decoded.use_imm = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_SRLI: begin base_decoded.itype = ITYPE_I; base_decoded.alu_op = ALU_SRL; base_decoded.imm = {27'd0, imm16[4:0]}; base_decoded.use_imm = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_SRAI: begin base_decoded.itype = ITYPE_I; base_decoded.alu_op = ALU_SRA; base_decoded.imm = {27'd0, imm16[4:0]}; base_decoded.use_imm = 1'b1; base_decoded.reg_write = 1'b1; end

      // Floating-point
      OP_FADD: begin base_decoded.itype = ITYPE_R; base_decoded.fpu_op = FPU_ADD; base_decoded.is_fpu_op = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_FSUB: begin base_decoded.itype = ITYPE_R; base_decoded.fpu_op = FPU_SUB; base_decoded.is_fpu_op = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_FMUL: begin base_decoded.itype = ITYPE_R; base_decoded.fpu_op = FPU_MUL; base_decoded.is_fpu_op = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_FDIV: begin base_decoded.itype = ITYPE_R; base_decoded.fpu_op = FPU_DIV; base_decoded.is_fpu_op = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_FMADD: begin base_decoded.itype = ITYPE_R; base_decoded.fpu_op = FPU_MADD; base_decoded.is_fpu_op = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_FMSUB: begin base_decoded.itype = ITYPE_R; base_decoded.fpu_op = FPU_MSUB; base_decoded.is_fpu_op = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_FSQRT: begin base_decoded.itype = ITYPE_R; base_decoded.fpu_op = FPU_SQRT; base_decoded.is_fpu_op = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_FABS: begin base_decoded.itype = ITYPE_R; base_decoded.fpu_op = FPU_ABS; base_decoded.is_fpu_op = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_FNEG: begin base_decoded.itype = ITYPE_R; base_decoded.fpu_op = FPU_NEG; base_decoded.is_fpu_op = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_FMIN: begin base_decoded.itype = ITYPE_R; base_decoded.fpu_op = FPU_MIN; base_decoded.is_fpu_op = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_FMAX: begin base_decoded.itype = ITYPE_R; base_decoded.fpu_op = FPU_MAX; base_decoded.is_fpu_op = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_FCVTWS: begin base_decoded.itype = ITYPE_R; base_decoded.fpu_op = FPU_CVTWS; base_decoded.is_fpu_op = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_FCVTSW: begin base_decoded.itype = ITYPE_R; base_decoded.fpu_op = FPU_CVTSW; base_decoded.is_fpu_op = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_FCMPEQ: begin base_decoded.itype = ITYPE_R; base_decoded.fpu_op = FPU_CMPEQ; base_decoded.is_fpu_op = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_FCMPLT: begin base_decoded.itype = ITYPE_R; base_decoded.fpu_op = FPU_CMPLT; base_decoded.is_fpu_op = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_FCMPLE: begin base_decoded.itype = ITYPE_R; base_decoded.fpu_op = FPU_CMPLE; base_decoded.is_fpu_op = 1'b1; base_decoded.reg_write = 1'b1; end

      // Memory load
      OP_LW, OP_LH, OP_LHU, OP_LB, OP_LBU: begin
        base_decoded.itype = ITYPE_I;
        base_decoded.alu_op = ALU_ADD;
        base_decoded.imm = sign_extend_16(imm16);
        base_decoded.use_imm = 1'b1;
        base_decoded.mem_read = 1'b1;
        base_decoded.reg_write = 1'b1;
      end

      // Memory store
      OP_SW, OP_SH, OP_SB: begin
        base_decoded.itype = ITYPE_S;
        base_decoded.alu_op = ALU_ADD;
        base_decoded.imm = sign_extend_16(imm16);
        base_decoded.use_imm = 1'b1;
        base_decoded.mem_write = 1'b1;
      end

      // Comparison R-type
      OP_SLT:  begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_SLT; base_decoded.reg_write = 1'b1; end
      OP_SLTU: begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_SLTU; base_decoded.reg_write = 1'b1; end
      OP_SEQ:  begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_SEQ; base_decoded.reg_write = 1'b1; end
      OP_SNE:  begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_SNE; base_decoded.reg_write = 1'b1; end
      OP_SGE:  begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_SGE; base_decoded.reg_write = 1'b1; end
      OP_SGEU: begin base_decoded.itype = ITYPE_R; base_decoded.alu_op = ALU_SGEU; base_decoded.reg_write = 1'b1; end

      // Comparison I-type
      OP_SLTI:  begin base_decoded.itype = ITYPE_I; base_decoded.alu_op = ALU_SLT; base_decoded.imm = sign_extend_16(imm16); base_decoded.use_imm = 1'b1; base_decoded.reg_write = 1'b1; end
      OP_SLTIU: begin base_decoded.itype = ITYPE_I; base_decoded.alu_op = ALU_SLTU; base_decoded.imm = sign_extend_16(imm16); base_decoded.use_imm = 1'b1; base_decoded.reg_write = 1'b1; end

      // Branch
      OP_BEQ:  begin base_decoded.itype = ITYPE_B; base_decoded.alu_op = ALU_SEQ; base_decoded.imm = sign_extend_16(imm16); base_decoded.branch = 1'b1; end
      OP_BNE:  begin base_decoded.itype = ITYPE_B; base_decoded.alu_op = ALU_SNE; base_decoded.imm = sign_extend_16(imm16); base_decoded.branch = 1'b1; end
      OP_BLT:  begin base_decoded.itype = ITYPE_B; base_decoded.alu_op = ALU_SLT; base_decoded.imm = sign_extend_16(imm16); base_decoded.branch = 1'b1; end
      OP_BGE:  begin base_decoded.itype = ITYPE_B; base_decoded.alu_op = ALU_SGE; base_decoded.imm = sign_extend_16(imm16); base_decoded.branch = 1'b1; end
      OP_BLTU: begin base_decoded.itype = ITYPE_B; base_decoded.alu_op = ALU_SLTU; base_decoded.imm = sign_extend_16(imm16); base_decoded.branch = 1'b1; end
      OP_BGEU: begin base_decoded.itype = ITYPE_B; base_decoded.alu_op = ALU_SGEU; base_decoded.imm = sign_extend_16(imm16); base_decoded.branch = 1'b1; end

      // Jump
      OP_JAL: begin
        base_decoded.itype = ITYPE_U;
        base_decoded.imm = sign_extend_21(imm21);
        base_decoded.jump = 1'b1;
        base_decoded.reg_write = 1'b1;
      end
      OP_JALR: begin
        base_decoded.itype = ITYPE_I;
        base_decoded.imm = sign_extend_16(imm16);
        base_decoded.jump = 1'b1;
        base_decoded.reg_write = 1'b1;
      end
      OP_RET: begin
        base_decoded.itype = ITYPE_R;
        base_decoded.jump = 1'b1;
        base_decoded.is_ret = 1'b1;
      end

      // GPU special
      OP_LUI: begin
        base_decoded.itype = ITYPE_U;
        base_decoded.imm = {imm21, 11'd0};
        base_decoded.alu_op = ALU_PASS_B;
        base_decoded.use_imm = 1'b1;
        base_decoded.reg_write = 1'b1;
      end
      OP_AUIPC: begin
        base_decoded.itype = ITYPE_U;
        base_decoded.imm = {imm21, 11'd0};
        base_decoded.alu_op = ALU_ADD;
        base_decoded.use_imm = 1'b1;
        base_decoded.reg_write = 1'b1;
      end

      // Vote operations
      OP_VOTEALL, OP_VOTEANY, OP_VOTEBAL: begin
        base_decoded.itype = ITYPE_R;
        base_decoded.reg_write = 1'b1;
      end

      // Shuffle operations
      OP_SHFLIDX, OP_SHFLUP, OP_SHFLDN, OP_SHFLXOR: begin
        base_decoded.itype = ITYPE_R;
        base_decoded.reg_write = 1'b1;
      end

      // Bit manipulation
      OP_POPC, OP_CLZ: begin
        base_decoded.itype = ITYPE_R;
        base_decoded.reg_write = 1'b1;
      end

      default: begin
        base_decoded.itype = ITYPE_INV;
      end
    endcase
  end

  // SIMT extension decode
  simt_decoded_instr_t decoded_comb;

  always_comb begin
    decoded_comb.base = base_decoded;
    decoded_comb.warp_id = warp_id_in;
    decoded_comb.active_mask = mask_in;
    decoded_comb.is_vote_op = is_vote_op(opcode);
    decoded_comb.is_shuffle_op = is_shuffle_op(opcode);

    // Vote operation type
    case (opcode)
      OP_VOTEALL: decoded_comb.vote_op = VOTE_ALL;
      OP_VOTEANY: decoded_comb.vote_op = VOTE_ANY;
      OP_VOTEBAL: decoded_comb.vote_op = VOTE_BAL;
      default:    decoded_comb.vote_op = VOTE_ALL;
    endcase

    // Shuffle operation type
    case (opcode)
      OP_SHFLIDX: decoded_comb.shuffle_op = SHFL_IDX;
      OP_SHFLUP:  decoded_comb.shuffle_op = SHFL_UP;
      OP_SHFLDN:  decoded_comb.shuffle_op = SHFL_DOWN;
      OP_SHFLXOR: decoded_comb.shuffle_op = SHFL_XOR;
      default:    decoded_comb.shuffle_op = SHFL_IDX;
    endcase
  end

  // Pipeline register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      decoded <= '0;
      pc_out <= '0;
      valid_out <= 1'b0;
    end else if (flush) begin
      decoded <= '0;
      valid_out <= 1'b0;
    end else if (!stall) begin
      decoded <= decoded_comb;
      pc_out <= pc_in;
      valid_out <= valid_in;
    end
  end

endmodule
