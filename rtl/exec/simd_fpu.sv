// SIMD FPU - 8-lane floating-point unit with 4-cycle latency for full warp
// Processes 32 lanes in 4 cycles (lanes 0-7, 8-15, 16-23, 24-31)

module simd_fpu
  import pkg_opengpu::*;
#(
  parameter int NUM_LANES = FPU_LANES,  // 8 lanes
  parameter int CYCLES_PER_WARP = FPU_CYCLES_PER_WARP  // 4 cycles
)(
  input  logic                          clk,
  input  logic                          rst_n,

  // Start signal and operation
  input  logic                          start,
  input  fpu_op_t                       fpu_op,

  // Per-lane operands (all 32 lanes provided upfront)
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] operand_a,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] operand_b,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] operand_c,

  // Active mask
  input  logic [WARP_SIZE-1:0]          active_mask,

  // Results (all 32 lanes)
  output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] result,

  // Status
  output logic                          busy,
  output logic                          result_valid
);

  // State machine
  typedef enum logic [2:0] {
    FPU_IDLE,
    FPU_CYCLE1,   // Processing lanes 0-7
    FPU_CYCLE2,   // Processing lanes 8-15
    FPU_CYCLE3,   // Processing lanes 16-23
    FPU_CYCLE4,   // Processing lanes 24-31
    FPU_WAIT_MC,  // Waiting for multi-cycle ops
    FPU_DONE
  } simd_fpu_state_t;

  simd_fpu_state_t state, next_state;

  // Stored operands
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] op_a_reg, op_b_reg, op_c_reg;
  fpu_op_t fpu_op_reg;
  logic [WARP_SIZE-1:0] mask_reg;

  // Result accumulator
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] result_reg;

  // Current lane group (0, 8, 16, or 24)
  logic [4:0] lane_offset;

  // FPU instance signals (8 lanes)
  logic [NUM_LANES-1:0][DATA_WIDTH-1:0] fpu_op_a, fpu_op_b, fpu_op_c;
  logic [NUM_LANES-1:0][DATA_WIDTH-1:0] fpu_result;
  logic [NUM_LANES-1:0] fpu_start, fpu_busy, fpu_valid;

  // Track if operation is multi-cycle
  logic is_multicycle;
  assign is_multicycle = (fpu_op_reg == FPU_DIV) || (fpu_op_reg == FPU_SQRT);

  // Any FPU busy
  logic any_fpu_busy;
  assign any_fpu_busy = |fpu_busy;

  // All FPUs valid
  logic all_fpu_valid;
  always_comb begin
    all_fpu_valid = 1'b1;
    for (int i = 0; i < NUM_LANES; i++) begin
      // Only check active lanes
      if (mask_reg[lane_offset + i]) begin
        all_fpu_valid = all_fpu_valid & fpu_valid[i];
      end
    end
  end

  // Instantiate 8 FPU lanes
  genvar lane;
  generate
    for (lane = 0; lane < NUM_LANES; lane++) begin : gen_fpu_lanes
      fp_alu fpu_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(fpu_start[lane]),
        .fpu_op(fpu_op_reg),
        .operand_a(fpu_op_a[lane]),
        .operand_b(fpu_op_b[lane]),
        .operand_c(fpu_op_c[lane]),
        .result(fpu_result[lane]),
        .result_valid(fpu_valid[lane]),
        .busy(fpu_busy[lane])
      );
    end
  endgenerate

  // Route operands to current lane group
  always_comb begin
    for (int i = 0; i < NUM_LANES; i++) begin
      fpu_op_a[i] = op_a_reg[lane_offset + i];
      fpu_op_b[i] = op_b_reg[lane_offset + i];
      fpu_op_c[i] = op_c_reg[lane_offset + i];
    end
  end

  // State machine
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= FPU_IDLE;
    end else begin
      state <= next_state;
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      FPU_IDLE: begin
        if (start) next_state = FPU_CYCLE1;
      end
      FPU_CYCLE1: begin
        if (is_multicycle) begin
          if (all_fpu_valid) next_state = FPU_CYCLE2;
        end else begin
          next_state = FPU_CYCLE2;
        end
      end
      FPU_CYCLE2: begin
        if (is_multicycle) begin
          if (all_fpu_valid) next_state = FPU_CYCLE3;
        end else begin
          next_state = FPU_CYCLE3;
        end
      end
      FPU_CYCLE3: begin
        if (is_multicycle) begin
          if (all_fpu_valid) next_state = FPU_CYCLE4;
        end else begin
          next_state = FPU_CYCLE4;
        end
      end
      FPU_CYCLE4: begin
        if (is_multicycle) begin
          if (all_fpu_valid) next_state = FPU_DONE;
        end else begin
          next_state = FPU_DONE;
        end
      end
      FPU_DONE: begin
        next_state = FPU_IDLE;
      end
      default: next_state = FPU_IDLE;
    endcase
  end

  // Lane offset based on state
  always_comb begin
    case (state)
      FPU_CYCLE1: lane_offset = 5'd0;
      FPU_CYCLE2: lane_offset = 5'd8;
      FPU_CYCLE3: lane_offset = 5'd16;
      FPU_CYCLE4: lane_offset = 5'd24;
      default:    lane_offset = 5'd0;
    endcase
  end

  // FPU start signals
  always_comb begin
    for (int i = 0; i < NUM_LANES; i++) begin
      fpu_start[i] = (state == FPU_CYCLE1 && lane_offset == 5'd0) ||
                     (state == FPU_CYCLE2 && lane_offset == 5'd8) ||
                     (state == FPU_CYCLE3 && lane_offset == 5'd16) ||
                     (state == FPU_CYCLE4 && lane_offset == 5'd24);
      // Only start for active lanes
      fpu_start[i] = fpu_start[i] && mask_reg[lane_offset + i];
    end
  end

  // Register operands on start
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      op_a_reg <= '0;
      op_b_reg <= '0;
      op_c_reg <= '0;
      fpu_op_reg <= FPU_ADD;
      mask_reg <= '0;
    end else if (start && state == FPU_IDLE) begin
      op_a_reg <= operand_a;
      op_b_reg <= operand_b;
      op_c_reg <= operand_c;
      fpu_op_reg <= fpu_op;
      mask_reg <= active_mask;
    end
  end

  // Collect results
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      result_reg <= '0;
    end else begin
      // Store results from current lane group when valid
      if ((state == FPU_CYCLE1 || state == FPU_CYCLE2 ||
           state == FPU_CYCLE3 || state == FPU_CYCLE4) &&
          (!is_multicycle || all_fpu_valid)) begin
        for (int i = 0; i < NUM_LANES; i++) begin
          if (mask_reg[lane_offset + i]) begin
            result_reg[lane_offset + i] <= fpu_result[i];
          end
        end
      end
    end
  end

  // Output assignments
  assign result = result_reg;
  assign busy = (state != FPU_IDLE) && (state != FPU_DONE);
  assign result_valid = (state == FPU_DONE);

endmodule
