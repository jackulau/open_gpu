// FP Square Root - IEEE 754 single precision
// Multi-cycle Newton-Raphson iteration for 1/sqrt(x), then multiply by x

module fp_sqrt
  import pkg_opengpu::*;
(
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  start,
  input  logic [DATA_WIDTH-1:0] operand_a,
  output logic [DATA_WIDTH-1:0] result,
  output logic                  valid,
  output logic                  busy
);

  // Canonical values
  localparam logic [31:0] POS_INF  = 32'h7F800000;
  localparam logic [31:0] QNAN     = 32'h7FC00000;

  // Unpack operand
  logic sign_a;
  logic [7:0] exp_a;
  logic [22:0] mant_a;

  assign sign_a = operand_a[31];
  assign exp_a  = operand_a[30:23];
  assign mant_a = operand_a[22:0];

  // Special value detection
  logic is_nan, is_inf, is_zero, is_negative;
  assign is_nan      = (exp_a == 8'hFF) && (mant_a != 0);
  assign is_inf      = (exp_a == 8'hFF) && (mant_a == 0);
  assign is_zero     = (exp_a == 8'h00) && (mant_a == 0);
  assign is_negative = sign_a && !is_zero;

  // State machine
  typedef enum logic [2:0] {
    IDLE, INIT, ITER1, ITER2, ITER3, FINAL_MUL, DONE
  } sqrt_state_t;

  sqrt_state_t state, next_state;

  // Registers
  logic [31:0] y_reg;           // 1/sqrt(x) estimate
  logic [31:0] x_half_reg;      // x/2 for Newton-Raphson
  logic [31:0] x_reg;           // Original x mantissa
  logic [8:0]  exp_result_reg;  // Result exponent
  logic [31:0] special_result;
  logic        use_special;

  // Newton-Raphson for 1/sqrt(x): y_{n+1} = y_n * (1.5 - 0.5*x*y_n^2)

  // Fixed-point arithmetic
  logic [63:0] y_squared;
  logic [63:0] x_y_squared;
  logic [31:0] three_halves_minus_xy2;
  logic [63:0] new_y_full;
  logic [31:0] new_y;

  always_comb begin
    y_squared = y_reg * y_reg;
    x_y_squared = x_half_reg * y_squared[62:31];
    three_halves_minus_xy2 = 32'hC0000000 - x_y_squared[62:31];
    new_y_full = y_reg * three_halves_minus_xy2;
    new_y = new_y_full[62:31];
  end

  // Final result: sqrt(x) = x * (1/sqrt(x))
  logic [63:0] sqrt_result_full;
  logic [31:0] sqrt_result;
  always_comb begin
    sqrt_result_full = x_reg * y_reg;
    sqrt_result = sqrt_result_full[62:31];
  end

  // Initial estimate using lookup
  logic [31:0] init_estimate;
  always_comb begin
    // Rough estimate based on exponent and mantissa
    // For x in [1,4), 1/sqrt(x) is in [0.5, 1]
    init_estimate = 32'h5F3759DF - (operand_a >> 1);  // Famous fast inverse sqrt
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
      ITER3:     next_state = FINAL_MUL;
      FINAL_MUL: next_state = DONE;
      DONE:      next_state = IDLE;
      default:   next_state = IDLE;
    endcase
  end

  // Data path
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      y_reg <= '0;
      x_half_reg <= '0;
      x_reg <= '0;
      exp_result_reg <= '0;
      special_result <= '0;
      use_special <= '0;
      result <= '0;
      valid <= '0;
    end else begin
      valid <= '0;

      case (state)
        IDLE: begin
          if (start) begin
            // Prepare mantissa with implicit 1
            logic [23:0] full_mant;
            full_mant = {1'b1, mant_a};

            // Normalize to [1,4) range based on exponent parity
            if (exp_a[0]) begin
              // Odd exponent: mantissa is in [1,2), shift left
              x_reg <= {full_mant, 8'd0};
              x_half_reg <= {1'b0, full_mant, 7'd0};
            end else begin
              // Even exponent: mantissa already good
              x_reg <= {full_mant, 8'd0};
              x_half_reg <= {1'b0, full_mant, 7'd0};
            end

            // Result exponent: (exp - 127) / 2 + 127 = (exp + 127) / 2
            exp_result_reg <= ({1'b0, exp_a} + 9'd127) >> 1;

            // Handle special cases
            if (is_nan || is_negative) begin
              special_result <= QNAN;
              use_special <= 1'b1;
            end else if (is_inf) begin
              special_result <= POS_INF;
              use_special <= 1'b1;
            end else if (is_zero) begin
              special_result <= operand_a;  // sqrt(+/-0) = +/-0
              use_special <= 1'b1;
            end else begin
              use_special <= 1'b0;
            end
          end
        end

        INIT: begin
          // Use lookup table estimate
          y_reg <= init_estimate[30:0];
        end

        ITER1, ITER2, ITER3: begin
          y_reg <= new_y;
        end

        FINAL_MUL: begin
          // Compute final result
          logic [7:0] final_exp;
          logic [22:0] final_mant;

          if (sqrt_result[31]) begin
            final_exp = exp_result_reg[7:0];
            final_mant = sqrt_result[30:8];
          end else begin
            final_exp = exp_result_reg[7:0] - 8'd1;
            final_mant = sqrt_result[29:7];
          end

          result <= {1'b0, final_exp, final_mant};
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
