// FP Convert - Float <-> Integer conversions
// FCVTWS: Float to signed 32-bit integer (truncate toward zero)
// FCVTSW: Signed 32-bit integer to float

module fp_convert
  import pkg_opengpu::*;
(
  input  logic [DATA_WIDTH-1:0] operand_a,
  input  fpu_op_t               fpu_op,
  output logic [DATA_WIDTH-1:0] result
);

  // Float to int signals
  logic f2i_sign;
  logic [7:0] f2i_exp;
  logic [22:0] f2i_mant;
  logic f2i_is_nan, f2i_is_inf;

  assign f2i_sign = operand_a[31];
  assign f2i_exp  = operand_a[30:23];
  assign f2i_mant = operand_a[22:0];
  assign f2i_is_nan = (f2i_exp == 8'hFF) && (f2i_mant != 0);
  assign f2i_is_inf = (f2i_exp == 8'hFF) && (f2i_mant == 0);

  // FCVTWS: Float to signed int
  logic [31:0] f2i_result;
  always_comb begin
    logic [7:0] unbiased_exp;
    logic [55:0] mant_extended;  // 1.mant << 31 for maximum precision
    logic [31:0] shifted_mant;

    f2i_result = 32'd0;

    if (f2i_is_nan) begin
      // NaN -> INT_MAX
      f2i_result = 32'h7FFFFFFF;
    end else if (f2i_is_inf) begin
      f2i_result = f2i_sign ? 32'h80000000 : 32'h7FFFFFFF;
    end else if (f2i_exp < 8'd127) begin
      // |value| < 1, truncate to 0
      f2i_result = 32'd0;
    end else if (f2i_exp >= 8'd158) begin
      // Overflow (2^31 or larger)
      f2i_result = f2i_sign ? 32'h80000000 : 32'h7FFFFFFF;
    end else begin
      // Normal conversion
      unbiased_exp = f2i_exp - 8'd127;  // 0-30 range
      mant_extended = {1'b1, f2i_mant, 32'd0};

      // Shift right by (31 - unbiased_exp) to get integer part
      if (unbiased_exp <= 8'd31)
        shifted_mant = mant_extended[55:24] >> (8'd31 - unbiased_exp);
      else
        shifted_mant = mant_extended[55:24] << (unbiased_exp - 8'd31);

      // Apply sign
      if (f2i_sign)
        f2i_result = -shifted_mant;
      else
        f2i_result = shifted_mant;
    end
  end

  // FCVTSW: Signed int to float
  logic [31:0] i2f_result;
  always_comb begin
    logic i2f_sign;
    logic [31:0] abs_val;
    logic [4:0] leading_zero_count;
    logic [31:0] normalized_mant;
    logic [7:0] i2f_exp;
    logic [22:0] i2f_mant;

    i2f_result = 32'd0;

    if (operand_a == 32'd0) begin
      i2f_result = 32'd0;
    end else begin
      // Get sign and absolute value
      i2f_sign = operand_a[31];
      abs_val = i2f_sign ? -operand_a : operand_a;

      // Count leading zeros to normalize
      leading_zero_count = 5'd0;
      for (int i = 31; i >= 0; i--) begin
        if (abs_val[i]) begin
          leading_zero_count = 5'd31 - i[4:0];
          break;
        end
      end

      // Normalize: shift left so MSB is in bit 31
      normalized_mant = abs_val << leading_zero_count;

      // Exponent: position of MSB (31 - leading_zeros) + bias
      i2f_exp = 8'd158 - {3'd0, leading_zero_count};  // 158 = 127 + 31

      // Mantissa: bits [30:8] of normalized value (drop implicit 1)
      // Round to nearest even
      logic round_bit, sticky_bit;
      round_bit = normalized_mant[8];
      sticky_bit = |normalized_mant[7:0];

      i2f_mant = normalized_mant[30:8];

      if (round_bit && (sticky_bit || normalized_mant[9])) begin
        {i2f_exp, i2f_mant} = {i2f_exp, i2f_mant} + 31'd1;
      end

      i2f_result = {i2f_sign, i2f_exp, i2f_mant};
    end
  end

  // Output mux
  always_comb begin
    case (fpu_op)
      FPU_CVTWS: result = f2i_result;
      FPU_CVTSW: result = i2f_result;
      default:   result = 32'd0;
    endcase
  end

endmodule
