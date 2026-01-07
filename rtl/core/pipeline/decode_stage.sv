// Decode stage - instruction decode and control signal generation

module decode_stage
  import pkg_opengpu::*;
(
  input  logic                       clk,
  input  logic                       rst_n,

  // From fetch
  input  logic [INSTR_WIDTH-1:0]     instr,
  input  logic [ADDR_WIDTH-1:0]      pc,
  input  logic                       valid_in,

  // Control
  input  logic                       stall,
  input  logic                       flush,

  // Register file addresses
  output logic [REG_ADDR_WIDTH-1:0]  rs1_addr,
  output logic [REG_ADDR_WIDTH-1:0]  rs2_addr,

  // To execute
  output decoded_instr_t             decoded,
  output logic [ADDR_WIDTH-1:0]      pc_out,
  output logic                       valid_out
);

  // Field extraction
  opcode_t opcode;
  logic [REG_ADDR_WIDTH-1:0] rd_field, rs1_field, rs2_field;
  logic [IMM16_WIDTH-1:0] imm16;
  logic [IMM21_WIDTH-1:0] imm21;

  assign opcode    = instr[OPCODE_MSB:OPCODE_LSB];
  assign rd_field  = instr[RD_MSB:RD_LSB];
  assign rs1_field = instr[RS1_MSB:RS1_LSB];
  assign rs2_field = instr[RS2_MSB:RS2_LSB];
  assign imm16     = instr[IMM16_MSB:IMM16_LSB];
  assign imm21     = instr[IMM21_MSB:IMM21_LSB];

  assign rs1_addr = rs1_field;
  assign rs2_addr = rs2_field;

  // Decode logic
  decoded_instr_t decoded_comb;

  always_comb begin
    decoded_comb = '0;
    decoded_comb.opcode = opcode;
    decoded_comb.rd     = rd_field;
    decoded_comb.rs1    = rs1_field;
    decoded_comb.rs2    = rs2_field;
    decoded_comb.alu_op = ALU_NOP;
    decoded_comb.itype  = ITYPE_INV;

    case (opcode)
      // R-type arithmetic
      OP_ADD:  begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_ADD;  decoded_comb.reg_write = 1'b1; end
      OP_SUB:  begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_SUB;  decoded_comb.reg_write = 1'b1; end
      OP_MUL:  begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_MUL;  decoded_comb.reg_write = 1'b1; end
      OP_MULH: begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_MULH; decoded_comb.reg_write = 1'b1; end
      OP_DIV:  begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_DIV;  decoded_comb.reg_write = 1'b1; end
      OP_DIVU: begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_DIVU; decoded_comb.reg_write = 1'b1; end
      OP_REM:  begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_REM;  decoded_comb.reg_write = 1'b1; end
      OP_REMU: begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_REMU; decoded_comb.reg_write = 1'b1; end

      // I-type arithmetic
      OP_ADDI: begin
        decoded_comb.itype = ITYPE_I; decoded_comb.alu_op = ALU_ADD;
        decoded_comb.imm = sign_extend_16(imm16);
        decoded_comb.reg_write = 1'b1; decoded_comb.use_imm = 1'b1;
      end

      // R-type logical
      OP_AND:  begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_AND;  decoded_comb.reg_write = 1'b1; end
      OP_OR:   begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_OR;   decoded_comb.reg_write = 1'b1; end
      OP_XOR:  begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_XOR;  decoded_comb.reg_write = 1'b1; end
      OP_NOT:  begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_NOT;  decoded_comb.reg_write = 1'b1; end

      // I-type logical
      OP_ANDI: begin
        decoded_comb.itype = ITYPE_I; decoded_comb.alu_op = ALU_AND;
        decoded_comb.imm = zero_extend(imm16);
        decoded_comb.reg_write = 1'b1; decoded_comb.use_imm = 1'b1;
      end
      OP_ORI: begin
        decoded_comb.itype = ITYPE_I; decoded_comb.alu_op = ALU_OR;
        decoded_comb.imm = zero_extend(imm16);
        decoded_comb.reg_write = 1'b1; decoded_comb.use_imm = 1'b1;
      end
      OP_XORI: begin
        decoded_comb.itype = ITYPE_I; decoded_comb.alu_op = ALU_XOR;
        decoded_comb.imm = zero_extend(imm16);
        decoded_comb.reg_write = 1'b1; decoded_comb.use_imm = 1'b1;
      end

      // R-type shift
      OP_SLL: begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_SLL; decoded_comb.reg_write = 1'b1; end
      OP_SRL: begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_SRL; decoded_comb.reg_write = 1'b1; end
      OP_SRA: begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_SRA; decoded_comb.reg_write = 1'b1; end

      // I-type shift
      OP_SLLI: begin
        decoded_comb.itype = ITYPE_I; decoded_comb.alu_op = ALU_SLL;
        decoded_comb.imm = {27'd0, imm16[4:0]};
        decoded_comb.reg_write = 1'b1; decoded_comb.use_imm = 1'b1;
      end
      OP_SRLI: begin
        decoded_comb.itype = ITYPE_I; decoded_comb.alu_op = ALU_SRL;
        decoded_comb.imm = {27'd0, imm16[4:0]};
        decoded_comb.reg_write = 1'b1; decoded_comb.use_imm = 1'b1;
      end
      OP_SRAI: begin
        decoded_comb.itype = ITYPE_I; decoded_comb.alu_op = ALU_SRA;
        decoded_comb.imm = {27'd0, imm16[4:0]};
        decoded_comb.reg_write = 1'b1; decoded_comb.use_imm = 1'b1;
      end

      // R-type comparison
      OP_SLT:  begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_SLT;  decoded_comb.reg_write = 1'b1; end
      OP_SLTU: begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_SLTU; decoded_comb.reg_write = 1'b1; end
      OP_SEQ:  begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_SEQ;  decoded_comb.reg_write = 1'b1; end
      OP_SNE:  begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_SNE;  decoded_comb.reg_write = 1'b1; end
      OP_SGE:  begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_SGE;  decoded_comb.reg_write = 1'b1; end
      OP_SGEU: begin decoded_comb.itype = ITYPE_R; decoded_comb.alu_op = ALU_SGEU; decoded_comb.reg_write = 1'b1; end

      // I-type comparison
      OP_SLTI: begin
        decoded_comb.itype = ITYPE_I; decoded_comb.alu_op = ALU_SLT;
        decoded_comb.imm = sign_extend_16(imm16);
        decoded_comb.reg_write = 1'b1; decoded_comb.use_imm = 1'b1;
      end
      OP_SLTIU: begin
        decoded_comb.itype = ITYPE_I; decoded_comb.alu_op = ALU_SLTU;
        decoded_comb.imm = sign_extend_16(imm16);
        decoded_comb.reg_write = 1'b1; decoded_comb.use_imm = 1'b1;
      end

      // Loads
      OP_LW, OP_LH, OP_LHU, OP_LB, OP_LBU: begin
        decoded_comb.itype = ITYPE_MEM; decoded_comb.alu_op = ALU_ADD;
        decoded_comb.imm = sign_extend_16(imm16);
        decoded_comb.reg_write = 1'b1; decoded_comb.mem_read = 1'b1; decoded_comb.use_imm = 1'b1;
      end

      // Stores (rd field is rs2)
      OP_SW, OP_SH, OP_SB: begin
        decoded_comb.itype = ITYPE_S; decoded_comb.alu_op = ALU_ADD;
        decoded_comb.imm = sign_extend_16(imm16);
        decoded_comb.mem_write = 1'b1; decoded_comb.use_imm = 1'b1;
        decoded_comb.rs2 = rd_field;
      end

      // Branches
      OP_BEQ:  begin decoded_comb.itype = ITYPE_B; decoded_comb.alu_op = ALU_SEQ;  decoded_comb.imm = sign_extend_16(imm16); decoded_comb.branch = 1'b1; decoded_comb.rs2 = rs2_field; end
      OP_BNE:  begin decoded_comb.itype = ITYPE_B; decoded_comb.alu_op = ALU_SNE;  decoded_comb.imm = sign_extend_16(imm16); decoded_comb.branch = 1'b1; decoded_comb.rs2 = rs2_field; end
      OP_BLT:  begin decoded_comb.itype = ITYPE_B; decoded_comb.alu_op = ALU_SLT;  decoded_comb.imm = sign_extend_16(imm16); decoded_comb.branch = 1'b1; decoded_comb.rs2 = rs2_field; end
      OP_BGE:  begin decoded_comb.itype = ITYPE_B; decoded_comb.alu_op = ALU_SGE;  decoded_comb.imm = sign_extend_16(imm16); decoded_comb.branch = 1'b1; decoded_comb.rs2 = rs2_field; end
      OP_BLTU: begin decoded_comb.itype = ITYPE_B; decoded_comb.alu_op = ALU_SLTU; decoded_comb.imm = sign_extend_16(imm16); decoded_comb.branch = 1'b1; decoded_comb.rs2 = rs2_field; end
      OP_BGEU: begin decoded_comb.itype = ITYPE_B; decoded_comb.alu_op = ALU_SGEU; decoded_comb.imm = sign_extend_16(imm16); decoded_comb.branch = 1'b1; decoded_comb.rs2 = rs2_field; end

      // Jumps
      OP_JAL: begin
        decoded_comb.itype = ITYPE_U; decoded_comb.alu_op = ALU_ADD;
        decoded_comb.imm = sign_extend_21(imm21);
        decoded_comb.reg_write = 1'b1; decoded_comb.jump = 1'b1; decoded_comb.use_imm = 1'b1;
      end
      OP_JALR: begin
        decoded_comb.itype = ITYPE_I; decoded_comb.alu_op = ALU_ADD;
        decoded_comb.imm = sign_extend_16(imm16);
        decoded_comb.reg_write = 1'b1; decoded_comb.jump = 1'b1; decoded_comb.use_imm = 1'b1;
      end

      // Control
      OP_RET: begin decoded_comb.itype = ITYPE_CTRL; decoded_comb.is_ret = 1'b1; end

      // Upper immediate
      OP_LUI: begin
        decoded_comb.itype = ITYPE_U; decoded_comb.alu_op = ALU_PASS_B;
        decoded_comb.imm = {imm21, 11'd0};
        decoded_comb.reg_write = 1'b1; decoded_comb.use_imm = 1'b1;
      end
      OP_AUIPC: begin
        decoded_comb.itype = ITYPE_U; decoded_comb.alu_op = ALU_ADD;
        decoded_comb.imm = {imm21, 11'd0};
        decoded_comb.reg_write = 1'b1; decoded_comb.use_imm = 1'b1;
      end

      default: begin
        decoded_comb.itype = ITYPE_INV;
        decoded_comb.alu_op = ALU_NOP;
      end
    endcase
  end

  // Output register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      decoded   <= '0;
      pc_out    <= '0;
      valid_out <= 1'b0;
    end else if (flush) begin
      decoded   <= '0;
      valid_out <= 1'b0;
    end else if (!stall) begin
      decoded   <= decoded_comb;
      pc_out    <= pc;
      valid_out <= valid_in;
    end
  end

endmodule
