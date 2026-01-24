// FP Add/Sub - IEEE 754 single precision addition and subtraction

module fp_addsub
  import pkg_opengpu::*;
(
  input  logic [DATA_WIDTH-1:0] operand_a,
  input  logic [DATA_WIDTH-1:0] operand_b,
  input  logic                  subtract,  // 1 for SUB, 0 for ADD
  output logic [DATA_WIDTH-1:0] result
);

  // Canonical values
  localparam logic [31:0] POS_INF = 32'h7F800000;
  localparam logic [31:0] NEG_INF = 32'hFF800000;
  localparam logic [31:0] QNAN    = 32'h7FC00000;
  localparam logic [31:0] POS_ZERO = 32'h00000000;

  // Unpack operands
  logic sign_a, sign_b, sign_b_eff;
  logic [7:0] exp_a, exp_b;
  logic [22:0] mant_a, mant_b;

  assign sign_a = operand_a[31];
  assign sign_b = operand_b[31];
  assign exp_a  = operand_a[30:23];
  assign exp_b  = operand_b[30:23];
  assign mant_a = operand_a[22:0];
  assign mant_b = operand_b[22:0];

  // Effective sign of B (flipped for subtraction)
  assign sign_b_eff = sign_b ^ subtract;

  // Special value detection
  logic is_nan_a, is_nan_b, is_inf_a, is_inf_b, is_zero_a, is_zero_b;
  assign is_nan_a  = (exp_a == 8'hFF) && (mant_a != 0);
  assign is_nan_b  = (exp_b == 8'hFF) && (mant_b != 0);
  assign is_inf_a  = (exp_a == 8'hFF) && (mant_a == 0);
  assign is_inf_b  = (exp_b == 8'hFF) && (mant_b == 0);
  assign is_zero_a = (exp_a == 8'h00) && (mant_a == 0);
  assign is_zero_b = (exp_b == 8'h00) && (mant_b == 0);

  // Add implicit 1 for normalized numbers (24-bit mantissa)
  logic [23:0] mant_a_full, mant_b_full;
  assign mant_a_full = (exp_a == 8'h00) ? {1'b0, mant_a} : {1'b1, mant_a};
  assign mant_b_full = (exp_b == 8'h00) ? {1'b0, mant_b} : {1'b1, mant_b};

  // Alignment
  logic swap;
  logic [7:0] exp_large, exp_small;
  logic [23:0] mant_large, mant_small;
  logic sign_large, sign_small;

  assign swap = (exp_b > exp_a) || ((exp_b == exp_a) && (mant_b > mant_a));

  always_comb begin
    if (swap) begin
      exp_large  = exp_b;
      exp_small  = exp_a;
      mant_large = mant_b_full;
      mant_small = mant_a_full;
      sign_large = sign_b_eff;
      sign_small = sign_a;
    end else begin
      exp_large  = exp_a;
      exp_small  = exp_b;
      mant_large = mant_a_full;
      mant_small = mant_b_full;
      sign_large = sign_a;
      sign_small = sign_b_eff;
    end
  end

  // Shift smaller mantissa
  logic [7:0] exp_diff;
  logic [26:0] mant_small_shifted;  // Extra bits for rounding (guard, round, sticky)

  assign exp_diff = exp_large - exp_small;

  always_comb begin
    if (exp_diff > 8'd26)
      mant_small_shifted = 27'd0;
    else
      mant_small_shifted = {mant_small, 3'b000} >> exp_diff;
  end

  // Add or subtract mantissas
  logic effective_sub;
  logic [27:0] mant_sum;
  logic result_sign;

  assign effective_sub = sign_large != sign_small;

  always_comb begin
    if (effective_sub) begin
      mant_sum = {1'b0, mant_large, 3'b000} - {1'b0, mant_small_shifted};
      result_sign = sign_large;
    end else begin
      mant_sum = {1'b0, mant_large, 3'b000} + {1'b0, mant_small_shifted};
      result_sign = sign_large;
    end
  end

  // Normalize
  logic [7:0] result_exp;
  logic [22:0] result_mant;
  logic [4:0] leading_zeros;

  // Count leading zeros in mant_sum
  always_comb begin
    leading_zeros = 5'd0;
    for (int i = 27; i >= 0; i--) begin
      if (mant_sum[i]) begin
        leading_zeros = 5'd27 - i[4:0];
        break;
      end
    end
    if (mant_sum == 28'd0)
      leading_zeros = 5'd28;
  end

  logic [27:0] mant_normalized;
  logic [8:0] exp_adjusted;

  always_comb begin
    if (mant_sum[27]) begin
      // Overflow: shift right
      mant_normalized = mant_sum >> 1;
      exp_adjusted = {1'b0, exp_large} + 9'd1;
    end else if (leading_zeros > 0 && exp_large >= leading_zeros) begin
      // Shift left to normalize
      mant_normalized = mant_sum << (leading_zeros - 1);
      exp_adjusted = {1'b0, exp_large} - {4'd0, leading_zeros} + 9'd1;
    end else if (leading_zeros > 0 && exp_large > 0) begin
      // Denormalize
      mant_normalized = mant_sum << (exp_large - 1);
      exp_adjusted = 9'd0;
    end else begin
      mant_normalized = mant_sum;
      exp_adjusted = {1'b0, exp_large};
    end
  end

  // Rounding (round to nearest, ties to even)
  logic round_bit, sticky_bit, guard_bit;
  logic [23:0] mant_rounded;

  assign guard_bit  = mant_normalized[3];
  assign round_bit  = mant_normalized[2];
  assign sticky_bit = |mant_normalized[1:0];

  logic round_up;
  assign round_up = guard_bit && (round_bit || sticky_bit || mant_normalized[4]);

  always_comb begin
    mant_rounded = mant_normalized[26:3] + {23'd0, round_up};
  end

  // Final result assembly
  always_comb begin
    // Handle special cases
    if (is_nan_a || is_nan_b) begin
      result = QNAN;
    end else if (is_inf_a && is_inf_b) begin
      if (sign_a == sign_b_eff)
        result = {sign_a, POS_INF[30:0]};
      else
        result = QNAN;  // inf - inf = NaN
    end else if (is_inf_a) begin
      result = operand_a;
    end else if (is_inf_b) begin
      result = {sign_b_eff, POS_INF[30:0]};
    end else if (is_zero_a && is_zero_b) begin
      // -0 + -0 = -0, otherwise +0
      result = (sign_a && sign_b_eff) ? NEG_INF & 32'h80000000 : POS_ZERO;
    end else if (is_zero_a) begin
      result = {sign_b_eff, operand_b[30:0]};
    end else if (is_zero_b) begin
      result = operand_a;
    end else if (mant_sum == 28'd0) begin
      result = POS_ZERO;
    end else if (exp_adjusted >= 9'd255) begin
      // Overflow to infinity
      result = {result_sign, POS_INF[30:0]};
    end else if (exp_adjusted == 9'd0 || mant_rounded[23] == 1'b0) begin
      // Denormalized or zero
      if (mant_rounded[22:0] == 23'd0 && mant_rounded[23] == 1'b0)
        result = POS_ZERO;
      else
        result = {result_sign, 8'd0, mant_rounded[22:0]};
    end else begin
      // Handle rounding overflow
      if (mant_rounded[23] && mant_normalized[26]) begin
        // Rounding caused overflow of normalized mantissa
        result = {result_sign, exp_adjusted[7:0] + 8'd1, 23'd0};
      end else begin
        result = {result_sign, exp_adjusted[7:0], mant_rounded[22:0]};
      end
    end
  end

endmodule
