// FP Classifier - Classify IEEE 754 single precision values

module fp_classifier
  import pkg_opengpu::*;
(
  input  logic [DATA_WIDTH-1:0] value,
  output fp_class_t             fp_class,
  output logic                  sign,
  output logic [FP_EXP_WIDTH-1:0]  exponent,
  output logic [FP_MANT_WIDTH-1:0] mantissa,
  output logic                  is_zero,
  output logic                  is_inf,
  output logic                  is_nan,
  output logic                  is_snan,
  output logic                  is_qnan,
  output logic                  is_denormal,
  output logic                  is_normal
);

  assign sign     = value[31];
  assign exponent = value[30:23];
  assign mantissa = value[22:0];

  logic exp_all_ones;
  logic exp_all_zeros;
  logic mant_all_zeros;

  assign exp_all_ones  = (exponent == 8'hFF);
  assign exp_all_zeros = (exponent == 8'h00);
  assign mant_all_zeros = (mantissa == 23'd0);

  always_comb begin
    fp_class = FP_NORMAL;
    is_zero     = 1'b0;
    is_inf      = 1'b0;
    is_nan      = 1'b0;
    is_snan     = 1'b0;
    is_qnan     = 1'b0;
    is_denormal = 1'b0;
    is_normal   = 1'b0;

    if (exp_all_zeros && mant_all_zeros) begin
      fp_class = FP_ZERO;
      is_zero = 1'b1;
    end else if (exp_all_zeros) begin
      fp_class = FP_DENORMAL;
      is_denormal = 1'b1;
    end else if (exp_all_ones && mant_all_zeros) begin
      fp_class = FP_INF;
      is_inf = 1'b1;
    end else if (exp_all_ones && mantissa[22]) begin
      // Quiet NaN: mantissa[22] = 1
      fp_class = FP_QNAN;
      is_nan = 1'b1;
      is_qnan = 1'b1;
    end else if (exp_all_ones) begin
      // Signaling NaN: mantissa[22] = 0, mantissa != 0
      fp_class = FP_SNAN;
      is_nan = 1'b1;
      is_snan = 1'b1;
    end else begin
      fp_class = FP_NORMAL;
      is_normal = 1'b1;
    end
  end

endmodule
