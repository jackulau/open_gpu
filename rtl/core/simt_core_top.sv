// SIMT Core Top - Top-level module integrating warp scheduler and SIMT pipeline
// Supports 4 warps with 32 threads each, GTO scheduling, and divergence handling

module simt_core_top
  import pkg_opengpu::*;
#(
  parameter int NUM_WARPS = WARPS_PER_CORE
)(
  input  logic                          clk,
  input  logic                          rst_n,

  // Core control
  input  logic                          start,
  input  logic [DATA_WIDTH-1:0]         start_pc,
  input  logic [NUM_WARPS-1:0]          warp_enable,    // Which warps to activate
  output logic                          done,
  output logic                          busy,

  // GPU context for initialization
  input  logic [DATA_WIDTH-1:0]         thread_base,    // Base thread ID
  input  logic [DATA_WIDTH-1:0]         block_idx,
  input  logic [DATA_WIDTH-1:0]         block_dim,
  input  logic [DATA_WIDTH-1:0]         grid_dim,

  // Instruction memory interface
  output logic                          imem_req,
  output logic [ADDR_WIDTH-1:0]         imem_addr,
  input  logic [INSTR_WIDTH-1:0]        imem_rdata,
  input  logic                          imem_valid,

  // Data memory interface (coalesced)
  output logic                          dmem_req,
  output logic [WARP_SIZE-1:0]          dmem_lane_valid,
  output logic [WARP_SIZE-1:0][ADDR_WIDTH-1:0] dmem_addr,
  output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] dmem_wdata,
  output logic                          dmem_we,
  output mem_size_t                     dmem_size,

  input  logic                          dmem_ready,
  input  logic                          dmem_resp_valid,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] dmem_rdata,
  input  logic [WARP_SIZE-1:0]          dmem_lane_resp_valid
);

  // ============================================================================
  // Warp Context Management
  // ============================================================================

  warp_context_t warp_contexts [NUM_WARPS];

  // Warp context control signals
  logic [WARP_ID_WIDTH-1:0] ctx_init_warp_id;
  logic ctx_init_valid;
  logic [DATA_WIDTH-1:0] ctx_init_pc;
  logic [WARP_SIZE-1:0] ctx_init_mask;

  logic [WARP_ID_WIDTH-1:0] ctx_pc_warp_id;
  logic ctx_pc_update;
  logic [DATA_WIDTH-1:0] ctx_new_pc;

  logic [WARP_ID_WIDTH-1:0] ctx_mask_warp_id;
  logic ctx_mask_update;
  logic [WARP_SIZE-1:0] ctx_new_mask;

  logic [WARP_ID_WIDTH-1:0] ctx_status_warp_id;
  logic ctx_status_update;
  warp_status_t ctx_new_status;

  logic [WARP_ID_WIDTH-1:0] ctx_issued_warp_id;
  logic ctx_warp_issued;

  warp_context u_warp_context (
    .clk(clk),
    .rst_n(rst_n),
    .init_warp_id(ctx_init_warp_id),
    .init_valid(ctx_init_valid),
    .init_pc(ctx_init_pc),
    .init_mask(ctx_init_mask),
    .pc_warp_id(ctx_pc_warp_id),
    .pc_update(ctx_pc_update),
    .new_pc(ctx_new_pc),
    .mask_warp_id(ctx_mask_warp_id),
    .mask_update(ctx_mask_update),
    .new_mask(ctx_new_mask),
    .status_warp_id(ctx_status_warp_id),
    .status_update(ctx_status_update),
    .new_status(ctx_new_status),
    .issued_warp_id(ctx_issued_warp_id),
    .warp_issued(ctx_warp_issued),
    .contexts(warp_contexts),
    .read_warp_id('0),
    .read_context()
  );

  // ============================================================================
  // Warp Scheduler
  // ============================================================================

  logic [NUM_WARPS-1:0] warp_stall;
  logic sched_warp_valid;
  logic [WARP_ID_WIDTH-1:0] sched_warp_id;
  logic [DATA_WIDTH-1:0] sched_warp_pc;
  logic [WARP_SIZE-1:0] sched_warp_mask;
  logic sched_issue_ack;
  logic sched_all_done;

  warp_scheduler #(
    .NUM_WARPS(NUM_WARPS)
  ) u_warp_scheduler (
    .clk(clk),
    .rst_n(rst_n),
    .contexts(warp_contexts),
    .warp_stall(warp_stall),
    .warp_valid(sched_warp_valid),
    .selected_warp_id(sched_warp_id),
    .selected_pc(sched_warp_pc),
    .selected_mask(sched_warp_mask),
    .issue_ack(sched_issue_ack),
    .all_done(sched_all_done)
  );

  // ============================================================================
  // SIMT Stack (one per warp)
  // ============================================================================

  logic [NUM_WARPS-1:0] stack_push;
  logic [NUM_WARPS-1:0] stack_pop;
  simt_stack_entry_t stack_push_entry [NUM_WARPS];
  simt_stack_entry_t stack_top_entry [NUM_WARPS];
  logic [NUM_WARPS-1:0] stack_empty;
  logic [NUM_WARPS-1:0] stack_at_reconvergence;

  genvar w;
  generate
    for (w = 0; w < NUM_WARPS; w++) begin : gen_simt_stacks
      simt_stack u_simt_stack (
        .clk(clk),
        .rst_n(rst_n),
        .push(stack_push[w]),
        .pop(stack_pop[w]),
        .push_entry(stack_push_entry[w]),
        .top_entry(stack_top_entry[w]),
        .stack_empty(stack_empty[w]),
        .stack_full(),
        .stack_depth(),
        .current_pc(warp_contexts[w].pc),
        .at_reconvergence(stack_at_reconvergence[w])
      );
    end
  endgenerate

  // ============================================================================
  // Register File
  // ============================================================================

  // Read ports
  logic [WARP_ID_WIDTH-1:0] rf_rs1_warp, rf_rs2_warp, rf_rs3_warp;
  logic [REG_ADDR_WIDTH-1:0] rf_rs1_addr, rf_rs2_addr, rf_rs3_addr;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rf_rs1_data, rf_rs2_data, rf_rs3_data;

  // Write port
  logic [WARP_ID_WIDTH-1:0] rf_rd_warp;
  logic [REG_ADDR_WIDTH-1:0] rf_rd_addr;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rf_rd_data;
  logic [WARP_SIZE-1:0] rf_rd_mask;
  logic rf_we;

  // Context init
  logic rf_init_context;
  logic [WARP_ID_WIDTH-1:0] rf_init_warp;
  logic [DATA_WIDTH-1:0] rf_thread_idx, rf_block_idx, rf_block_dim, rf_grid_dim, rf_warp_idx;

  simt_regfile u_simt_regfile (
    .clk(clk),
    .rst_n(rst_n),
    .rs1_warp_id(rf_rs1_warp),
    .rs1_addr(rf_rs1_addr),
    .rs1_data(rf_rs1_data),
    .rs2_warp_id(rf_rs2_warp),
    .rs2_addr(rf_rs2_addr),
    .rs2_data(rf_rs2_data),
    .rs3_warp_id(rf_rs3_warp),
    .rs3_addr(rf_rs3_addr),
    .rs3_data(rf_rs3_data),
    .rd_warp_id(rf_rd_warp),
    .rd_addr(rf_rd_addr),
    .rd_data(rf_rd_data),
    .rd_mask(rf_rd_mask),
    .rd_we(rf_we),
    .init_context(rf_init_context),
    .init_warp_id(rf_init_warp),
    .thread_idx(rf_thread_idx),
    .block_idx(rf_block_idx),
    .block_dim(rf_block_dim),
    .grid_dim(rf_grid_dim),
    .warp_idx(rf_warp_idx)
  );

  // ============================================================================
  // Pipeline Stages
  // ============================================================================

  // Pipeline control
  logic pipeline_enable;
  logic pipeline_stall;
  logic pipeline_flush;

  // Selective flush for branch misprediction
  logic selective_flush;
  logic [WARP_ID_WIDTH-1:0] flush_warp_id;
  logic [DATA_WIDTH-1:0] flush_correct_pc;

  // Fetch stage outputs
  logic [INSTR_WIDTH-1:0] fetch_instr;
  logic [ADDR_WIDTH-1:0] fetch_pc;
  logic [WARP_ID_WIDTH-1:0] fetch_warp_id;
  logic [WARP_SIZE-1:0] fetch_mask;
  logic fetch_valid;
  logic fetch_issue_ack;

  simt_fetch_stage u_fetch (
    .clk(clk),
    .rst_n(rst_n),
    .enable(pipeline_enable),
    .stall(pipeline_stall),
    .flush(pipeline_flush),
    .selective_flush(selective_flush),
    .flush_warp_id(flush_warp_id),
    .correct_pc(flush_correct_pc),
    .warp_valid(sched_warp_valid),
    .warp_id(sched_warp_id),
    .warp_pc(sched_warp_pc),
    .warp_mask(sched_warp_mask),
    .issue_ack(fetch_issue_ack),
    .imem_req(imem_req),
    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),
    .imem_valid(imem_valid),
    .instr(fetch_instr),
    .pc(fetch_pc),
    .out_warp_id(fetch_warp_id),
    .out_mask(fetch_mask),
    .valid(fetch_valid)
  );

  // Decode stage outputs
  simt_decoded_instr_t decode_decoded;
  logic [ADDR_WIDTH-1:0] decode_pc;
  logic decode_valid;

  // Hazard detection signals from decode
  logic decode_uses_rs1, decode_uses_rs2, decode_uses_rs3;
  logic decode_is_branch;
  logic [DATA_WIDTH-1:0] decode_branch_offset;

  simt_decode_stage u_decode (
    .clk(clk),
    .rst_n(rst_n),
    .stall(pipeline_stall),
    .flush(pipeline_flush),
    .instr(fetch_instr),
    .pc_in(fetch_pc),
    .warp_id_in(fetch_warp_id),
    .mask_in(fetch_mask),
    .valid_in(fetch_valid),
    .decoded(decode_decoded),
    .pc_out(decode_pc),
    .valid_out(decode_valid),
    .uses_rs1(decode_uses_rs1),
    .uses_rs2(decode_uses_rs2),
    .uses_rs3(decode_uses_rs3),
    .is_branch_out(decode_is_branch),
    .branch_offset_out(decode_branch_offset)
  );

  // Connect register file read to decode output
  assign rf_rs1_warp = decode_decoded.warp_id;
  assign rf_rs2_warp = decode_decoded.warp_id;
  assign rf_rs3_warp = decode_decoded.warp_id;
  assign rf_rs1_addr = decode_decoded.base.rs1;
  assign rf_rs2_addr = decode_decoded.base.rs2;
  assign rf_rs3_addr = decode_decoded.base.rs3;

  // Forwarded data (from forwarding unit)
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] fwd_rs1_data, fwd_rs2_data, fwd_rs3_data;
  logic [1:0] fwd_rs1_src, fwd_rs2_src, fwd_rs3_src;

  // Execute stage outputs
  simt_decoded_instr_t exec_decoded;
  logic [ADDR_WIDTH-1:0] exec_pc;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] exec_alu_result;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] exec_mem_wdata;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] exec_mem_addr;
  logic exec_valid;
  logic exec_branch_taken;
  logic [DATA_WIDTH-1:0] exec_branch_target;
  logic exec_is_divergent;
  logic [WARP_SIZE-1:0] exec_new_mask;
  logic exec_update_pc;
  logic [DATA_WIDTH-1:0] exec_new_pc;
  logic exec_fpu_busy;

  // SIMT stack signals for current warp
  logic exec_stack_push, exec_stack_pop;
  simt_stack_entry_t exec_stack_push_entry;
  simt_stack_entry_t exec_stack_top;
  logic exec_stack_at_reconv;

  // Route stack signals to correct warp
  assign exec_stack_top = stack_top_entry[decode_decoded.warp_id];
  assign exec_stack_at_reconv = stack_at_reconvergence[decode_decoded.warp_id];

  // FPU signals (simplified - actual FPU integration would be more complex)
  logic fpu_result_valid;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] fpu_result;

  // Branch resolution signals from execute
  logic exec_branch_resolved;
  logic exec_is_branch;
  logic exec_branch_taken_actual;

  simt_execute_stage u_execute (
    .clk(clk),
    .rst_n(rst_n),
    .stall(pipeline_stall),
    .flush(pipeline_flush),
    .decoded(decode_decoded),
    .pc_in(decode_pc),
    .valid_in(decode_valid),
    .rs1_data(fwd_rs1_data),   // Use forwarded data
    .rs2_data(fwd_rs2_data),   // Use forwarded data
    .rs3_data(fwd_rs3_data),   // Use forwarded data
    .stack_push(exec_stack_push),
    .stack_pop(exec_stack_pop),
    .stack_push_entry(exec_stack_push_entry),
    .stack_top_entry(exec_stack_top),
    .stack_at_reconvergence(exec_stack_at_reconv),
    .decoded_out(exec_decoded),
    .pc_out(exec_pc),
    .alu_result(exec_alu_result),
    .mem_wdata(exec_mem_wdata),
    .mem_addr(exec_mem_addr),
    .valid_out(exec_valid),
    .branch_taken(exec_branch_taken),
    .branch_target(exec_branch_target),
    .is_divergent(exec_is_divergent),
    .new_active_mask(exec_new_mask),
    .update_pc(exec_update_pc),
    .new_pc(exec_new_pc),
    .fpu_busy(exec_fpu_busy),
    .fpu_result_valid(fpu_result_valid),
    .fpu_result(fpu_result),
    .branch_resolved(exec_branch_resolved),
    .is_branch_out(exec_is_branch),
    .branch_taken_actual(exec_branch_taken_actual)
  );

  // Route stack operations to correct warp
  always_comb begin
    for (int i = 0; i < NUM_WARPS; i++) begin
      stack_push[i] = exec_stack_push && (decode_decoded.warp_id == i[WARP_ID_WIDTH-1:0]);
      stack_pop[i] = exec_stack_pop && (decode_decoded.warp_id == i[WARP_ID_WIDTH-1:0]);
      stack_push_entry[i] = exec_stack_push_entry;
    end
  end

  // Memory stage outputs
  simt_decoded_instr_t mem_decoded;
  logic [ADDR_WIDTH-1:0] mem_pc;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] mem_result;
  logic mem_valid;
  logic mem_busy;

  simt_memory_stage u_memory (
    .clk(clk),
    .rst_n(rst_n),
    .stall(pipeline_stall),
    .flush(pipeline_flush),
    .decoded(exec_decoded),
    .pc_in(exec_pc),
    .alu_result(exec_alu_result),
    .mem_wdata_in(exec_mem_wdata),
    .mem_addr_in(exec_mem_addr),
    .valid_in(exec_valid),
    .mem_req_valid(dmem_req),
    .mem_lane_valid(dmem_lane_valid),
    .mem_lane_addr(dmem_addr),
    .mem_lane_wdata(dmem_wdata),
    .mem_is_write(dmem_we),
    .mem_access_size(dmem_size),
    .mem_req_ready(dmem_ready),
    .mem_resp_valid(dmem_resp_valid),
    .mem_resp_rdata(dmem_rdata),
    .mem_resp_lane_valid(dmem_lane_resp_valid),
    .decoded_out(mem_decoded),
    .pc_out(mem_pc),
    .result(mem_result),
    .valid_out(mem_valid),
    .mem_busy(mem_busy)
  );

  // Writeback stage
  logic wb_instr_complete;
  logic [WARP_ID_WIDTH-1:0] wb_complete_warp_id;

  simt_writeback_stage u_writeback (
    .clk(clk),
    .rst_n(rst_n),
    .stall(pipeline_stall),
    .flush(pipeline_flush),
    .decoded(mem_decoded),
    .pc_in(mem_pc),
    .result(mem_result),
    .valid_in(mem_valid),
    .rf_warp_id(rf_rd_warp),
    .rf_rd_addr(rf_rd_addr),
    .rf_rd_data(rf_rd_data),
    .rf_wr_mask(rf_rd_mask),
    .rf_we(rf_we),
    .instr_complete(wb_instr_complete),
    .complete_warp_id(wb_complete_warp_id)
  );

  // ============================================================================
  // SIMD FPU
  // ============================================================================

  logic simd_fpu_start;
  logic simd_fpu_busy;
  logic simd_fpu_valid;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] simd_fpu_result;

  simd_fpu u_simd_fpu (
    .clk(clk),
    .rst_n(rst_n),
    .start(simd_fpu_start),
    .fpu_op(decode_decoded.base.fpu_op),
    .operand_a(rf_rs1_data),
    .operand_b(rf_rs2_data),
    .operand_c(rf_rs3_data),
    .active_mask(decode_decoded.active_mask),
    .result(simd_fpu_result),
    .busy(simd_fpu_busy),
    .result_valid(simd_fpu_valid)
  );

  assign simd_fpu_start = decode_valid && decode_decoded.base.is_fpu_op && !pipeline_stall;
  assign fpu_result_valid = simd_fpu_valid;
  assign fpu_result = simd_fpu_result;

  // ============================================================================
  // Hazard Detection and Data Forwarding
  // ============================================================================

  // Hazard scoreboard signals
  logic scoreboard_hazard_detected;
  logic scoreboard_rs1_hazard, scoreboard_rs2_hazard, scoreboard_rs3_hazard;
  logic [1:0] scoreboard_rs1_fwd_stage, scoreboard_rs2_fwd_stage, scoreboard_rs3_fwd_stage;
  logic scoreboard_rs1_fwd_valid, scoreboard_rs2_fwd_valid, scoreboard_rs3_fwd_valid;
  logic load_use_hazard;

  hazard_scoreboard #(
    .NUM_WARPS(NUM_WARPS)
  ) u_scoreboard (
    .clk(clk),
    .rst_n(rst_n),
    // Decode stage inputs
    .decode_valid(decode_valid),
    .decode_warp_id(decode_decoded.warp_id),
    .decode_rs1(decode_decoded.base.rs1),
    .decode_rs2(decode_decoded.base.rs2),
    .decode_rs3(decode_decoded.base.rs3),
    .decode_uses_rs1(decode_uses_rs1),
    .decode_uses_rs2(decode_uses_rs2),
    .decode_uses_rs3(decode_uses_rs3),
    // Execute issue (set pending)
    .exec_issue(decode_valid && !pipeline_stall),
    .exec_warp_id(decode_decoded.warp_id),
    .exec_rd(decode_decoded.base.rd),
    .exec_reg_write(decode_decoded.base.reg_write),
    .exec_is_load(decode_decoded.base.mem_read),
    // Pipeline advancement
    .ex_mem_advance(exec_valid && !pipeline_stall),
    .ex_mem_warp_id(exec_decoded.warp_id),
    .ex_mem_rd(exec_decoded.base.rd),
    .ex_mem_reg_write(exec_decoded.base.reg_write),
    .mem_wb_advance(mem_valid && !pipeline_stall),
    .mem_wb_warp_id(mem_decoded.warp_id),
    .mem_wb_rd(mem_decoded.base.rd),
    .mem_wb_reg_write(mem_decoded.base.reg_write),
    // Writeback completion
    .wb_complete(wb_instr_complete),
    .wb_warp_id(wb_complete_warp_id),
    .wb_rd(rf_rd_addr),
    .wb_reg_write(rf_we),
    // Flush
    .flush(selective_flush),
    .flush_warp_id(flush_warp_id),
    // Outputs
    .hazard_detected(scoreboard_hazard_detected),
    .rs1_hazard(scoreboard_rs1_hazard),
    .rs2_hazard(scoreboard_rs2_hazard),
    .rs3_hazard(scoreboard_rs3_hazard),
    .rs1_fwd_stage(scoreboard_rs1_fwd_stage),
    .rs2_fwd_stage(scoreboard_rs2_fwd_stage),
    .rs3_fwd_stage(scoreboard_rs3_fwd_stage),
    .rs1_fwd_valid(scoreboard_rs1_fwd_valid),
    .rs2_fwd_valid(scoreboard_rs2_fwd_valid),
    .rs3_fwd_valid(scoreboard_rs3_fwd_valid),
    .load_use_hazard(load_use_hazard)
  );

  // Forwarding unit
  forwarding_unit #(
    .NUM_WARPS(NUM_WARPS)
  ) u_forwarding (
    // Current instruction
    .decode_warp_id(decode_decoded.warp_id),
    .decode_rs1(decode_decoded.base.rs1),
    .decode_rs2(decode_decoded.base.rs2),
    .decode_rs3(decode_decoded.base.rs3),
    // Register file data
    .rf_rs1_data(rf_rs1_data),
    .rf_rs2_data(rf_rs2_data),
    .rf_rs3_data(rf_rs3_data),
    // Execute stage
    .ex_valid(exec_valid),
    .ex_warp_id(exec_decoded.warp_id),
    .ex_rd(exec_decoded.base.rd),
    .ex_reg_write(exec_decoded.base.reg_write),
    .ex_result(exec_alu_result),
    // Memory stage
    .mem_valid(mem_valid),
    .mem_warp_id(mem_decoded.warp_id),
    .mem_rd(mem_decoded.base.rd),
    .mem_reg_write(mem_decoded.base.reg_write),
    .mem_result(mem_result),
    // Writeback stage
    .wb_valid(rf_we),
    .wb_warp_id(rf_rd_warp),
    .wb_rd(rf_rd_addr),
    .wb_reg_write(rf_we),
    .wb_result(rf_rd_data),
    // Forwarded outputs
    .fwd_rs1_data(fwd_rs1_data),
    .fwd_rs2_data(fwd_rs2_data),
    .fwd_rs3_data(fwd_rs3_data),
    .fwd_rs1_src(fwd_rs1_src),
    .fwd_rs2_src(fwd_rs2_src),
    .fwd_rs3_src(fwd_rs3_src)
  );

  // Branch predictor
  logic bp_predict_taken;
  logic [ADDR_WIDTH-1:0] bp_predict_target;
  logic bp_misprediction;
  logic [WARP_ID_WIDTH-1:0] bp_mispredict_warp_id;
  logic [ADDR_WIDTH-1:0] bp_correct_pc;

  branch_predictor #(
    .NUM_WARPS(NUM_WARPS)
  ) u_branch_pred (
    .clk(clk),
    .rst_n(rst_n),
    // Fetch stage
    .fetch_valid(fetch_valid),
    .fetch_warp_id(fetch_warp_id),
    .fetch_pc(fetch_pc),
    // Decode stage
    .decode_valid(decode_valid),
    .decode_warp_id(decode_decoded.warp_id),
    .decode_pc(decode_pc),
    .decode_is_branch(decode_is_branch),
    .decode_branch_offset(decode_branch_offset),
    // Execute stage (resolution)
    .exec_valid(exec_valid),
    .exec_warp_id(exec_decoded.warp_id),
    .exec_pc(exec_pc),
    .exec_is_branch(exec_is_branch),
    .exec_branch_taken(exec_branch_taken_actual),
    .exec_branch_target(exec_branch_target),
    // Prediction outputs
    .predict_taken(bp_predict_taken),
    .predict_target(bp_predict_target),
    // Misprediction outputs
    .misprediction(bp_misprediction),
    .mispredict_warp_id(bp_mispredict_warp_id),
    .correct_pc(bp_correct_pc)
  );

  // Connect misprediction signals
  assign selective_flush = bp_misprediction;
  assign flush_warp_id = bp_mispredict_warp_id;
  assign flush_correct_pc = bp_correct_pc;

  // ============================================================================
  // Control Logic
  // ============================================================================

  // Core state machine
  typedef enum logic [2:0] {
    CORE_IDLE,
    CORE_INIT,
    CORE_RUN,
    CORE_DONE
  } simt_core_state_t;

  simt_core_state_t core_state, core_next_state;
  logic [WARP_ID_WIDTH-1:0] init_warp_counter;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      core_state <= CORE_IDLE;
      init_warp_counter <= '0;
    end else begin
      core_state <= core_next_state;
      if (core_state == CORE_INIT) begin
        if (init_warp_counter < NUM_WARPS - 1) begin
          init_warp_counter <= init_warp_counter + 1;
        end
      end else if (core_state == CORE_IDLE) begin
        init_warp_counter <= '0;
      end
    end
  end

  always_comb begin
    core_next_state = core_state;
    case (core_state)
      CORE_IDLE: begin
        if (start) core_next_state = CORE_INIT;
      end
      CORE_INIT: begin
        if (init_warp_counter == NUM_WARPS - 1) core_next_state = CORE_RUN;
      end
      CORE_RUN: begin
        if (sched_all_done) core_next_state = CORE_DONE;
      end
      CORE_DONE: begin
        core_next_state = CORE_IDLE;
      end
      default: core_next_state = CORE_IDLE;
    endcase
  end

  // Warp initialization
  always_comb begin
    ctx_init_valid = (core_state == CORE_INIT) && warp_enable[init_warp_counter];
    ctx_init_warp_id = init_warp_counter;
    ctx_init_pc = start_pc;
    ctx_init_mask = {WARP_SIZE{1'b1}};  // All lanes active initially

    rf_init_context = ctx_init_valid;
    rf_init_warp = init_warp_counter;
    rf_thread_idx = thread_base + (init_warp_counter * WARP_SIZE);
    rf_block_idx = block_idx;
    rf_block_dim = block_dim;
    rf_grid_dim = grid_dim;
    rf_warp_idx = {29'd0, init_warp_counter};
  end

  // Pipeline control
  assign pipeline_enable = (core_state == CORE_RUN);
  // Stall for memory, FPU, or load-use hazard
  assign pipeline_stall = mem_busy || exec_fpu_busy || simd_fpu_busy || load_use_hazard;
  // Flush on branch misprediction
  assign pipeline_flush = bp_misprediction;

  // Warp stall (pipeline hazards)
  always_comb begin
    warp_stall = '0;
    // Stall warp if it's currently in the pipeline
    if (fetch_valid) warp_stall[fetch_warp_id] = 1'b1;
    if (decode_valid) warp_stall[decode_decoded.warp_id] = 1'b1;
    if (exec_valid) warp_stall[exec_decoded.warp_id] = 1'b1;
    if (mem_valid) warp_stall[mem_decoded.warp_id] = 1'b1;
  end

  // Scheduler interface
  assign sched_issue_ack = fetch_issue_ack;
  assign ctx_warp_issued = fetch_issue_ack;
  assign ctx_issued_warp_id = sched_warp_id;

  // PC update from execute stage
  always_comb begin
    ctx_pc_update = exec_update_pc && exec_valid && !pipeline_stall;
    ctx_pc_warp_id = exec_decoded.warp_id;
    ctx_new_pc = exec_new_pc;
  end

  // Mask update from execute stage
  always_comb begin
    ctx_mask_update = exec_is_divergent && exec_valid && !pipeline_stall;
    ctx_mask_warp_id = exec_decoded.warp_id;
    ctx_new_mask = exec_new_mask;
  end

  // Status update
  always_comb begin
    ctx_status_update = 1'b0;
    ctx_status_warp_id = '0;
    ctx_new_status = WARP_READY;

    // Mark warp as done if RET instruction completes
    if (wb_instr_complete && mem_decoded.base.is_ret) begin
      ctx_status_update = 1'b1;
      ctx_status_warp_id = wb_complete_warp_id;
      ctx_new_status = WARP_DONE;
    end
  end

  // Output signals
  assign done = (core_state == CORE_DONE);
  assign busy = (core_state != CORE_IDLE);

endmodule
