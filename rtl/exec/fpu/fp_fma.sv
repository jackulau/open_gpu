// FP Fused Multiply-Add - FMADD, FMSUB
// result = (a * b) + c  for FMADD
// result = (a * b) - c  for FMSUB
// Simplified implementation: separate multiply then add (not fully fused)

module fp_fma
  import pkg_opengpu::*;
(
  input  logic [DATA_WIDTH-1:0] operand_a,
  input  logic [DATA_WIDTH-1:0] operand_b,
  input  logic [DATA_WIDTH-1:0] operand_c,
  input  logic                  negate_c,  // 1 for FMSUB
  output logic [DATA_WIDTH-1:0] result
);

  // Multiply a * b
  logic [DATA_WIDTH-1:0] mul_result;

  fp_mul u_mul (
    .operand_a(operand_a),
    .operand_b(operand_b),
    .result(mul_result)
  );

  // Negate c for FMSUB
  logic [DATA_WIDTH-1:0] c_adjusted;
  assign c_adjusted = negate_c ? {~operand_c[31], operand_c[30:0]} : operand_c;

  // Add (a*b) + c
  fp_addsub u_add (
    .operand_a(mul_result),
    .operand_b(c_adjusted),
    .subtract(1'b0),
    .result(result)
  );

endmodule
