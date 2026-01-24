// SIMD Integer ALU - 32 parallel lanes for SIMT execution
// Instantiates 32 copies of the scalar int_alu

module simd_int_alu
  import pkg_opengpu::*;
(
  // Per-lane operands
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] operand_a,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] operand_b,

  // Shared ALU operation (same for all lanes)
  input  alu_op_t                              alu_op,

  // Active mask - only active lanes compute
  input  logic [WARP_SIZE-1:0]                 active_mask,

  // Per-lane results
  output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] result,
  output logic [WARP_SIZE-1:0]                 zero_flags,
  output logic [WARP_SIZE-1:0]                 neg_flags,

  // Aggregate flags (across active lanes)
  output logic                                 any_zero,
  output logic                                 all_zero,
  output logic                                 any_neg,
  output logic                                 all_neg
);

  // Per-lane ALU instances
  genvar lane;
  generate
    for (lane = 0; lane < WARP_SIZE; lane++) begin : gen_alu_lanes
      int_alu alu_inst (
        .operand_a(operand_a[lane]),
        .operand_b(operand_b[lane]),
        .alu_op(alu_op),
        .result(result[lane]),
        .zero_flag(zero_flags[lane]),
        .neg_flag(neg_flags[lane])
      );
    end
  endgenerate

  // Aggregate flag computation (only for active lanes)
  always_comb begin
    any_zero = 1'b0;
    all_zero = 1'b1;
    any_neg = 1'b0;
    all_neg = 1'b1;

    for (int i = 0; i < WARP_SIZE; i++) begin
      if (active_mask[i]) begin
        any_zero = any_zero | zero_flags[i];
        all_zero = all_zero & zero_flags[i];
        any_neg = any_neg | neg_flags[i];
        all_neg = all_neg & neg_flags[i];
      end
    end

    // If no lanes active, all_* should be false
    if (active_mask == '0) begin
      all_zero = 1'b0;
      all_neg = 1'b0;
    end
  end

endmodule
