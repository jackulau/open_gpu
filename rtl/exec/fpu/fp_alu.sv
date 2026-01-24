// FP ALU - Top-level Floating-Point Unit
// Supports all FPU operations with multi-cycle div/sqrt

module fp_alu
  import pkg_opengpu::*;
(
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  start,         // Begin operation
  input  fpu_op_t               fpu_op,
  input  logic [DATA_WIDTH-1:0] operand_a,     // rs1
  input  logic [DATA_WIDTH-1:0] operand_b,     // rs2
  input  logic [DATA_WIDTH-1:0] operand_c,     // rs3 (FMADD/FMSUB)
  output logic [DATA_WIDTH-1:0] result,
  output logic                  result_valid,  // Result ready
  output logic                  busy           // Multi-cycle in progress
);

  // Submodule results
  logic [DATA_WIDTH-1:0] addsub_result;
  logic [DATA_WIDTH-1:0] mul_result;
  logic [DATA_WIDTH-1:0] div_result;
  logic [DATA_WIDTH-1:0] sqrt_result;
  logic [DATA_WIDTH-1:0] misc_result;
  logic [DATA_WIDTH-1:0] compare_result;
  logic [DATA_WIDTH-1:0] convert_result;
  logic [DATA_WIDTH-1:0] fma_result;

  // Multi-cycle control
  logic div_start, div_valid, div_busy;
  logic sqrt_start, sqrt_valid, sqrt_busy;

  // Operation classification
  logic is_add, is_sub, is_mul, is_div, is_sqrt;
  logic is_misc, is_compare, is_convert, is_fma;

  assign is_add     = (fpu_op == FPU_ADD);
  assign is_sub     = (fpu_op == FPU_SUB);
  assign is_mul     = (fpu_op == FPU_MUL);
  assign is_div     = (fpu_op == FPU_DIV);
  assign is_sqrt    = (fpu_op == FPU_SQRT);
  assign is_misc    = (fpu_op == FPU_ABS) || (fpu_op == FPU_NEG) ||
                      (fpu_op == FPU_MIN) || (fpu_op == FPU_MAX);
  assign is_compare = (fpu_op == FPU_CMPEQ) || (fpu_op == FPU_CMPLT) ||
                      (fpu_op == FPU_CMPLE);
  assign is_convert = (fpu_op == FPU_CVTWS) || (fpu_op == FPU_CVTSW);
  assign is_fma     = (fpu_op == FPU_MADD) || (fpu_op == FPU_MSUB);

  // Multi-cycle start signals
  assign div_start  = start && is_div;
  assign sqrt_start = start && is_sqrt;

  // Add/Sub unit
  fp_addsub u_addsub (
    .operand_a(operand_a),
    .operand_b(operand_b),
    .subtract(is_sub),
    .result(addsub_result)
  );

  // Multiply unit
  fp_mul u_mul (
    .operand_a(operand_a),
    .operand_b(operand_b),
    .result(mul_result)
  );

  // Divide unit (multi-cycle)
  fp_div u_div (
    .clk(clk),
    .rst_n(rst_n),
    .start(div_start),
    .operand_a(operand_a),
    .operand_b(operand_b),
    .result(div_result),
    .valid(div_valid),
    .busy(div_busy)
  );

  // Square root unit (multi-cycle)
  fp_sqrt u_sqrt (
    .clk(clk),
    .rst_n(rst_n),
    .start(sqrt_start),
    .operand_a(operand_a),
    .result(sqrt_result),
    .valid(sqrt_valid),
    .busy(sqrt_busy)
  );

  // Misc operations (ABS, NEG, MIN, MAX)
  fp_misc u_misc (
    .operand_a(operand_a),
    .operand_b(operand_b),
    .fpu_op(fpu_op),
    .result(misc_result)
  );

  // Compare operations
  fp_compare u_compare (
    .operand_a(operand_a),
    .operand_b(operand_b),
    .fpu_op(fpu_op),
    .result(compare_result)
  );

  // Convert operations
  fp_convert u_convert (
    .operand_a(operand_a),
    .fpu_op(fpu_op),
    .result(convert_result)
  );

  // FMA operations
  fp_fma u_fma (
    .operand_a(operand_a),
    .operand_b(operand_b),
    .operand_c(operand_c),
    .negate_c(fpu_op == FPU_MSUB),
    .result(fma_result)
  );

  // Result mux
  always_comb begin
    case (fpu_op)
      FPU_ADD, FPU_SUB:               result = addsub_result;
      FPU_MUL:                        result = mul_result;
      FPU_DIV:                        result = div_result;
      FPU_SQRT:                       result = sqrt_result;
      FPU_ABS, FPU_NEG,
      FPU_MIN, FPU_MAX:               result = misc_result;
      FPU_CMPEQ, FPU_CMPLT, FPU_CMPLE: result = compare_result;
      FPU_CVTWS, FPU_CVTSW:           result = convert_result;
      FPU_MADD, FPU_MSUB:             result = fma_result;
      default:                        result = 32'd0;
    endcase
  end

  // Busy signal (multi-cycle operations)
  assign busy = div_busy || sqrt_busy;

  // Result valid
  // Single-cycle ops: valid immediately when started
  // Multi-cycle ops: valid when unit signals completion
  always_comb begin
    if (is_div)
      result_valid = div_valid;
    else if (is_sqrt)
      result_valid = sqrt_valid;
    else
      result_valid = start && !busy;  // Single-cycle ops
  end

endmodule
