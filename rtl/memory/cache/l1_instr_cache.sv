// L1 Instruction Cache - 16KB, 4-way set associative
// Read-only cache with LRU replacement
// Compatible with Icarus Verilog

module l1_instr_cache
  import pkg_opengpu::*;
#(
  parameter int CACHE_SIZE_KB = L1I_SIZE_KB,  // 16 KB
  parameter int NUM_WAYS = L1_WAYS,           // 4-way
  parameter int LINE_BYTES = CACHE_LINE_BYTES // 64 bytes
)(
  input  logic                          clk,
  input  logic                          rst_n,

  // CPU-side interface (from fetch stage)
  input  logic                          req_valid,
  input  logic [ADDR_WIDTH-1:0]         req_addr,

  output logic                          resp_valid,
  output logic                          resp_hit,
  output logic [INSTR_WIDTH-1:0]        resp_instr,
  output logic                          ready,

  // L2/Memory-side interface
  output logic                          l2_req_valid,
  output logic [ADDR_WIDTH-1:0]         l2_req_addr,

  input  logic                          l2_resp_valid,
  input  logic [CACHE_LINE_BITS-1:0]    l2_resp_rdata,
  input  logic                          l2_ready,

  // Invalidate control (for coherency)
  input  logic                          invalidate_req,
  input  logic [ADDR_WIDTH-1:0]         invalidate_addr,
  output logic                          invalidate_done,

  // Statistics
  output cache_stats_t                  stats
);

  // Cache parameters
  localparam int NUM_SETS = (CACHE_SIZE_KB * 1024) / (LINE_BYTES * NUM_WAYS);
  localparam int SET_BITS = $clog2(NUM_SETS);
  localparam int OFFSET_BITS = $clog2(LINE_BYTES);
  localparam int TAG_BITS = ADDR_WIDTH - SET_BITS - OFFSET_BITS;
  localparam int WORDS_PER_LINE = LINE_BYTES / 4;

  // Cache storage
  logic [TAG_BITS-1:0]          tag_array [0:NUM_SETS-1][0:NUM_WAYS-1];
  logic [CACHE_LINE_BITS-1:0]   data_array [0:NUM_SETS-1][0:NUM_WAYS-1];
  logic [NUM_WAYS-1:0]          valid_array [0:NUM_SETS-1];

  // LRU state
  logic [1:0] lru_array [0:NUM_SETS-1][0:NUM_WAYS-1];

  // Address field extraction (input)
  logic [OFFSET_BITS-1:0] offset_in;
  logic [SET_BITS-1:0]    set_idx_in;
  logic [TAG_BITS-1:0]    tag_in;

  assign offset_in = req_addr[OFFSET_BITS-1:0];
  assign set_idx_in = req_addr[OFFSET_BITS +: SET_BITS];
  assign tag_in = req_addr[ADDR_WIDTH-1 -: TAG_BITS];

  // State machine
  typedef enum logic [1:0] {
    IDLE,
    TAG_CHECK,
    FILL_WAIT,
    UPDATE
  } cache_state_t;

  cache_state_t state, next_state;

  // Registered request
  logic [ADDR_WIDTH-1:0] req_addr_reg;
  logic [SET_BITS-1:0]   set_idx;
  logic [TAG_BITS-1:0]   tag;
  logic [OFFSET_BITS-1:0] offset;

  // Hit detection
  logic [NUM_WAYS-1:0] way_hit;
  logic cache_hit;
  logic [1:0] hit_way;

  always_comb begin
    way_hit = '0;
    cache_hit = 1'b0;
    hit_way = '0;

    for (int w = 0; w < NUM_WAYS; w++) begin
      if (valid_array[set_idx][w] && (tag_array[set_idx][w] == tag)) begin
        way_hit[w] = 1'b1;
        cache_hit = 1'b1;
        hit_way = w[1:0];
      end
    end
  end

  // LRU victim selection
  logic [1:0] victim_way;
  logic all_valid;

  assign all_valid = &valid_array[set_idx];

  always_comb begin
    victim_way = '0;
    // Find invalid way first
    for (int w = 0; w < NUM_WAYS; w++) begin
      if (!valid_array[set_idx][w]) begin
        victim_way = w[1:0];
      end
    end
    // If all valid, use LRU
    if (all_valid) begin
      logic [1:0] max_age;
      max_age = '0;
      for (int w = 0; w < NUM_WAYS; w++) begin
        if (lru_array[set_idx][w] >= max_age) begin
          max_age = lru_array[set_idx][w];
          victim_way = w[1:0];
        end
      end
    end
  end

  // Word selection from cache line
  logic [3:0] word_idx;
  assign word_idx = offset[OFFSET_BITS-1:2];

  // Read data extraction
  logic [INSTR_WIDTH-1:0] hit_instr;
  logic [CACHE_LINE_BITS-1:0] hit_line;

  assign hit_line = data_array[set_idx][hit_way];

  always_comb begin
    case (word_idx)
      4'd0:  hit_instr = hit_line[31:0];
      4'd1:  hit_instr = hit_line[63:32];
      4'd2:  hit_instr = hit_line[95:64];
      4'd3:  hit_instr = hit_line[127:96];
      4'd4:  hit_instr = hit_line[159:128];
      4'd5:  hit_instr = hit_line[191:160];
      4'd6:  hit_instr = hit_line[223:192];
      4'd7:  hit_instr = hit_line[255:224];
      4'd8:  hit_instr = hit_line[287:256];
      4'd9:  hit_instr = hit_line[319:288];
      4'd10: hit_instr = hit_line[351:320];
      4'd11: hit_instr = hit_line[383:352];
      4'd12: hit_instr = hit_line[415:384];
      4'd13: hit_instr = hit_line[447:416];
      4'd14: hit_instr = hit_line[479:448];
      4'd15: hit_instr = hit_line[511:480];
      default: hit_instr = '0;
    endcase
  end

  // Statistics
  logic [31:0] stat_hits, stat_misses;

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
        if (req_valid) next_state = TAG_CHECK;
      end
      TAG_CHECK: begin
        if (cache_hit) next_state = IDLE;  // Fast path - 1 cycle hit
        else if (l2_ready) next_state = FILL_WAIT;
      end
      FILL_WAIT: begin
        if (l2_resp_valid) next_state = UPDATE;
      end
      UPDATE: begin
        next_state = IDLE;
      end
      default: next_state = IDLE;
    endcase
  end

  // Register incoming request
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      req_addr_reg <= '0;
      set_idx <= '0;
      tag <= '0;
      offset <= '0;
    end else if (state == IDLE && req_valid) begin
      req_addr_reg <= req_addr;
      set_idx <= set_idx_in;
      tag <= tag_in;
      offset <= offset_in;
    end
  end

  // Cache array updates
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int s = 0; s < NUM_SETS; s++) begin
        valid_array[s] <= '0;
        for (int w = 0; w < NUM_WAYS; w++) begin
          tag_array[s][w] <= '0;
          data_array[s][w] <= '0;
          lru_array[s][w] <= w[1:0];
        end
      end
    end else begin
      // Handle invalidation
      if (invalidate_req) begin
        logic [SET_BITS-1:0] inv_set;
        logic [TAG_BITS-1:0] inv_tag;
        inv_set = invalidate_addr[OFFSET_BITS +: SET_BITS];
        inv_tag = invalidate_addr[ADDR_WIDTH-1 -: TAG_BITS];
        for (int w = 0; w < NUM_WAYS; w++) begin
          if (valid_array[inv_set][w] && tag_array[inv_set][w] == inv_tag) begin
            valid_array[inv_set][w] <= 1'b0;
          end
        end
      end

      case (state)
        TAG_CHECK: begin
          if (cache_hit) begin
            // Update LRU on hit
            for (int w = 0; w < NUM_WAYS; w++) begin
              if (w[1:0] == hit_way) begin
                lru_array[set_idx][w] <= '0;
              end else if (lru_array[set_idx][w] < lru_array[set_idx][hit_way]) begin
                lru_array[set_idx][w] <= lru_array[set_idx][w] + 1;
              end
            end
          end
        end

        UPDATE: begin
          // Fill from L2
          tag_array[set_idx][victim_way] <= tag;
          data_array[set_idx][victim_way] <= l2_resp_rdata;
          valid_array[set_idx][victim_way] <= 1'b1;

          // Update LRU
          for (int w = 0; w < NUM_WAYS; w++) begin
            if (w[1:0] == victim_way) begin
              lru_array[set_idx][w] <= '0;
            end else begin
              lru_array[set_idx][w] <= lru_array[set_idx][w] + 1;
            end
          end
        end
        default: ;
      endcase
    end
  end

  // L2 interface
  assign l2_req_valid = (state == TAG_CHECK) && !cache_hit;
  assign l2_req_addr = {req_addr_reg[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};

  // Response data extraction
  logic [CACHE_LINE_BITS-1:0] fill_line;
  logic [INSTR_WIDTH-1:0] fill_instr;

  assign fill_line = l2_resp_rdata;

  always_comb begin
    case (word_idx)
      4'd0:  fill_instr = fill_line[31:0];
      4'd1:  fill_instr = fill_line[63:32];
      4'd2:  fill_instr = fill_line[95:64];
      4'd3:  fill_instr = fill_line[127:96];
      4'd4:  fill_instr = fill_line[159:128];
      4'd5:  fill_instr = fill_line[191:160];
      4'd6:  fill_instr = fill_line[223:192];
      4'd7:  fill_instr = fill_line[255:224];
      4'd8:  fill_instr = fill_line[287:256];
      4'd9:  fill_instr = fill_line[319:288];
      4'd10: fill_instr = fill_line[351:320];
      4'd11: fill_instr = fill_line[383:352];
      4'd12: fill_instr = fill_line[415:384];
      4'd13: fill_instr = fill_line[447:416];
      4'd14: fill_instr = fill_line[479:448];
      4'd15: fill_instr = fill_line[511:480];
      default: fill_instr = '0;
    endcase
  end

  // Response signals
  assign resp_valid = (state == TAG_CHECK && cache_hit) || (state == UPDATE);
  assign resp_hit = (state == TAG_CHECK) && cache_hit;
  assign resp_instr = (state == TAG_CHECK && cache_hit) ? hit_instr : fill_instr;
  assign ready = (state == IDLE);
  assign invalidate_done = !invalidate_req;

  // Statistics
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stat_hits <= '0;
      stat_misses <= '0;
    end else begin
      if (state == TAG_CHECK && cache_hit) stat_hits <= stat_hits + 1;
      if (state == TAG_CHECK && !cache_hit) stat_misses <= stat_misses + 1;
    end
  end

  assign stats.hits = stat_hits;
  assign stats.misses = stat_misses;
  assign stats.writebacks = '0;  // I-cache has no writebacks
  assign stats.invalidations = '0;

endmodule
