// SIMT Execute Stage - 32-lane execution with divergence handling
// Handles branch divergence, SIMT stack operations, and multi-lane execution

module simt_execute_stage
  import pkg_opengpu::*;
(
  input  logic                          clk,
  input  logic                          rst_n,

  // Control
  input  logic                          stall,
  input  logic                          flush,

  // From decode
  input  simt_decoded_instr_t           decoded,
  input  logic [ADDR_WIDTH-1:0]         pc_in,
  input  logic                          valid_in,

  // Register file read data (32 lanes)
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rs1_data,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rs2_data,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rs3_data,

  // SIMT stack interface (per-warp)
  output logic                          stack_push,
  output logic                          stack_pop,
  output simt_stack_entry_t             stack_push_entry,
  input  simt_stack_entry_t             stack_top_entry,
  input  logic                          stack_at_reconvergence,

  // To memory stage
  output simt_decoded_instr_t           decoded_out,
  output logic [ADDR_WIDTH-1:0]         pc_out,
  output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] alu_result,
  output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] mem_wdata,
  output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] mem_addr,
  output logic                          valid_out,

  // Branch/divergence output
  output logic                          branch_taken,
  output logic [DATA_WIDTH-1:0]         branch_target,
  output logic                          is_divergent,
  output logic [WARP_SIZE-1:0]          new_active_mask,

  // PC update for warp context
  output logic                          update_pc,
  output logic [DATA_WIDTH-1:0]         new_pc,

  // FPU busy (stall signal)
  output logic                          fpu_busy,
  input  logic                          fpu_result_valid,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] fpu_result
);

  // Per-lane operands
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] operand_a;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] operand_b;

  // SIMD ALU instance
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] int_alu_result;
  logic [WARP_SIZE-1:0] zero_flags, neg_flags;

  simd_int_alu u_simd_int_alu (
    .operand_a(operand_a),
    .operand_b(operand_b),
    .alu_op(decoded.base.alu_op),
    .active_mask(decoded.active_mask),
    .result(int_alu_result),
    .zero_flags(zero_flags),
    .neg_flags(neg_flags),
    .any_zero(),
    .all_zero(),
    .any_neg(),
    .all_neg()
  );

  // Vote unit
  logic [DATA_WIDTH-1:0] vote_result;
  logic [WARP_SIZE-1:0] predicate_for_vote;

  // Use rs1_data[lane][0] as predicate (bit 0)
  always_comb begin
    for (int i = 0; i < WARP_SIZE; i++) begin
      predicate_for_vote[i] = rs1_data[i][0];
    end
  end

  vote_unit u_vote (
    .predicate(predicate_for_vote),
    .active_mask(decoded.active_mask),
    .vote_op(decoded.vote_op),
    .result(vote_result),
    .vote_all_result(),
    .vote_any_result(),
    .vote_ballot_result()
  );

  // Shuffle unit
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] shuffle_result;
  logic [WARP_SIZE-1:0] shuffle_valid;
  logic [WARP_SIZE-1:0][4:0] shuffle_idx;

  // Shuffle index from rs2
  always_comb begin
    for (int i = 0; i < WARP_SIZE; i++) begin
      shuffle_idx[i] = rs2_data[i][4:0];
    end
  end

  shuffle_unit u_shuffle (
    .lane_data(rs1_data),
    .shuffle_op(decoded.shuffle_op),
    .shuffle_idx(shuffle_idx),
    .width(5'd32),
    .active_mask(decoded.active_mask),
    .result(shuffle_result),
    .result_valid(shuffle_valid)
  );

  // Operand selection
  always_comb begin
    for (int lane = 0; lane < WARP_SIZE; lane++) begin
      // Operand A: rs1 data or PC for AUIPC
      if (decoded.base.opcode == OP_AUIPC) begin
        operand_a[lane] = pc_in;
      end else begin
        operand_a[lane] = rs1_data[lane];
      end

      // Operand B: rs2 data or immediate
      if (decoded.base.use_imm) begin
        operand_b[lane] = decoded.base.imm;
      end else begin
        operand_b[lane] = rs2_data[lane];
      end
    end
  end

  // Branch condition evaluation (per-lane)
  logic [WARP_SIZE-1:0] branch_condition;
  always_comb begin
    for (int lane = 0; lane < WARP_SIZE; lane++) begin
      // Branch condition is result of comparison (bit 0)
      branch_condition[lane] = int_alu_result[lane][0];
    end
  end

  // Divergence detection
  logic [WARP_SIZE-1:0] taken_mask;
  logic [WARP_SIZE-1:0] not_taken_mask;

  assign taken_mask = decoded.active_mask & branch_condition;
  assign not_taken_mask = decoded.active_mask & ~branch_condition;

  // Divergent if both taken and not-taken have active lanes
  assign is_divergent = valid_in && decoded.base.branch &&
                        (taken_mask != '0) && (not_taken_mask != '0);

  // Branch target calculation
  logic [DATA_WIDTH-1:0] branch_target_calc;
  always_comb begin
    if (decoded.base.jump && decoded.base.is_ret) begin
      // RET: target from rs1 (return address)
      branch_target_calc = rs1_data[ffs32(decoded.active_mask)];
    end else if (decoded.base.jump && decoded.base.opcode == OP_JALR) begin
      // JALR: rs1 + imm
      branch_target_calc = rs1_data[ffs32(decoded.active_mask)] + decoded.base.imm;
    end else begin
      // Branch/JAL: PC + imm
      branch_target_calc = pc_in + decoded.base.imm;
    end
  end

  // Branch decision
  logic uniform_taken;
  assign uniform_taken = (taken_mask == decoded.active_mask);  // All active lanes take branch

  always_comb begin
    if (decoded.base.jump) begin
      branch_taken = valid_in;
      branch_target = branch_target_calc;
    end else if (decoded.base.branch && !is_divergent) begin
      branch_taken = valid_in && uniform_taken;
      branch_target = branch_target_calc;
    end else begin
      branch_taken = 1'b0;
      branch_target = pc_in + 4;
    end
  end

  // SIMT stack operations
  always_comb begin
    stack_push = 1'b0;
    stack_pop = 1'b0;
    stack_push_entry = '0;
    new_active_mask = decoded.active_mask;
    update_pc = 1'b0;
    new_pc = pc_in + 4;

    if (valid_in && !stall) begin
      if (is_divergent) begin
        // Push divergence context onto stack
        stack_push = 1'b1;
        stack_push_entry.reconvergence_pc = pc_in + 4;  // After branch = reconvergence
        stack_push_entry.active_mask = decoded.active_mask;
        stack_push_entry.taken_mask = taken_mask;

        // Execute taken path first, mask off not-taken
        new_active_mask = taken_mask;
        update_pc = 1'b1;
        new_pc = branch_target_calc;
      end else if (stack_at_reconvergence) begin
        // Pop stack and restore mask
        stack_pop = 1'b1;
        new_active_mask = stack_top_entry.active_mask;
        update_pc = 1'b1;
        new_pc = pc_in + 4;  // Continue after reconvergence
      end else if (decoded.base.branch && taken_mask == '0) begin
        // No lanes took branch (uniform not-taken)
        update_pc = 1'b1;
        new_pc = pc_in + 4;
      end else if (decoded.base.branch || decoded.base.jump) begin
        // Uniform branch/jump
        update_pc = 1'b1;
        new_pc = branch_taken ? branch_target : (pc_in + 4);
      end else begin
        // Normal sequential execution
        update_pc = 1'b1;
        new_pc = pc_in + 4;
      end
    end
  end

  // Result selection
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] result_mux;

  always_comb begin
    for (int lane = 0; lane < WARP_SIZE; lane++) begin
      if (decoded.is_vote_op) begin
        result_mux[lane] = vote_result;  // Broadcast to all lanes
      end else if (decoded.is_shuffle_op) begin
        result_mux[lane] = shuffle_result[lane];
      end else if (decoded.base.opcode == OP_POPC) begin
        result_mux[lane] = {26'd0, popcount32(rs1_data[lane])};
      end else if (decoded.base.opcode == OP_CLZ) begin
        result_mux[lane] = {26'd0, clz32(rs1_data[lane])};
      end else if (decoded.base.jump && !decoded.base.is_ret) begin
        // JAL/JALR: save return address
        result_mux[lane] = pc_in + 4;
      end else if (decoded.base.is_fpu_op && fpu_result_valid) begin
        result_mux[lane] = fpu_result[lane];
      end else begin
        result_mux[lane] = int_alu_result[lane];
      end
    end
  end

  // Memory address and write data
  always_comb begin
    for (int lane = 0; lane < WARP_SIZE; lane++) begin
      mem_addr[lane] = rs1_data[lane] + decoded.base.imm;
      mem_wdata[lane] = rs2_data[lane];
    end
  end

  // FPU busy signal (placeholder - actual FPU manages this)
  assign fpu_busy = valid_in && decoded.base.is_fpu_op &&
                    is_multicycle_fpu_op(decoded.base.fpu_op) &&
                    !fpu_result_valid;

  // Pipeline registers
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      decoded_out <= '0;
      pc_out <= '0;
      alu_result <= '0;
      valid_out <= 1'b0;
    end else if (flush) begin
      decoded_out <= '0;
      valid_out <= 1'b0;
    end else if (!stall) begin
      decoded_out <= decoded;
      decoded_out.active_mask <= new_active_mask;
      pc_out <= pc_in;
      alu_result <= result_mux;
      valid_out <= valid_in;
    end
  end

endmodule
