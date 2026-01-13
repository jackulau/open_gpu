// Integer ALU - combinational

module int_alu
  import pkg_opengpu::*;
(
  input  logic [DATA_WIDTH-1:0] operand_a,
  input  logic [DATA_WIDTH-1:0] operand_b,
  input  alu_op_t               alu_op,
  output logic [DATA_WIDTH-1:0] result,
  output logic                  zero_flag,
  output logic                  neg_flag
);

  logic signed [DATA_WIDTH-1:0] signed_a;
  logic signed [DATA_WIDTH-1:0] signed_b;
  logic signed [2*DATA_WIDTH-1:0] mul_result_signed;
  logic        [2*DATA_WIDTH-1:0] mul_result_unsigned;
  logic [4:0] shamt;

  assign signed_a = $signed(operand_a);
  assign signed_b = $signed(operand_b);
  assign shamt    = operand_b[4:0];
  assign mul_result_signed   = signed_a * signed_b;
  assign mul_result_unsigned = operand_a * operand_b;

  always_comb begin
    result = operand_a;

    case (alu_op)
      ALU_ADD:  result = operand_a + operand_b;
      ALU_SUB:  result = operand_a - operand_b;
      ALU_MUL:  result = mul_result_unsigned[DATA_WIDTH-1:0];
      ALU_MULH: result = mul_result_signed[2*DATA_WIDTH-1:DATA_WIDTH];

      ALU_DIV:  result = (operand_b == '0) ? '1 : signed_a / signed_b;
      ALU_DIVU: result = (operand_b == '0) ? '1 : operand_a / operand_b;
      ALU_REM:  result = (operand_b == '0) ? operand_a : signed_a % signed_b;
      ALU_REMU: result = (operand_b == '0) ? operand_a : operand_a % operand_b;

      ALU_AND:  result = operand_a & operand_b;
      ALU_OR:   result = operand_a | operand_b;
      ALU_XOR:  result = operand_a ^ operand_b;
      ALU_NOT:  result = ~operand_a;

      ALU_SLL:  result = operand_a << shamt;
      ALU_SRL:  result = operand_a >> shamt;
      ALU_SRA:  result = signed_a >>> shamt;

      ALU_SLT:  result = {31'd0, (signed_a < signed_b)};
      ALU_SLTU: result = {31'd0, (operand_a < operand_b)};
      ALU_SEQ:  result = {31'd0, (operand_a == operand_b)};
      ALU_SNE:  result = {31'd0, (operand_a != operand_b)};
      ALU_SGE:  result = {31'd0, (signed_a >= signed_b)};
      ALU_SGEU: result = {31'd0, (operand_a >= operand_b)};

      ALU_PASS_A: result = operand_a;
      ALU_PASS_B: result = operand_b;
      ALU_NOP:    result = '0;
      default:    result = '0;
    endcase
  end

  assign zero_flag = (result == '0);
  assign neg_flag  = result[DATA_WIDTH-1];

endmodule
