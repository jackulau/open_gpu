// Branch Predictor - Static BTFN (Backward Taken, Forward Not Taken)
// Simplified version for iverilog compatibility

module branch_predictor
  import pkg_opengpu::*;
#(
  parameter int NUM_WARPS = WARPS_PER_CORE
)(
  input  logic                          clk,
  input  logic                          rst_n,

  // ========================================================================
  // Fetch stage inputs (make prediction)
  // ========================================================================
  input  logic                          fetch_valid,
  input  logic [WARP_ID_WIDTH-1:0]      fetch_warp_id,
  input  logic [ADDR_WIDTH-1:0]         fetch_pc,

  // ========================================================================
  // Decode stage inputs (record prediction for later comparison)
  // ========================================================================
  input  logic                          decode_valid,
  input  logic [WARP_ID_WIDTH-1:0]      decode_warp_id,
  input  logic [ADDR_WIDTH-1:0]         decode_pc,
  input  logic                          decode_is_branch,
  input  logic [DATA_WIDTH-1:0]         decode_branch_offset,  // Signed offset from imm

  // ========================================================================
  // Execute stage inputs (resolve branch)
  // ========================================================================
  input  logic                          exec_valid,
  input  logic [WARP_ID_WIDTH-1:0]      exec_warp_id,
  input  logic [ADDR_WIDTH-1:0]         exec_pc,
  input  logic                          exec_is_branch,
  input  logic                          exec_branch_taken,     // Actual branch outcome
  input  logic [DATA_WIDTH-1:0]         exec_branch_target,    // Actual target if taken

  // ========================================================================
  // Prediction outputs (for fetch stage PC selection)
  // ========================================================================
  output logic                          predict_taken,
  output logic [ADDR_WIDTH-1:0]         predict_target,

  // ========================================================================
  // Misprediction outputs (for pipeline flush)
  // ========================================================================
  output logic                          misprediction,
  output logic [WARP_ID_WIDTH-1:0]      mispredict_warp_id,
  output logic [ADDR_WIDTH-1:0]         correct_pc
);

  // ========================================================================
  // Prediction tracking per warp - flattened to avoid struct array issues
  // ========================================================================

  // Per-warp prediction state
  logic [NUM_WARPS-1:0] pred_valid;
  logic [ADDR_WIDTH-1:0] pred_pc [NUM_WARPS];
  logic [NUM_WARPS-1:0] pred_taken;
  logic [ADDR_WIDTH-1:0] pred_target [NUM_WARPS];
  logic [ADDR_WIDTH-1:0] pred_fallthrough [NUM_WARPS];

  // ========================================================================
  // Static BTFN Prediction Logic
  // Backward branches (negative offset) -> Predict Taken
  // Forward branches (positive/zero offset) -> Predict Not Taken
  // ========================================================================

  logic is_backward_branch;
  logic [ADDR_WIDTH-1:0] branch_target_calc;

  // Check if branch offset is negative (backward branch)
  assign is_backward_branch = decode_branch_offset[DATA_WIDTH-1];  // Sign bit

  // Calculate predicted target
  assign branch_target_calc = decode_pc + decode_branch_offset;

  // Make prediction
  always_comb begin
    if (decode_valid && decode_is_branch) begin
      predict_taken = is_backward_branch;  // BTFN: Backward -> Taken
      predict_target = is_backward_branch ? branch_target_calc : (decode_pc + 4);
    end else begin
      predict_taken = 1'b0;
      predict_target = decode_pc + 4;
    end
  end

  // ========================================================================
  // Prediction Recording (Decode Stage)
  // ========================================================================

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pred_valid <= '0;
      for (int w = 0; w < NUM_WARPS; w++) begin
        pred_pc[w] <= '0;
        pred_target[w] <= '0;
        pred_fallthrough[w] <= '0;
      end
      pred_taken <= '0;
    end else begin
      // Record prediction for branches in decode stage
      if (decode_valid && decode_is_branch) begin
        case (decode_warp_id)
          2'd0: begin
            pred_valid[0] <= 1'b1;
            pred_pc[0] <= decode_pc;
            pred_taken[0] <= predict_taken;
            pred_target[0] <= predict_target;
            pred_fallthrough[0] <= decode_pc + 4;
          end
          2'd1: begin
            pred_valid[1] <= 1'b1;
            pred_pc[1] <= decode_pc;
            pred_taken[1] <= predict_taken;
            pred_target[1] <= predict_target;
            pred_fallthrough[1] <= decode_pc + 4;
          end
          2'd2: begin
            pred_valid[2] <= 1'b1;
            pred_pc[2] <= decode_pc;
            pred_taken[2] <= predict_taken;
            pred_target[2] <= predict_target;
            pred_fallthrough[2] <= decode_pc + 4;
          end
          2'd3: begin
            pred_valid[3] <= 1'b1;
            pred_pc[3] <= decode_pc;
            pred_taken[3] <= predict_taken;
            pred_target[3] <= predict_target;
            pred_fallthrough[3] <= decode_pc + 4;
          end
        endcase
      end

      // Clear prediction after resolution
      if (exec_valid && exec_is_branch) begin
        case (exec_warp_id)
          2'd0: pred_valid[0] <= 1'b0;
          2'd1: pred_valid[1] <= 1'b0;
          2'd2: pred_valid[2] <= 1'b0;
          2'd3: pred_valid[3] <= 1'b0;
        endcase
      end
    end
  end

  // ========================================================================
  // Misprediction Detection (Execute Stage)
  // ========================================================================

  logic predicted_taken_for_exec;
  logic [ADDR_WIDTH-1:0] predicted_target_for_exec;
  logic [ADDR_WIDTH-1:0] not_taken_pc;
  logic prediction_valid;

  // Get the prediction that was made for this branch
  always_comb begin
    case (exec_warp_id)
      2'd0: begin
        predicted_taken_for_exec = pred_taken[0];
        predicted_target_for_exec = pred_target[0];
        not_taken_pc = pred_fallthrough[0];
        prediction_valid = pred_valid[0] && (pred_pc[0] == exec_pc);
      end
      2'd1: begin
        predicted_taken_for_exec = pred_taken[1];
        predicted_target_for_exec = pred_target[1];
        not_taken_pc = pred_fallthrough[1];
        prediction_valid = pred_valid[1] && (pred_pc[1] == exec_pc);
      end
      2'd2: begin
        predicted_taken_for_exec = pred_taken[2];
        predicted_target_for_exec = pred_target[2];
        not_taken_pc = pred_fallthrough[2];
        prediction_valid = pred_valid[2] && (pred_pc[2] == exec_pc);
      end
      2'd3: begin
        predicted_taken_for_exec = pred_taken[3];
        predicted_target_for_exec = pred_target[3];
        not_taken_pc = pred_fallthrough[3];
        prediction_valid = pred_valid[3] && (pred_pc[3] == exec_pc);
      end
      default: begin
        predicted_taken_for_exec = 1'b0;
        predicted_target_for_exec = '0;
        not_taken_pc = '0;
        prediction_valid = 1'b0;
      end
    endcase
  end

  // Detect misprediction
  always_comb begin
    misprediction = 1'b0;
    mispredict_warp_id = exec_warp_id;
    correct_pc = exec_pc + 4;

    if (exec_valid && exec_is_branch && prediction_valid) begin
      // Compare actual vs predicted outcome
      if (predicted_taken_for_exec != exec_branch_taken) begin
        // Direction misprediction
        misprediction = 1'b1;
        if (exec_branch_taken) begin
          // Should have taken but predicted not-taken
          correct_pc = exec_branch_target;
        end else begin
          // Should not have taken but predicted taken
          correct_pc = not_taken_pc;
        end
      end else if (exec_branch_taken &&
                   (predicted_target_for_exec != exec_branch_target)) begin
        // Target misprediction (taken but wrong target)
        misprediction = 1'b1;
        correct_pc = exec_branch_target;
      end
    end else if (exec_valid && exec_is_branch && !prediction_valid) begin
      // No prediction was recorded - be conservative
      if (exec_branch_taken) begin
        misprediction = 1'b1;
        correct_pc = exec_branch_target;
      end
    end
  end

endmodule
