// FP Compare - FCMPEQ, FCMPLT, FCMPLE
// Returns integer 1 if true, 0 if false
// Comparisons with NaN return 0

module fp_compare
  import pkg_opengpu::*;
(
  input  logic [DATA_WIDTH-1:0] operand_a,
  input  logic [DATA_WIDTH-1:0] operand_b,
  input  fpu_op_t               fpu_op,
  output logic [DATA_WIDTH-1:0] result
);

  logic sign_a, sign_b;
  logic [FP_EXP_WIDTH-1:0] exp_a, exp_b;
  logic [FP_MANT_WIDTH-1:0] mant_a, mant_b;
  logic is_nan_a, is_nan_b;
  logic is_zero_a, is_zero_b;

  assign sign_a = operand_a[31];
  assign sign_b = operand_b[31];
  assign exp_a  = operand_a[30:23];
  assign exp_b  = operand_b[30:23];
  assign mant_a = operand_a[22:0];
  assign mant_b = operand_b[22:0];

  assign is_nan_a  = (exp_a == 8'hFF) && (mant_a != 23'd0);
  assign is_nan_b  = (exp_b == 8'hFF) && (mant_b != 23'd0);
  assign is_zero_a = (exp_a == 8'h00) && (mant_a == 23'd0);
  assign is_zero_b = (exp_b == 8'h00) && (mant_b == 23'd0);

  // Equality check (+0 == -0)
  logic is_equal;
  assign is_equal = (is_zero_a && is_zero_b) || (operand_a == operand_b);

  // Less-than check
  logic a_less_than_b;
  always_comb begin
    if (is_zero_a && is_zero_b) begin
      // +0 and -0 are equal
      a_less_than_b = 1'b0;
    end else if (sign_a != sign_b) begin
      // Different signs: negative is smaller
      a_less_than_b = sign_a;
    end else begin
      // Same sign: compare magnitude
      logic mag_a_less;
      if (exp_a < exp_b)
        mag_a_less = 1'b1;
      else if (exp_a > exp_b)
        mag_a_less = 1'b0;
      else
        mag_a_less = (mant_a < mant_b);

      // For negative numbers, larger magnitude means smaller value
      a_less_than_b = sign_a ? !mag_a_less && !is_equal : mag_a_less;
    end
  end

  always_comb begin
    result = 32'd0;

    // NaN comparisons always return false
    if (is_nan_a || is_nan_b) begin
      result = 32'd0;
    end else begin
      case (fpu_op)
        FPU_CMPEQ: result = {31'd0, is_equal};
        FPU_CMPLT: result = {31'd0, a_less_than_b};
        FPU_CMPLE: result = {31'd0, a_less_than_b || is_equal};
        default:   result = 32'd0;
      endcase
    end
  end

endmodule
