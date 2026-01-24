// SIMT Memory Stage - Per-lane memory access with optional coalescing
// Handles load/store operations for all 32 lanes

module simt_memory_stage
  import pkg_opengpu::*;
(
  input  logic                          clk,
  input  logic                          rst_n,

  // Control
  input  logic                          stall,
  input  logic                          flush,

  // From execute
  input  simt_decoded_instr_t           decoded,
  input  logic [ADDR_WIDTH-1:0]         pc_in,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] alu_result,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] mem_wdata_in,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] mem_addr_in,
  input  logic                          valid_in,

  // Memory interface (coalesced)
  output logic                          mem_req_valid,
  output logic [WARP_SIZE-1:0]          mem_lane_valid,
  output logic [WARP_SIZE-1:0][ADDR_WIDTH-1:0] mem_lane_addr,
  output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] mem_lane_wdata,
  output logic                          mem_is_write,
  output mem_size_t                     mem_access_size,

  input  logic                          mem_req_ready,
  input  logic                          mem_resp_valid,
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] mem_resp_rdata,
  input  logic [WARP_SIZE-1:0]          mem_resp_lane_valid,

  // To writeback
  output simt_decoded_instr_t           decoded_out,
  output logic [ADDR_WIDTH-1:0]         pc_out,
  output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] result,
  output logic                          valid_out,

  // Memory busy (stall signal)
  output logic                          mem_busy
);

  // State machine for memory operations
  typedef enum logic [1:0] {
    MEM_IDLE,
    MEM_REQUEST,
    MEM_WAIT,
    MEM_DONE
  } mem_state_t;

  mem_state_t state, next_state;

  // Stored request
  simt_decoded_instr_t decoded_reg;
  logic [ADDR_WIDTH-1:0] pc_reg;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] alu_result_reg;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] mem_addr_reg;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] mem_wdata_reg;
  logic valid_reg;

  // Memory response data
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] load_data;

  // Access size determination
  function automatic mem_size_t get_mem_size(opcode_t op);
    case (op)
      OP_LB, OP_LBU, OP_SB: return MEM_BYTE;
      OP_LH, OP_LHU, OP_SH: return MEM_HALF;
      default: return MEM_WORD;
    endcase
  endfunction

  // Sign extension for loads
  function automatic logic [DATA_WIDTH-1:0] sign_extend_load(
    input logic [DATA_WIDTH-1:0] data,
    input opcode_t op
  );
    case (op)
      OP_LB:  return {{24{data[7]}}, data[7:0]};
      OP_LBU: return {24'd0, data[7:0]};
      OP_LH:  return {{16{data[15]}}, data[15:0]};
      OP_LHU: return {16'd0, data[15:0]};
      default: return data;
    endcase
  endfunction

  // State machine
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= MEM_IDLE;
    end else if (flush) begin
      state <= MEM_IDLE;
    end else begin
      state <= next_state;
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      MEM_IDLE: begin
        if (valid_in && (decoded.base.mem_read || decoded.base.mem_write) && !stall) begin
          next_state = MEM_REQUEST;
        end else if (valid_in && !stall) begin
          next_state = MEM_DONE;  // No memory op, pass through
        end
      end
      MEM_REQUEST: begin
        if (mem_req_ready) begin
          next_state = MEM_WAIT;
        end
      end
      MEM_WAIT: begin
        if (mem_resp_valid) begin
          next_state = MEM_DONE;
        end
      end
      MEM_DONE: begin
        if (!stall) begin
          next_state = MEM_IDLE;
        end
      end
      default: next_state = MEM_IDLE;
    endcase
  end

  // Store request on entry
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      decoded_reg <= '0;
      pc_reg <= '0;
      alu_result_reg <= '0;
      mem_addr_reg <= '0;
      mem_wdata_reg <= '0;
      valid_reg <= 1'b0;
    end else if (flush) begin
      valid_reg <= 1'b0;
    end else if (state == MEM_IDLE && valid_in && !stall) begin
      decoded_reg <= decoded;
      pc_reg <= pc_in;
      alu_result_reg <= alu_result;
      mem_addr_reg <= mem_addr_in;
      mem_wdata_reg <= mem_wdata_in;
      valid_reg <= 1'b1;
    end else if (state == MEM_DONE && !stall) begin
      valid_reg <= 1'b0;
    end
  end

  // Memory request signals
  assign mem_req_valid = (state == MEM_REQUEST);
  assign mem_lane_valid = decoded_reg.active_mask;
  assign mem_lane_addr = mem_addr_reg;
  assign mem_lane_wdata = mem_wdata_reg;
  assign mem_is_write = decoded_reg.base.mem_write;
  assign mem_access_size = get_mem_size(decoded_reg.base.opcode);

  // Store load response
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      load_data <= '0;
    end else if (mem_resp_valid) begin
      for (int lane = 0; lane < WARP_SIZE; lane++) begin
        if (mem_resp_lane_valid[lane]) begin
          load_data[lane] <= sign_extend_load(mem_resp_rdata[lane], decoded_reg.base.opcode);
        end
      end
    end
  end

  // Result selection
  always_comb begin
    for (int lane = 0; lane < WARP_SIZE; lane++) begin
      if (decoded_reg.base.mem_read) begin
        result[lane] = load_data[lane];
      end else begin
        result[lane] = alu_result_reg[lane];
      end
    end
  end

  // Output signals
  assign decoded_out = decoded_reg;
  assign pc_out = pc_reg;
  assign valid_out = (state == MEM_DONE) && valid_reg;
  assign mem_busy = (state != MEM_IDLE) && (state != MEM_DONE);

endmodule
