// FP Multiply - IEEE 754 single precision multiplication

module fp_mul
  import pkg_opengpu::*;
(
  input  logic [DATA_WIDTH-1:0] operand_a,
  input  logic [DATA_WIDTH-1:0] operand_b,
  output logic [DATA_WIDTH-1:0] result
);

  // Canonical values
  localparam logic [31:0] POS_INF  = 32'h7F800000;
  localparam logic [31:0] QNAN     = 32'h7FC00000;
  localparam logic [31:0] POS_ZERO = 32'h00000000;

  // Unpack operands
  logic sign_a, sign_b;
  logic [7:0] exp_a, exp_b;
  logic [22:0] mant_a, mant_b;

  assign sign_a = operand_a[31];
  assign sign_b = operand_b[31];
  assign exp_a  = operand_a[30:23];
  assign exp_b  = operand_b[30:23];
  assign mant_a = operand_a[22:0];
  assign mant_b = operand_b[22:0];

  // Result sign
  logic result_sign;
  assign result_sign = sign_a ^ sign_b;

  // Special value detection
  logic is_nan_a, is_nan_b, is_inf_a, is_inf_b, is_zero_a, is_zero_b;
  assign is_nan_a  = (exp_a == 8'hFF) && (mant_a != 0);
  assign is_nan_b  = (exp_b == 8'hFF) && (mant_b != 0);
  assign is_inf_a  = (exp_a == 8'hFF) && (mant_a == 0);
  assign is_inf_b  = (exp_b == 8'hFF) && (mant_b == 0);
  assign is_zero_a = (exp_a == 8'h00) && (mant_a == 0);
  assign is_zero_b = (exp_b == 8'h00) && (mant_b == 0);

  logic is_denorm_a, is_denorm_b;
  assign is_denorm_a = (exp_a == 8'h00) && (mant_a != 0);
  assign is_denorm_b = (exp_b == 8'h00) && (mant_b != 0);

  // Add implicit 1 for normalized numbers (24-bit mantissa)
  logic [23:0] mant_a_full, mant_b_full;
  assign mant_a_full = (exp_a == 8'h00) ? {1'b0, mant_a} : {1'b1, mant_a};
  assign mant_b_full = (exp_b == 8'h00) ? {1'b0, mant_b} : {1'b1, mant_b};

  // 24x24 multiply = 48-bit result
  logic [47:0] mant_product;
  assign mant_product = mant_a_full * mant_b_full;

  // Calculate exponent (with bias adjustment)
  // exp_result = exp_a + exp_b - 127
  logic [9:0] exp_sum;
  assign exp_sum = {2'b0, exp_a} + {2'b0, exp_b};

  // Normalize product
  logic [9:0] exp_result;
  logic [22:0] mant_result;
  logic round_bit, guard_bit, sticky_bit;

  always_comb begin
    if (mant_product[47]) begin
      // Product >= 2, shift right by 1
      exp_result = exp_sum - 10'd126;  // -127 + 1 = -126
      mant_result = mant_product[46:24];
      guard_bit   = mant_product[23];
      round_bit   = mant_product[22];
      sticky_bit  = |mant_product[21:0];
    end else begin
      // Product in [1, 2)
      exp_result = exp_sum - 10'd127;
      mant_result = mant_product[45:23];
      guard_bit   = mant_product[22];
      round_bit   = mant_product[21];
      sticky_bit  = |mant_product[20:0];
    end
  end

  // Rounding (round to nearest, ties to even)
  logic round_up;
  logic [23:0] mant_rounded;
  assign round_up = guard_bit && (round_bit || sticky_bit || mant_result[0]);
  assign mant_rounded = {1'b0, mant_result} + {23'd0, round_up};

  // Handle rounding overflow
  logic [9:0] exp_final;
  logic [22:0] mant_final;

  always_comb begin
    if (mant_rounded[23]) begin
      exp_final = exp_result + 10'd1;
      mant_final = mant_rounded[23:1];
    end else begin
      exp_final = exp_result;
      mant_final = mant_rounded[22:0];
    end
  end

  // Final result assembly with special case handling
  always_comb begin
    if (is_nan_a || is_nan_b) begin
      result = QNAN;
    end else if (is_inf_a || is_inf_b) begin
      if (is_zero_a || is_zero_b)
        result = QNAN;  // 0 * inf = NaN
      else
        result = {result_sign, POS_INF[30:0]};
    end else if (is_zero_a || is_zero_b) begin
      result = {result_sign, 31'd0};
    end else if (is_denorm_a || is_denorm_b) begin
      // Simplified: treat denorm * anything as zero (flush to zero)
      result = {result_sign, 31'd0};
    end else if (exp_final >= 10'd255) begin
      // Overflow to infinity
      result = {result_sign, POS_INF[30:0]};
    end else if (exp_final[9] || exp_final == 10'd0) begin
      // Underflow to zero
      result = {result_sign, 31'd0};
    end else begin
      result = {result_sign, exp_final[7:0], mant_final};
    end
  end

endmodule
