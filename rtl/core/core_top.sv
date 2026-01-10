// GPU compute core - FSM-based sequential execution

module core_top
  import pkg_opengpu::*;
(
  input  logic                       clk,
  input  logic                       rst_n,

  // Control
  input  logic                       start,
  input  logic [ADDR_WIDTH-1:0]      pc_start,
  output logic                       done,
  output logic                       busy,

  // GPU context
  input  logic [DATA_WIDTH-1:0]      thread_idx,
  input  logic [DATA_WIDTH-1:0]      block_idx,
  input  logic [DATA_WIDTH-1:0]      block_dim,
  input  logic [DATA_WIDTH-1:0]      grid_dim,
  input  logic [DATA_WIDTH-1:0]      warp_idx,
  input  logic [DATA_WIDTH-1:0]      lane_idx,

  // Instruction memory
  output logic                       imem_req,
  output logic [ADDR_WIDTH-1:0]      imem_addr,
  input  logic [INSTR_WIDTH-1:0]     imem_rdata,
  input  logic                       imem_valid,

  // Data memory
  output logic                       dmem_req,
  output logic                       dmem_we,
  output logic [ADDR_WIDTH-1:0]      dmem_addr,
  output logic [DATA_WIDTH-1:0]      dmem_wdata,
  output logic [3:0]                 dmem_be,
  input  logic [DATA_WIDTH-1:0]      dmem_rdata,
  input  logic                       dmem_valid
);

  core_state_t state, next_state;

  logic [ADDR_WIDTH-1:0] pc_reg;
  logic [INSTR_WIDTH-1:0] instr_reg;
  decoded_instr_t decoded_instr;

  // Register file
  logic [REG_ADDR_WIDTH-1:0] rs1_addr, rs2_addr;
  logic [DATA_WIDTH-1:0] rs1_data, rs2_data;
  logic rf_we;
  logic [REG_ADDR_WIDTH-1:0] rf_waddr;
  logic [DATA_WIDTH-1:0] rf_wdata;
  logic rf_init;

  // ALU
  logic [DATA_WIDTH-1:0] alu_result;
  logic alu_zero, alu_neg;
  logic [DATA_WIDTH-1:0] alu_op_a, alu_op_b;

  // Branch
  logic branch_taken;
  logic [ADDR_WIDTH-1:0] branch_target;
  logic [DATA_WIDTH-1:0] mem_result;

  vector_regfile u_regfile (
    .clk(clk), .rst_n(rst_n),
    .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
    .rs1_data(rs1_data), .rs2_data(rs2_data),
    .we(rf_we), .rd_addr(rf_waddr), .rd_data(rf_wdata),
    .init_context(rf_init),
    .thread_idx(thread_idx), .block_idx(block_idx),
    .block_dim(block_dim), .grid_dim(grid_dim),
    .warp_idx(warp_idx), .lane_idx(lane_idx)
  );

  int_alu u_alu (
    .operand_a(alu_op_a), .operand_b(alu_op_b),
    .alu_op(decoded_instr.alu_op),
    .result(alu_result), .zero_flag(alu_zero), .neg_flag(alu_neg)
  );

  // Decode
  assign rs1_addr = instr_reg[RS1_MSB:RS1_LSB];

  always_comb begin
    rs2_addr = is_store_op(instr_reg[OPCODE_MSB:OPCODE_LSB]) ?
               instr_reg[RD_MSB:RD_LSB] : instr_reg[RS2_MSB:RS2_LSB];
  end

  always_comb begin
    decoded_instr = '0;
    decoded_instr.opcode = instr_reg[OPCODE_MSB:OPCODE_LSB];
    decoded_instr.rd     = instr_reg[RD_MSB:RD_LSB];
    decoded_instr.rs1    = instr_reg[RS1_MSB:RS1_LSB];
    decoded_instr.rs2    = rs2_addr;

    case (decoded_instr.opcode)
      OP_ADD:  begin decoded_instr.alu_op = ALU_ADD;  decoded_instr.reg_write = 1'b1; end
      OP_SUB:  begin decoded_instr.alu_op = ALU_SUB;  decoded_instr.reg_write = 1'b1; end
      OP_MUL:  begin decoded_instr.alu_op = ALU_MUL;  decoded_instr.reg_write = 1'b1; end
      OP_DIV:  begin decoded_instr.alu_op = ALU_DIV;  decoded_instr.reg_write = 1'b1; end
      OP_REM:  begin decoded_instr.alu_op = ALU_REM;  decoded_instr.reg_write = 1'b1; end

      OP_ADDI: begin
        decoded_instr.alu_op = ALU_ADD;
        decoded_instr.imm = sign_extend_16(instr_reg[IMM16_MSB:IMM16_LSB]);
        decoded_instr.reg_write = 1'b1; decoded_instr.use_imm = 1'b1;
      end

      OP_AND:  begin decoded_instr.alu_op = ALU_AND;  decoded_instr.reg_write = 1'b1; end
      OP_OR:   begin decoded_instr.alu_op = ALU_OR;   decoded_instr.reg_write = 1'b1; end
      OP_XOR:  begin decoded_instr.alu_op = ALU_XOR;  decoded_instr.reg_write = 1'b1; end
      OP_NOT:  begin decoded_instr.alu_op = ALU_NOT;  decoded_instr.reg_write = 1'b1; end

      OP_ANDI: begin
        decoded_instr.alu_op = ALU_AND;
        decoded_instr.imm = {16'd0, instr_reg[IMM16_MSB:IMM16_LSB]};
        decoded_instr.reg_write = 1'b1; decoded_instr.use_imm = 1'b1;
      end
      OP_ORI: begin
        decoded_instr.alu_op = ALU_OR;
        decoded_instr.imm = {16'd0, instr_reg[IMM16_MSB:IMM16_LSB]};
        decoded_instr.reg_write = 1'b1; decoded_instr.use_imm = 1'b1;
      end

      OP_SLL:  begin decoded_instr.alu_op = ALU_SLL;  decoded_instr.reg_write = 1'b1; end
      OP_SRL:  begin decoded_instr.alu_op = ALU_SRL;  decoded_instr.reg_write = 1'b1; end
      OP_SRA:  begin decoded_instr.alu_op = ALU_SRA;  decoded_instr.reg_write = 1'b1; end

      OP_SLLI: begin
        decoded_instr.alu_op = ALU_SLL;
        decoded_instr.imm = {27'd0, instr_reg[4:0]};
        decoded_instr.reg_write = 1'b1; decoded_instr.use_imm = 1'b1;
      end
      OP_SRLI: begin
        decoded_instr.alu_op = ALU_SRL;
        decoded_instr.imm = {27'd0, instr_reg[4:0]};
        decoded_instr.reg_write = 1'b1; decoded_instr.use_imm = 1'b1;
      end

      OP_SLT:  begin decoded_instr.alu_op = ALU_SLT;  decoded_instr.reg_write = 1'b1; end
      OP_SLTU: begin decoded_instr.alu_op = ALU_SLTU; decoded_instr.reg_write = 1'b1; end
      OP_SEQ:  begin decoded_instr.alu_op = ALU_SEQ;  decoded_instr.reg_write = 1'b1; end
      OP_SNE:  begin decoded_instr.alu_op = ALU_SNE;  decoded_instr.reg_write = 1'b1; end

      OP_SLTI: begin
        decoded_instr.alu_op = ALU_SLT;
        decoded_instr.imm = sign_extend_16(instr_reg[IMM16_MSB:IMM16_LSB]);
        decoded_instr.reg_write = 1'b1; decoded_instr.use_imm = 1'b1;
      end

      OP_LW, OP_LH, OP_LHU, OP_LB, OP_LBU: begin
        decoded_instr.alu_op = ALU_ADD;
        decoded_instr.imm = sign_extend_16(instr_reg[IMM16_MSB:IMM16_LSB]);
        decoded_instr.reg_write = 1'b1; decoded_instr.mem_read = 1'b1; decoded_instr.use_imm = 1'b1;
      end

      OP_SW, OP_SH, OP_SB: begin
        decoded_instr.alu_op = ALU_ADD;
        decoded_instr.imm = sign_extend_16(instr_reg[IMM16_MSB:IMM16_LSB]);
        decoded_instr.mem_write = 1'b1; decoded_instr.use_imm = 1'b1;
      end

      OP_BEQ:  begin decoded_instr.alu_op = ALU_SEQ;  decoded_instr.branch = 1'b1; decoded_instr.imm = sign_extend_16(instr_reg[IMM16_MSB:IMM16_LSB]); end
      OP_BNE:  begin decoded_instr.alu_op = ALU_SNE;  decoded_instr.branch = 1'b1; decoded_instr.imm = sign_extend_16(instr_reg[IMM16_MSB:IMM16_LSB]); end
      OP_BLT:  begin decoded_instr.alu_op = ALU_SLT;  decoded_instr.branch = 1'b1; decoded_instr.imm = sign_extend_16(instr_reg[IMM16_MSB:IMM16_LSB]); end
      OP_BGE:  begin decoded_instr.alu_op = ALU_SGE;  decoded_instr.branch = 1'b1; decoded_instr.imm = sign_extend_16(instr_reg[IMM16_MSB:IMM16_LSB]); end
      OP_BLTU: begin decoded_instr.alu_op = ALU_SLTU; decoded_instr.branch = 1'b1; decoded_instr.imm = sign_extend_16(instr_reg[IMM16_MSB:IMM16_LSB]); end
      OP_BGEU: begin decoded_instr.alu_op = ALU_SGEU; decoded_instr.branch = 1'b1; decoded_instr.imm = sign_extend_16(instr_reg[IMM16_MSB:IMM16_LSB]); end

      OP_JAL: begin
        decoded_instr.alu_op = ALU_ADD;
        decoded_instr.imm = sign_extend_21(instr_reg[IMM21_MSB:IMM21_LSB]);
        decoded_instr.reg_write = 1'b1; decoded_instr.jump = 1'b1;
      end
      OP_JALR: begin
        decoded_instr.alu_op = ALU_ADD;
        decoded_instr.imm = sign_extend_16(instr_reg[IMM16_MSB:IMM16_LSB]);
        decoded_instr.reg_write = 1'b1; decoded_instr.jump = 1'b1; decoded_instr.use_imm = 1'b1;
      end

      OP_RET: decoded_instr.is_ret = 1'b1;

      OP_LUI: begin
        decoded_instr.alu_op = ALU_PASS_B;
        decoded_instr.imm = {instr_reg[IMM21_MSB:IMM21_LSB], 11'd0};
        decoded_instr.reg_write = 1'b1; decoded_instr.use_imm = 1'b1;
      end

      default: decoded_instr.alu_op = ALU_NOP;
    endcase
  end

  // ALU operands
  always_comb begin
    alu_op_a = (decoded_instr.opcode == OP_AUIPC) ? pc_reg : rs1_data;
    alu_op_b = decoded_instr.use_imm ? decoded_instr.imm : rs2_data;
  end

  // Branch evaluation
  always_comb begin
    branch_taken = 1'b0;
    if (decoded_instr.branch) begin
      case (decoded_instr.opcode)
        OP_BEQ:  branch_taken = (rs1_data == rs2_data);
        OP_BNE:  branch_taken = (rs1_data != rs2_data);
        OP_BLT:  branch_taken = ($signed(rs1_data) < $signed(rs2_data));
        OP_BGE:  branch_taken = ($signed(rs1_data) >= $signed(rs2_data));
        OP_BLTU: branch_taken = (rs1_data < rs2_data);
        OP_BGEU: branch_taken = (rs1_data >= rs2_data);
        default: branch_taken = 1'b0;
      endcase
    end else if (decoded_instr.jump) begin
      branch_taken = 1'b1;
    end
  end

  always_comb begin
    branch_target = (decoded_instr.opcode == OP_JALR) ?
                    (rs1_data + decoded_instr.imm) : (pc_reg + decoded_instr.imm);
  end

  // Memory interface
  assign imem_req  = (state == CORE_FETCH);
  assign imem_addr = pc_reg;

  assign dmem_req   = (state == CORE_MEMORY) && (decoded_instr.mem_read || decoded_instr.mem_write);
  assign dmem_we    = decoded_instr.mem_write;
  assign dmem_addr  = {alu_result[ADDR_WIDTH-1:2], 2'b00};
  assign dmem_wdata = rs2_data;

  always_comb begin
    case (decoded_instr.opcode)
      OP_SB, OP_LB, OP_LBU: dmem_be = 4'b0001 << alu_result[1:0];
      OP_SH, OP_LH, OP_LHU: dmem_be = alu_result[1] ? 4'b1100 : 4'b0011;
      default:              dmem_be = 4'b1111;
    endcase
  end

  // Memory result with sign/zero extension
  always_comb begin
    mem_result = dmem_rdata;
    case (decoded_instr.opcode)
      OP_LB: begin
        case (alu_result[1:0])
          2'b00: mem_result = {{24{dmem_rdata[7]}},  dmem_rdata[7:0]};
          2'b01: mem_result = {{24{dmem_rdata[15]}}, dmem_rdata[15:8]};
          2'b10: mem_result = {{24{dmem_rdata[23]}}, dmem_rdata[23:16]};
          2'b11: mem_result = {{24{dmem_rdata[31]}}, dmem_rdata[31:24]};
        endcase
      end
      OP_LBU: begin
        case (alu_result[1:0])
          2'b00: mem_result = {24'd0, dmem_rdata[7:0]};
          2'b01: mem_result = {24'd0, dmem_rdata[15:8]};
          2'b10: mem_result = {24'd0, dmem_rdata[23:16]};
          2'b11: mem_result = {24'd0, dmem_rdata[31:24]};
        endcase
      end
      OP_LH:  mem_result = alu_result[1] ? {{16{dmem_rdata[31]}}, dmem_rdata[31:16]} : {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
      OP_LHU: mem_result = alu_result[1] ? {16'd0, dmem_rdata[31:16]} : {16'd0, dmem_rdata[15:0]};
      default: mem_result = dmem_rdata;
    endcase
  end

  // Register file write
  assign rf_we = (state == CORE_WRITEBACK) && decoded_instr.reg_write && (decoded_instr.rd != REG_ZERO);
  assign rf_waddr = decoded_instr.rd;

  always_comb begin
    if (decoded_instr.jump)
      rf_wdata = pc_reg + 4;
    else if (decoded_instr.mem_read)
      rf_wdata = mem_result;
    else
      rf_wdata = alu_result;
  end

  assign rf_init = start && (state == CORE_IDLE);

  // FSM
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      state <= CORE_IDLE;
    else
      state <= next_state;
  end

  always_comb begin
    next_state = state;
    case (state)
      CORE_IDLE:      if (start) next_state = CORE_FETCH;
      CORE_FETCH:     if (imem_valid) next_state = CORE_DECODE;
      CORE_DECODE:    next_state = CORE_EXECUTE;
      CORE_EXECUTE: begin
        if (decoded_instr.is_ret)
          next_state = CORE_DONE;
        else if (decoded_instr.mem_read || decoded_instr.mem_write)
          next_state = CORE_MEMORY;
        else
          next_state = CORE_WRITEBACK;
      end
      CORE_MEMORY:    if (dmem_valid || !dmem_req) next_state = CORE_WRITEBACK;
      CORE_WRITEBACK: next_state = CORE_FETCH;
      CORE_DONE:      next_state = CORE_DONE;
      default:        next_state = CORE_IDLE;
    endcase
  end

  // PC
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      pc_reg <= '0;
    else if (start && state == CORE_IDLE)
      pc_reg <= pc_start;
    else if (state == CORE_WRITEBACK)
      pc_reg <= branch_taken ? branch_target : (pc_reg + 4);
  end

  // Instruction register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      instr_reg <= INSTR_NOP;
    else if (state == CORE_FETCH && imem_valid)
      instr_reg <= imem_rdata;
  end

  assign done = (state == CORE_DONE);
  assign busy = (state != CORE_IDLE) && (state != CORE_DONE);

endmodule
