// FP Divide - IEEE 754 single precision division
// Multi-cycle Newton-Raphson iteration

module fp_div
  import pkg_opengpu::*;
(
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  start,
  input  logic [DATA_WIDTH-1:0] operand_a,  // dividend
  input  logic [DATA_WIDTH-1:0] operand_b,  // divisor
  output logic [DATA_WIDTH-1:0] result,
  output logic                  valid,
  output logic                  busy
);

  // Canonical values
  localparam logic [31:0] POS_INF  = 32'h7F800000;
  localparam logic [31:0] QNAN     = 32'h7FC00000;

  // Unpack operands
  logic sign_a, sign_b, result_sign;
  logic [7:0] exp_a, exp_b;
  logic [22:0] mant_a, mant_b;

  assign sign_a = operand_a[31];
  assign sign_b = operand_b[31];
  assign result_sign = sign_a ^ sign_b;
  assign exp_a  = operand_a[30:23];
  assign exp_b  = operand_b[30:23];
  assign mant_a = operand_a[22:0];
  assign mant_b = operand_b[22:0];

  // Special value detection
  logic is_nan_a, is_nan_b, is_inf_a, is_inf_b, is_zero_a, is_zero_b;
  assign is_nan_a  = (exp_a == 8'hFF) && (mant_a != 0);
  assign is_nan_b  = (exp_b == 8'hFF) && (mant_b != 0);
  assign is_inf_a  = (exp_a == 8'hFF) && (mant_a == 0);
  assign is_inf_b  = (exp_b == 8'hFF) && (mant_b == 0);
  assign is_zero_a = (exp_a == 8'h00) && (mant_a == 0);
  assign is_zero_b = (exp_b == 8'h00) && (mant_b == 0);

  // State machine
  typedef enum logic [2:0] {
    IDLE, INIT, ITER1, ITER2, ITER3, NORMALIZE, DONE
  } div_state_t;

  div_state_t state, next_state;

  // Registers for Newton-Raphson
  logic [31:0] x_reg;           // Current reciprocal estimate
  logic [23:0] mant_a_reg;      // Saved dividend mantissa
  logic [23:0] mant_b_reg;      // Saved divisor mantissa
  logic [9:0]  exp_diff_reg;    // Exponent difference
  logic        result_sign_reg;
  logic [31:0] special_result;
  logic        use_special;

  // Newton-Raphson: x_{n+1} = x_n * (2 - b * x_n)
  // For 1/b, starting with initial estimate x_0

  // Fixed-point arithmetic (Q1.31 format)
  logic [63:0] mult_result;
  logic [31:0] two_minus_bx;
  logic [31:0] new_x;

  // Lookup table for initial estimate (based on high bits of mantissa)
  logic [31:0] init_estimate;
  always_comb begin
    // Simple linear approximation: 1/b ~ 2 - b for b in [1,2)
    // More accurate: use lookup table indexed by top bits
    // Here we use a rough estimate: ~1.5 - 0.5*b
    init_estimate = 32'hC0000000 - {1'b0, mant_b_reg, 7'd0};
  end

  // Main computation
  always_comb begin
    // b * x in Q2.62 format
    mult_result = {8'd0, mant_b_reg} * {8'd0, x_reg};
    // 2 - b*x (saturating)
    two_minus_bx = 64'h100000000 - mult_result[62:31];
    // x * (2 - b*x)
    new_x = (({8'd0, x_reg} * {8'd0, two_minus_bx}) >> 32);
  end

  // Compute final quotient
  logic [47:0] quotient_full;
  logic [31:0] quotient;
  always_comb begin
    quotient_full = {mant_a_reg, 24'd0} * {8'd0, x_reg};
    quotient = quotient_full[47:16];
  end

  // FSM
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      state <= IDLE;
    else
      state <= next_state;
  end

  always_comb begin
    next_state = state;
    case (state)
      IDLE:      if (start) next_state = INIT;
      INIT:      next_state = use_special ? DONE : ITER1;
      ITER1:     next_state = ITER2;
      ITER2:     next_state = ITER3;
      ITER3:     next_state = NORMALIZE;
      NORMALIZE: next_state = DONE;
      DONE:      next_state = IDLE;
      default:   next_state = IDLE;
    endcase
  end

  // Data path
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      x_reg <= '0;
      mant_a_reg <= '0;
      mant_b_reg <= '0;
      exp_diff_reg <= '0;
      result_sign_reg <= '0;
      special_result <= '0;
      use_special <= '0;
      result <= '0;
      valid <= '0;
    end else begin
      valid <= '0;

      case (state)
        IDLE: begin
          if (start) begin
            mant_a_reg <= {1'b1, mant_a};
            mant_b_reg <= {1'b1, mant_b};
            result_sign_reg <= result_sign;
            exp_diff_reg <= {2'b0, exp_a} - {2'b0, exp_b} + 10'd127;

            // Handle special cases
            if (is_nan_a || is_nan_b) begin
              special_result <= QNAN;
              use_special <= 1'b1;
            end else if (is_inf_a && is_inf_b) begin
              special_result <= QNAN;
              use_special <= 1'b1;
            end else if (is_zero_a && is_zero_b) begin
              special_result <= QNAN;
              use_special <= 1'b1;
            end else if (is_inf_a || is_zero_b) begin
              special_result <= {result_sign, POS_INF[30:0]};
              use_special <= 1'b1;
            end else if (is_zero_a || is_inf_b) begin
              special_result <= {result_sign, 31'd0};
              use_special <= 1'b1;
            end else begin
              use_special <= 1'b0;
            end
          end
        end

        INIT: begin
          x_reg <= init_estimate;
        end

        ITER1, ITER2, ITER3: begin
          x_reg <= new_x;
        end

        NORMALIZE: begin
          // Normalize quotient and assemble result
          logic [7:0] final_exp;
          logic [22:0] final_mant;

          if (quotient[31]) begin
            final_exp = exp_diff_reg[7:0] + 8'd1;
            final_mant = quotient[30:8];
          end else begin
            // Find leading 1 and normalize
            final_exp = exp_diff_reg[7:0];
            final_mant = quotient[29:7];
          end

          if (exp_diff_reg >= 10'd255) begin
            result <= {result_sign_reg, POS_INF[30:0]};
          end else if (exp_diff_reg[9] || exp_diff_reg == 10'd0) begin
            result <= {result_sign_reg, 31'd0};
          end else begin
            result <= {result_sign_reg, final_exp, final_mant};
          end
        end

        DONE: begin
          if (use_special)
            result <= special_result;
          valid <= 1'b1;
        end
      endcase
    end
  end

  assign busy = (state != IDLE) && (state != DONE);

endmodule
