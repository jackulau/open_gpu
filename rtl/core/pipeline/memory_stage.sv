// Memory stage - load/store with byte enables and sign extension

module memory_stage
  import pkg_opengpu::*;
(
  input  logic                       clk,
  input  logic                       rst_n,

  // From execute
  input  logic [DATA_WIDTH-1:0]      alu_result,
  input  logic [DATA_WIDTH-1:0]      mem_wdata,
  input  decoded_instr_t             decoded,
  input  logic [ADDR_WIDTH-1:0]      pc_in,
  input  logic                       valid_in,

  // Control
  input  logic                       stall,
  input  logic                       flush,

  // Data memory
  output logic                       dmem_req,
  output logic                       dmem_we,
  output logic [ADDR_WIDTH-1:0]      dmem_addr,
  output logic [DATA_WIDTH-1:0]      dmem_wdata,
  output logic [3:0]                 dmem_be,
  input  logic [DATA_WIDTH-1:0]      dmem_rdata,
  input  logic                       dmem_valid,

  // To writeback
  output logic [DATA_WIDTH-1:0]      result,
  output decoded_instr_t             decoded_out,
  output logic [ADDR_WIDTH-1:0]      pc_out,
  output logic                       valid_out,
  output logic                       mem_busy
);

  mem_size_t mem_size;
  logic sign_extend;
  logic [1:0] byte_offset;

  assign byte_offset = alu_result[1:0];

  // Access size and sign extension
  always_comb begin
    mem_size = MEM_WORD;
    sign_extend = 1'b0;
    case (decoded.opcode)
      OP_LW, OP_SW:           begin mem_size = MEM_WORD; sign_extend = 1'b0; end
      OP_LH:                  begin mem_size = MEM_HALF; sign_extend = 1'b1; end
      OP_LHU, OP_SH:          begin mem_size = MEM_HALF; sign_extend = 1'b0; end
      OP_LB:                  begin mem_size = MEM_BYTE; sign_extend = 1'b1; end
      OP_LBU, OP_SB:          begin mem_size = MEM_BYTE; sign_extend = 1'b0; end
      default:                begin mem_size = MEM_WORD; sign_extend = 1'b0; end
    endcase
  end

  // Byte enables
  logic [3:0] byte_en;
  always_comb begin
    case (mem_size)
      MEM_BYTE: byte_en = 4'b0001 << byte_offset;
      MEM_HALF: byte_en = byte_offset[1] ? 4'b1100 : 4'b0011;
      default:  byte_en = 4'b1111;
    endcase
  end

  // Write data alignment
  logic [DATA_WIDTH-1:0] aligned_wdata;
  always_comb begin
    case (mem_size)
      MEM_BYTE: aligned_wdata = {4{mem_wdata[7:0]}};
      MEM_HALF: aligned_wdata = {2{mem_wdata[15:0]}};
      default:  aligned_wdata = mem_wdata;
    endcase
  end

  assign dmem_req   = valid_in && (decoded.mem_read || decoded.mem_write) && !stall;
  assign dmem_we    = decoded.mem_write;
  assign dmem_addr  = {alu_result[ADDR_WIDTH-1:2], 2'b00};
  assign dmem_wdata = aligned_wdata;
  assign dmem_be    = byte_en;

  // Read data extraction
  logic [DATA_WIDTH-1:0] extracted_data;
  always_comb begin
    case (mem_size)
      MEM_BYTE: begin
        case (byte_offset)
          2'b00: extracted_data = sign_extend ? {{24{dmem_rdata[7]}},  dmem_rdata[7:0]}   : {24'd0, dmem_rdata[7:0]};
          2'b01: extracted_data = sign_extend ? {{24{dmem_rdata[15]}}, dmem_rdata[15:8]}  : {24'd0, dmem_rdata[15:8]};
          2'b10: extracted_data = sign_extend ? {{24{dmem_rdata[23]}}, dmem_rdata[23:16]} : {24'd0, dmem_rdata[23:16]};
          2'b11: extracted_data = sign_extend ? {{24{dmem_rdata[31]}}, dmem_rdata[31:24]} : {24'd0, dmem_rdata[31:24]};
        endcase
      end
      MEM_HALF: begin
        case (byte_offset[1])
          1'b0: extracted_data = sign_extend ? {{16{dmem_rdata[15]}}, dmem_rdata[15:0]}  : {16'd0, dmem_rdata[15:0]};
          1'b1: extracted_data = sign_extend ? {{16{dmem_rdata[31]}}, dmem_rdata[31:16]} : {16'd0, dmem_rdata[31:16]};
        endcase
      end
      default: extracted_data = dmem_rdata;
    endcase
  end

  logic [DATA_WIDTH-1:0] result_mux;
  assign result_mux = (decoded.mem_read && dmem_valid) ? extracted_data : alu_result;

  logic mem_pending;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      mem_pending <= 1'b0;
    else if (dmem_req && !dmem_valid)
      mem_pending <= 1'b1;
    else if (dmem_valid)
      mem_pending <= 1'b0;
  end

  assign mem_busy = dmem_req && !dmem_valid;

  // Output registers
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      result      <= '0;
      decoded_out <= '0;
      pc_out      <= '0;
      valid_out   <= 1'b0;
    end else if (flush) begin
      result      <= '0;
      valid_out   <= 1'b0;
    end else if (!stall && (!dmem_req || dmem_valid)) begin
      result      <= result_mux;
      decoded_out <= decoded;
      pc_out      <= pc_in;
      valid_out   <= valid_in;
    end
  end

endmodule
