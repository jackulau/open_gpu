// Memory Coalescing Unit - Merges per-lane memory accesses into wide transactions
// Detects consecutive addresses and coalesces into efficient memory operations

module mem_coalescing_unit
  import pkg_opengpu::*;
#(
  parameter int CACHE_LINE_BYTES = CACHE_LINE_SIZE,  // 64 bytes
  parameter int MAX_TRANSACTION_BITS = COALESCE_WIDTH  // 128 bits max
)(
  input  logic                          clk,
  input  logic                          rst_n,

  // Request interface (from execution unit)
  input  logic                          req_valid,
  input  logic [WARP_SIZE-1:0]          lane_valid,      // Which lanes have requests
  input  logic [WARP_SIZE-1:0][ADDR_WIDTH-1:0] lane_addr,  // Per-lane addresses
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] lane_wdata, // Per-lane write data
  input  logic                          is_write,        // Write operation
  input  mem_size_t                     access_size,     // Byte/Half/Word

  output logic                          req_ready,       // Ready to accept request

  // Coalesced memory interface (to memory system)
  output logic                          mem_valid,
  output logic [ADDR_WIDTH-1:0]         mem_addr,        // Base address
  output logic [MAX_TRANSACTION_BITS-1:0] mem_wdata,     // Coalesced write data
  output logic [MAX_TRANSACTION_BITS/8-1:0] mem_wmask,   // Write byte mask
  output logic                          mem_write,
  output logic [3:0]                    mem_burst_len,   // Number of 32-bit words

  input  logic                          mem_ready,
  input  logic                          mem_valid_resp,
  input  logic [MAX_TRANSACTION_BITS-1:0] mem_rdata,

  // Response interface (back to execution unit)
  output logic                          resp_valid,
  output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] resp_rdata,
  output logic [WARP_SIZE-1:0]          resp_lane_valid
);

  // State machine
  typedef enum logic [2:0] {
    IDLE,
    ANALYZE,
    ISSUE,
    WAIT_RESP,
    DISTRIBUTE
  } state_t;

  state_t state, next_state;

  // Stored request
  logic [WARP_SIZE-1:0] pending_lanes;
  logic [WARP_SIZE-1:0] served_lanes;
  logic [WARP_SIZE-1:0][ADDR_WIDTH-1:0] stored_addr;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] stored_wdata;
  logic stored_write;
  mem_size_t stored_size;

  // Coalescing analysis
  logic [ADDR_WIDTH-1:0] base_addr;
  logic [ADDR_WIDTH-1:0] cache_line_base;
  logic [WARP_SIZE-1:0] same_line_mask;
  logic [WARP_SIZE-1:0] current_batch;
  logic [3:0] batch_size;

  // Cache line computation
  assign cache_line_base = base_addr & ~(CACHE_LINE_BYTES - 1);

  // Find first pending lane for base address
  logic [4:0] first_lane;
  always_comb begin
    logic found;
    first_lane = '0;
    found = 1'b0;
    for (int i = 0; i < WARP_SIZE; i++) begin
      if (pending_lanes[i] && !found) begin
        first_lane = i[4:0];
        found = 1'b1;
      end
    end
  end

  // Base address is from first pending lane
  assign base_addr = stored_addr[first_lane];

  // Identify lanes in same cache line as base
  always_comb begin
    for (int i = 0; i < WARP_SIZE; i++) begin
      same_line_mask[i] = pending_lanes[i] &&
                          ((stored_addr[i] & ~(CACHE_LINE_BYTES - 1)) == cache_line_base);
    end
  end

  // Determine current batch to process (lanes in same cache line)
  assign current_batch = same_line_mask;

  // Count lanes in current batch
  always_comb begin
    batch_size = '0;
    for (int i = 0; i < WARP_SIZE; i++) begin
      batch_size = batch_size + {3'b0, current_batch[i]};
    end
  end

  // State machine
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      IDLE: begin
        if (req_valid) next_state = ANALYZE;
      end
      ANALYZE: begin
        if (pending_lanes != '0) next_state = ISSUE;
        else next_state = IDLE;
      end
      ISSUE: begin
        if (mem_ready) next_state = WAIT_RESP;
      end
      WAIT_RESP: begin
        if (mem_valid_resp) next_state = DISTRIBUTE;
      end
      DISTRIBUTE: begin
        if ((pending_lanes & ~served_lanes) != '0) next_state = ANALYZE;
        else next_state = IDLE;
      end
      default: next_state = IDLE;
    endcase
  end

  // Store incoming request
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pending_lanes <= '0;
      served_lanes <= '0;
      stored_addr <= '0;
      stored_wdata <= '0;
      stored_write <= 1'b0;
      stored_size <= MEM_WORD;
    end else begin
      case (state)
        IDLE: begin
          if (req_valid) begin
            pending_lanes <= lane_valid;
            served_lanes <= '0;
            stored_addr <= lane_addr;
            stored_wdata <= lane_wdata;
            stored_write <= is_write;
            stored_size <= access_size;
          end
        end
        DISTRIBUTE: begin
          // Mark current batch as served
          served_lanes <= served_lanes | current_batch;
          pending_lanes <= pending_lanes & ~current_batch;
        end
        default: ;
      endcase
    end
  end

  // Memory request generation
  assign mem_valid = (state == ISSUE);
  assign mem_addr = cache_line_base;
  assign mem_write = stored_write;
  assign mem_burst_len = 4'd16;  // Full cache line (16 x 32-bit words)

  // Generate write data and mask for coalesced access
  always_comb begin
    mem_wdata = '0;
    mem_wmask = '0;

    for (int i = 0; i < WARP_SIZE; i++) begin
      if (current_batch[i]) begin
        // Calculate offset within cache line
        logic [5:0] byte_offset;
        byte_offset = stored_addr[i][5:0];  // Offset within 64-byte line

        case (stored_size)
          MEM_BYTE: begin
            mem_wdata[byte_offset*8 +: 8] = stored_wdata[i][7:0];
            mem_wmask[byte_offset] = 1'b1;
          end
          MEM_HALF: begin
            mem_wdata[byte_offset*8 +: 16] = stored_wdata[i][15:0];
            mem_wmask[byte_offset +: 2] = 2'b11;
          end
          MEM_WORD: begin
            mem_wdata[byte_offset*8 +: 32] = stored_wdata[i];
            mem_wmask[byte_offset +: 4] = 4'b1111;
          end
          default: ;
        endcase
      end
    end
  end

  // Response distribution
  logic [MAX_TRANSACTION_BITS-1:0] resp_data_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      resp_data_reg <= '0;
    end else if (mem_valid_resp) begin
      resp_data_reg <= mem_rdata;
    end
  end

  // Extract per-lane read data from coalesced response
  always_comb begin
    resp_rdata = '0;
    for (int i = 0; i < WARP_SIZE; i++) begin
      if (current_batch[i] && !stored_write) begin
        logic [5:0] byte_offset;
        byte_offset = stored_addr[i][5:0];

        case (stored_size)
          MEM_BYTE: resp_rdata[i] = {24'd0, resp_data_reg[byte_offset*8 +: 8]};
          MEM_HALF: resp_rdata[i] = {16'd0, resp_data_reg[byte_offset*8 +: 16]};
          MEM_WORD: resp_rdata[i] = resp_data_reg[byte_offset*8 +: 32];
          default:  resp_rdata[i] = '0;
        endcase
      end
    end
  end

  assign resp_valid = (state == DISTRIBUTE);
  assign resp_lane_valid = current_batch;
  assign req_ready = (state == IDLE);

endmodule
