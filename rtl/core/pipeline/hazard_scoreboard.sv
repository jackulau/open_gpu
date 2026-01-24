// Hazard Scoreboard - Tracks in-flight register writes per warp
// Detects RAW hazards and provides forwarding stage information

module hazard_scoreboard
  import pkg_opengpu::*;
#(
  parameter int NUM_WARPS = WARPS_PER_CORE,
  parameter int NUM_REGS  = 32
)(
  input  logic                          clk,
  input  logic                          rst_n,

  // ========================================================================
  // Decode stage inputs (check for hazards)
  // ========================================================================
  input  logic                          decode_valid,
  input  logic [WARP_ID_WIDTH-1:0]      decode_warp_id,
  input  logic [REG_ADDR_WIDTH-1:0]     decode_rs1,
  input  logic [REG_ADDR_WIDTH-1:0]     decode_rs2,
  input  logic [REG_ADDR_WIDTH-1:0]     decode_rs3,
  input  logic                          decode_uses_rs1,
  input  logic                          decode_uses_rs2,
  input  logic                          decode_uses_rs3,

  // ========================================================================
  // Execute stage inputs (set pending on issue)
  // ========================================================================
  input  logic                          exec_issue,         // Instruction issued to execute
  input  logic [WARP_ID_WIDTH-1:0]      exec_warp_id,
  input  logic [REG_ADDR_WIDTH-1:0]     exec_rd,
  input  logic                          exec_reg_write,
  input  logic                          exec_is_load,       // Load instructions need extra cycle

  // ========================================================================
  // Pipeline stage completion inputs (advance/clear pending)
  // ========================================================================
  input  logic                          ex_mem_advance,     // EX->MEM transition
  input  logic [WARP_ID_WIDTH-1:0]      ex_mem_warp_id,
  input  logic [REG_ADDR_WIDTH-1:0]     ex_mem_rd,
  input  logic                          ex_mem_reg_write,

  input  logic                          mem_wb_advance,     // MEM->WB transition
  input  logic [WARP_ID_WIDTH-1:0]      mem_wb_warp_id,
  input  logic [REG_ADDR_WIDTH-1:0]     mem_wb_rd,
  input  logic                          mem_wb_reg_write,

  input  logic                          wb_complete,        // WB completion (clear pending)
  input  logic [WARP_ID_WIDTH-1:0]      wb_warp_id,
  input  logic [REG_ADDR_WIDTH-1:0]     wb_rd,
  input  logic                          wb_reg_write,

  // ========================================================================
  // Flush support
  // ========================================================================
  input  logic                          flush,
  input  logic [WARP_ID_WIDTH-1:0]      flush_warp_id,

  // ========================================================================
  // Hazard detection outputs
  // ========================================================================
  output logic                          hazard_detected,
  output logic                          rs1_hazard,
  output logic                          rs2_hazard,
  output logic                          rs3_hazard,

  // Forwarding stage information (for forwarding unit)
  // Stage encoding: 0=EX, 1=MEM, 2=WB
  output logic [1:0]                    rs1_fwd_stage,
  output logic [1:0]                    rs2_fwd_stage,
  output logic [1:0]                    rs3_fwd_stage,
  output logic                          rs1_fwd_valid,
  output logic                          rs2_fwd_valid,
  output logic                          rs3_fwd_valid,

  // Load-use hazard (requires stall, cannot forward from EX)
  output logic                          load_use_hazard
);

  // ========================================================================
  // Pipeline stage encoding
  // ========================================================================
  localparam logic [1:0] STAGE_EX  = 2'd0;
  localparam logic [1:0] STAGE_MEM = 2'd1;
  localparam logic [1:0] STAGE_WB  = 2'd2;
  localparam logic [1:0] STAGE_NONE = 2'd3;

  // ========================================================================
  // Scoreboard storage
  // ========================================================================

  // Pending write bitmap: pending[warp][reg] = 1 if register has pending write
  logic [NUM_REGS-1:0] pending [NUM_WARPS];

  // Stage tracking: pending_stage[warp][reg] = stage that will produce value
  logic [1:0] pending_stage [NUM_WARPS][NUM_REGS];

  // Is load tracking: is_load[warp][reg] = 1 if pending write is from load
  logic [NUM_REGS-1:0] is_load_pending [NUM_WARPS];

  // ========================================================================
  // Hazard detection logic (combinational)
  // ========================================================================

  logic rs1_pending, rs2_pending, rs3_pending;
  logic [1:0] rs1_stage, rs2_stage, rs3_stage;
  logic rs1_is_load, rs2_is_load, rs3_is_load;

  always_comb begin
    // Check if source registers have pending writes
    rs1_pending = decode_valid && decode_uses_rs1 &&
                  (decode_rs1 != '0) &&  // x0 never has hazard
                  pending[decode_warp_id][decode_rs1];

    rs2_pending = decode_valid && decode_uses_rs2 &&
                  (decode_rs2 != '0) &&
                  pending[decode_warp_id][decode_rs2];

    rs3_pending = decode_valid && decode_uses_rs3 &&
                  (decode_rs3 != '0) &&
                  pending[decode_warp_id][decode_rs3];

    // Get the stage producing each source register
    rs1_stage = pending[decode_warp_id][decode_rs1] ?
                pending_stage[decode_warp_id][decode_rs1] : STAGE_NONE;
    rs2_stage = pending[decode_warp_id][decode_rs2] ?
                pending_stage[decode_warp_id][decode_rs2] : STAGE_NONE;
    rs3_stage = pending[decode_warp_id][decode_rs3] ?
                pending_stage[decode_warp_id][decode_rs3] : STAGE_NONE;

    // Check if pending writes are from load instructions
    rs1_is_load = is_load_pending[decode_warp_id][decode_rs1];
    rs2_is_load = is_load_pending[decode_warp_id][decode_rs2];
    rs3_is_load = is_load_pending[decode_warp_id][decode_rs3];

    // Individual hazard signals
    rs1_hazard = rs1_pending;
    rs2_hazard = rs2_pending;
    rs3_hazard = rs3_pending;

    // Overall hazard detection
    hazard_detected = rs1_pending || rs2_pending || rs3_pending;

    // Forwarding stage outputs
    rs1_fwd_stage = rs1_stage;
    rs2_fwd_stage = rs2_stage;
    rs3_fwd_stage = rs3_stage;

    // Forwarding valid when pending and not in EX stage for loads
    // (loads need to wait for MEM stage to have data)
    rs1_fwd_valid = rs1_pending && !(rs1_is_load && rs1_stage == STAGE_EX);
    rs2_fwd_valid = rs2_pending && !(rs2_is_load && rs2_stage == STAGE_EX);
    rs3_fwd_valid = rs3_pending && !(rs3_is_load && rs3_stage == STAGE_EX);

    // Load-use hazard: need data from load but it's still in EX stage
    load_use_hazard = (rs1_pending && rs1_is_load && rs1_stage == STAGE_EX) ||
                      (rs2_pending && rs2_is_load && rs2_stage == STAGE_EX) ||
                      (rs3_pending && rs3_is_load && rs3_stage == STAGE_EX);
  end

  // ========================================================================
  // Scoreboard update logic (sequential)
  // ========================================================================

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int w = 0; w < NUM_WARPS; w++) begin
        pending[w] <= '0;
        is_load_pending[w] <= '0;
        for (int r = 0; r < NUM_REGS; r++) begin
          pending_stage[w][r] <= STAGE_NONE;
        end
      end
    end else begin
      // Flush: clear all pending for the flushed warp
      if (flush) begin
        // Clear using case statement for better iverilog compatibility
        case (flush_warp_id)
          2'd0: begin
            pending[0] <= '0;
            is_load_pending[0] <= '0;
          end
          2'd1: begin
            pending[1] <= '0;
            is_load_pending[1] <= '0;
          end
          2'd2: begin
            pending[2] <= '0;
            is_load_pending[2] <= '0;
          end
          2'd3: begin
            pending[3] <= '0;
            is_load_pending[3] <= '0;
          end
        endcase
        for (int r = 0; r < NUM_REGS; r++) begin
          pending_stage[flush_warp_id][r] <= STAGE_NONE;
        end
      end else begin

        // Stage advancement: EX -> MEM
        if (ex_mem_advance && ex_mem_reg_write && ex_mem_rd != '0) begin
          if (pending[ex_mem_warp_id][ex_mem_rd] &&
              pending_stage[ex_mem_warp_id][ex_mem_rd] == STAGE_EX) begin
            pending_stage[ex_mem_warp_id][ex_mem_rd] <= STAGE_MEM;
          end
        end

        // Stage advancement: MEM -> WB
        if (mem_wb_advance && mem_wb_reg_write && mem_wb_rd != '0) begin
          if (pending[mem_wb_warp_id][mem_wb_rd] &&
              pending_stage[mem_wb_warp_id][mem_wb_rd] == STAGE_MEM) begin
            pending_stage[mem_wb_warp_id][mem_wb_rd] <= STAGE_WB;
          end
        end

        // Writeback completion: clear pending
        if (wb_complete && wb_reg_write && wb_rd != '0) begin
          // Only clear if the stage is WB (to handle WAW correctly)
          if (pending_stage[wb_warp_id][wb_rd] == STAGE_WB) begin
            pending[wb_warp_id][wb_rd] <= 1'b0;
            pending_stage[wb_warp_id][wb_rd] <= STAGE_NONE;
            is_load_pending[wb_warp_id][wb_rd] <= 1'b0;
          end
        end

        // New instruction issued: set pending
        // This should happen last to handle WAW (newer write takes precedence)
        if (exec_issue && exec_reg_write && exec_rd != '0) begin
          pending[exec_warp_id][exec_rd] <= 1'b1;
          pending_stage[exec_warp_id][exec_rd] <= STAGE_EX;
          is_load_pending[exec_warp_id][exec_rd] <= exec_is_load;
        end

      end
    end
  end

endmodule
