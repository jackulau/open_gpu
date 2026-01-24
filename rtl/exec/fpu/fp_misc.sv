// FP Misc Operations - FABS, FNEG, FMIN, FMAX

module fp_misc
  import pkg_opengpu::*;
(
  input  logic [DATA_WIDTH-1:0] operand_a,
  input  logic [DATA_WIDTH-1:0] operand_b,
  input  fpu_op_t               fpu_op,
  output logic [DATA_WIDTH-1:0] result
);

  // Classification for operand_a
  logic sign_a, sign_b;
  logic [FP_EXP_WIDTH-1:0] exp_a, exp_b;
  logic [FP_MANT_WIDTH-1:0] mant_a, mant_b;
  logic is_nan_a, is_nan_b;

  assign sign_a = operand_a[31];
  assign sign_b = operand_b[31];
  assign exp_a  = operand_a[30:23];
  assign exp_b  = operand_b[30:23];
  assign mant_a = operand_a[22:0];
  assign mant_b = operand_b[22:0];

  assign is_nan_a = (exp_a == 8'hFF) && (mant_a != 23'd0);
  assign is_nan_b = (exp_b == 8'hFF) && (mant_b != 23'd0);

  // Canonical quiet NaN
  localparam logic [31:0] QNAN = 32'h7FC00000;

  // Compare magnitudes (absolute values)
  logic a_less_than_b;
  always_comb begin
    if (exp_a < exp_b)
      a_less_than_b = 1'b1;
    else if (exp_a > exp_b)
      a_less_than_b = 1'b0;
    else
      a_less_than_b = (mant_a < mant_b);
  end

  // Signed comparison for min/max
  logic a_lt_b_signed;
  always_comb begin
    if (sign_a != sign_b) begin
      // Different signs: negative is smaller
      a_lt_b_signed = sign_a && !sign_b;
    end else if (sign_a) begin
      // Both negative: larger magnitude is smaller
      a_lt_b_signed = !a_less_than_b && (operand_a != operand_b);
    end else begin
      // Both positive: smaller magnitude is smaller
      a_lt_b_signed = a_less_than_b;
    end
  end

  always_comb begin
    result = operand_a;

    case (fpu_op)
      FPU_ABS: begin
        // Clear sign bit
        result = {1'b0, operand_a[30:0]};
      end

      FPU_NEG: begin
        // Flip sign bit
        result = {~operand_a[31], operand_a[30:0]};
      end

      FPU_MIN: begin
        if (is_nan_a && is_nan_b)
          result = QNAN;
        else if (is_nan_a)
          result = operand_b;
        else if (is_nan_b)
          result = operand_a;
        else
          result = a_lt_b_signed ? operand_a : operand_b;
      end

      FPU_MAX: begin
        if (is_nan_a && is_nan_b)
          result = QNAN;
        else if (is_nan_a)
          result = operand_b;
        else if (is_nan_b)
          result = operand_a;
        else
          result = a_lt_b_signed ? operand_b : operand_a;
      end

      default: result = operand_a;
    endcase
  end

endmodule
