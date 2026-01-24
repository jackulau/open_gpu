// L1 Data Cache - 32KB, 4-way set associative
// Write-back with write-allocate policy, LRU replacement
// Compatible with Icarus Verilog

module l1_data_cache
  import pkg_opengpu::*;
#(
  parameter int CACHE_SIZE_KB = L1D_SIZE_KB,  // 32 KB
  parameter int NUM_WAYS = L1_WAYS,           // 4-way
  parameter int LINE_BYTES = CACHE_LINE_BYTES // 64 bytes
)(
  input  logic                          clk,
  input  logic                          rst_n,

  // CPU-side interface (from memory stage)
  input  logic                          req_valid,
  input  logic                          req_we,
  input  logic [ADDR_WIDTH-1:0]         req_addr,
  input  logic [DATA_WIDTH-1:0]         req_wdata,
  input  logic [3:0]                    req_byte_en,
  input  mem_size_t                     req_size,

  output logic                          resp_valid,
  output logic                          resp_hit,
  output logic [DATA_WIDTH-1:0]         resp_rdata,
  output logic                          ready,

  // L2/Memory-side interface
  output logic                          l2_req_valid,
  output logic [2:0]                    l2_req_type,  // Use raw bits for Icarus
  output logic [ADDR_WIDTH-1:0]         l2_req_addr,
  output logic [CACHE_LINE_BITS-1:0]    l2_req_wdata,

  input  logic                          l2_resp_valid,
  input  logic [CACHE_LINE_BITS-1:0]    l2_resp_rdata,
  input  logic                          l2_ready,

  // Flush/invalidate control
  input  logic                          flush_req,
  output logic                          flush_done,

  // Statistics
  output cache_stats_t                  stats
);

  // Cache parameters
  localparam int NUM_SETS = (CACHE_SIZE_KB * 1024) / (LINE_BYTES * NUM_WAYS);
  localparam int SET_BITS = $clog2(NUM_SETS);
  localparam int OFFSET_BITS = $clog2(LINE_BYTES);
  localparam int TAG_BITS = ADDR_WIDTH - SET_BITS - OFFSET_BITS;
  localparam int WORDS_PER_LINE = LINE_BYTES / 4;

  // Cache storage - use fixed sizes for Icarus compatibility
  logic [TAG_BITS-1:0]          tag_array [0:NUM_SETS-1][0:NUM_WAYS-1];
  logic [CACHE_LINE_BITS-1:0]   data_array [0:NUM_SETS-1][0:NUM_WAYS-1];
  logic [NUM_WAYS-1:0]          valid_array [0:NUM_SETS-1];
  logic [NUM_WAYS-1:0]          dirty_array [0:NUM_SETS-1];

  // LRU state (2 bits per way for 4-way)
  logic [1:0] lru_array [0:NUM_SETS-1][0:NUM_WAYS-1];

  // Address field extraction (registered)
  logic [OFFSET_BITS-1:0] offset_in;
  logic [SET_BITS-1:0]    set_idx_in;
  logic [TAG_BITS-1:0]    tag_in;

  assign offset_in = req_addr[OFFSET_BITS-1:0];
  assign set_idx_in = req_addr[OFFSET_BITS +: SET_BITS];
  assign tag_in = req_addr[ADDR_WIDTH-1 -: TAG_BITS];

  // State machine
  typedef enum logic [2:0] {
    IDLE,
    TAG_CHECK,
    WRITEBACK,
    FILL_REQ,
    FILL_WAIT,
    UPDATE,
    FLUSH_SCAN
  } cache_state_t;

  cache_state_t state, next_state;

  // Registered request
  logic                   req_we_reg;
  logic [ADDR_WIDTH-1:0]  req_addr_reg;
  logic [DATA_WIDTH-1:0]  req_wdata_reg;
  logic [3:0]             req_byte_en_reg;
  logic [SET_BITS-1:0]    set_idx;
  logic [TAG_BITS-1:0]    tag;
  logic [OFFSET_BITS-1:0] offset;

  // Hit detection signals
  logic [NUM_WAYS-1:0] way_hit;
  logic cache_hit;
  logic [1:0] hit_way;

  // Victim selection
  logic [1:0] victim_way;
  logic victim_dirty;
  logic all_valid;

  // Flush control
  logic [SET_BITS-1:0] flush_set;
  logic [1:0] flush_way;

  // Statistics counters
  logic [31:0] stat_hits, stat_misses, stat_writebacks;

  // Word index for data extraction
  logic [3:0] word_idx;
  assign word_idx = offset[OFFSET_BITS-1:2];

  // Hit detection (combinational)
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

  // Check if all ways are valid
  assign all_valid = &valid_array[set_idx];

  // Victim selection (combinational) - find invalid or LRU
  always_comb begin
    victim_way = '0;
    victim_dirty = 1'b0;

    // First, check for invalid way
    for (int w = 0; w < NUM_WAYS; w++) begin
      if (!valid_array[set_idx][w]) begin
        victim_way = w[1:0];
      end
    end

    // If all valid, find LRU (way with highest age)
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

    victim_dirty = valid_array[set_idx][victim_way] && dirty_array[set_idx][victim_way];
  end

  // Read data extraction
  logic [DATA_WIDTH-1:0] hit_data;
  logic [CACHE_LINE_BITS-1:0] hit_line;

  assign hit_line = data_array[set_idx][hit_way];

  always_comb begin
    case (word_idx)
      4'd0:  hit_data = hit_line[31:0];
      4'd1:  hit_data = hit_line[63:32];
      4'd2:  hit_data = hit_line[95:64];
      4'd3:  hit_data = hit_line[127:96];
      4'd4:  hit_data = hit_line[159:128];
      4'd5:  hit_data = hit_line[191:160];
      4'd6:  hit_data = hit_line[223:192];
      4'd7:  hit_data = hit_line[255:224];
      4'd8:  hit_data = hit_line[287:256];
      4'd9:  hit_data = hit_line[319:288];
      4'd10: hit_data = hit_line[351:320];
      4'd11: hit_data = hit_line[383:352];
      4'd12: hit_data = hit_line[415:384];
      4'd13: hit_data = hit_line[447:416];
      4'd14: hit_data = hit_line[479:448];
      4'd15: hit_data = hit_line[511:480];
      default: hit_data = '0;
    endcase
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
        if (flush_req) next_state = FLUSH_SCAN;
        else if (req_valid) next_state = TAG_CHECK;
      end
      TAG_CHECK: begin
        if (cache_hit) next_state = UPDATE;
        else if (victim_dirty) next_state = WRITEBACK;
        else next_state = FILL_REQ;
      end
      WRITEBACK: begin
        if (l2_ready) next_state = FILL_REQ;
      end
      FILL_REQ: begin
        if (l2_ready) next_state = FILL_WAIT;
      end
      FILL_WAIT: begin
        if (l2_resp_valid) next_state = UPDATE;
      end
      UPDATE: begin
        next_state = IDLE;
      end
      FLUSH_SCAN: begin
        if (flush_set == NUM_SETS[SET_BITS-1:0]-1 && flush_way == NUM_WAYS[1:0]-1) begin
          next_state = IDLE;
        end
      end
      default: next_state = IDLE;
    endcase
  end

  // Register incoming request
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      req_we_reg <= 1'b0;
      req_addr_reg <= '0;
      req_wdata_reg <= '0;
      req_byte_en_reg <= '0;
      set_idx <= '0;
      tag <= '0;
      offset <= '0;
    end else if (state == IDLE && req_valid) begin
      req_we_reg <= req_we;
      req_addr_reg <= req_addr;
      req_wdata_reg <= req_wdata;
      req_byte_en_reg <= req_byte_en;
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
        dirty_array[s] <= '0;
        for (int w = 0; w < NUM_WAYS; w++) begin
          tag_array[s][w] <= '0;
          data_array[s][w] <= '0;
          lru_array[s][w] <= w[1:0];
        end
      end
    end else begin
      case (state)
        TAG_CHECK: begin
          if (cache_hit) begin
            // Update LRU on hit
            for (int w = 0; w < NUM_WAYS; w++) begin
              if (w[1:0] == hit_way) begin
                lru_array[set_idx][w] <= '0;  // Most recently used
              end else if (lru_array[set_idx][w] < lru_array[set_idx][hit_way]) begin
                lru_array[set_idx][w] <= lru_array[set_idx][w] + 1;
              end
            end
          end
        end

        UPDATE: begin
          if (cache_hit && req_we_reg) begin
            // Write hit - update data with byte enables
            if (req_byte_en_reg[0]) data_array[set_idx][hit_way][word_idx*32 +: 8] <= req_wdata_reg[7:0];
            if (req_byte_en_reg[1]) data_array[set_idx][hit_way][word_idx*32+8 +: 8] <= req_wdata_reg[15:8];
            if (req_byte_en_reg[2]) data_array[set_idx][hit_way][word_idx*32+16 +: 8] <= req_wdata_reg[23:16];
            if (req_byte_en_reg[3]) data_array[set_idx][hit_way][word_idx*32+24 +: 8] <= req_wdata_reg[31:24];
            dirty_array[set_idx][hit_way] <= 1'b1;
          end else if (!cache_hit) begin
            // Fill from L2
            tag_array[set_idx][victim_way] <= tag;
            data_array[set_idx][victim_way] <= l2_resp_rdata;
            valid_array[set_idx][victim_way] <= 1'b1;
            dirty_array[set_idx][victim_way] <= req_we_reg;

            // Write new data if store
            if (req_we_reg) begin
              if (req_byte_en_reg[0]) data_array[set_idx][victim_way][word_idx*32 +: 8] <= req_wdata_reg[7:0];
              if (req_byte_en_reg[1]) data_array[set_idx][victim_way][word_idx*32+8 +: 8] <= req_wdata_reg[15:8];
              if (req_byte_en_reg[2]) data_array[set_idx][victim_way][word_idx*32+16 +: 8] <= req_wdata_reg[23:16];
              if (req_byte_en_reg[3]) data_array[set_idx][victim_way][word_idx*32+24 +: 8] <= req_wdata_reg[31:24];
            end

            // Update LRU
            for (int w = 0; w < NUM_WAYS; w++) begin
              if (w[1:0] == victim_way) begin
                lru_array[set_idx][w] <= '0;
              end else begin
                lru_array[set_idx][w] <= lru_array[set_idx][w] + 1;
              end
            end
          end
        end

        FLUSH_SCAN: begin
          if (dirty_array[flush_set][flush_way]) begin
            // Clear dirty bit after writeback
            dirty_array[flush_set][flush_way] <= 1'b0;
          end
        end
        default: ;
      endcase
    end
  end

  // Flush counter
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      flush_set <= '0;
      flush_way <= '0;
    end else if (state == FLUSH_SCAN) begin
      if (flush_way == NUM_WAYS[1:0]-1) begin
        flush_way <= '0;
        flush_set <= flush_set + 1;
      end else begin
        flush_way <= flush_way + 1;
      end
    end else begin
      flush_set <= '0;
      flush_way <= '0;
    end
  end

  // L2 interface
  assign l2_req_valid = (state == WRITEBACK) || (state == FILL_REQ);
  assign l2_req_type = (state == WRITEBACK) ? 3'd2 : 3'd0;  // CACHE_WRITEBACK=2, CACHE_READ=0
  assign l2_req_addr = (state == WRITEBACK) ?
                       {tag_array[set_idx][victim_way], set_idx, {OFFSET_BITS{1'b0}}} :
                       {req_addr_reg[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
  assign l2_req_wdata = data_array[set_idx][victim_way];

  // Response signals
  assign resp_valid = (state == UPDATE);
  assign resp_hit = cache_hit;

  // Response data extraction
  logic [CACHE_LINE_BITS-1:0] fill_line;
  logic [DATA_WIDTH-1:0] fill_word;

  assign fill_line = l2_resp_rdata;

  always_comb begin
    case (word_idx)
      4'd0:  fill_word = fill_line[31:0];
      4'd1:  fill_word = fill_line[63:32];
      4'd2:  fill_word = fill_line[95:64];
      4'd3:  fill_word = fill_line[127:96];
      4'd4:  fill_word = fill_line[159:128];
      4'd5:  fill_word = fill_line[191:160];
      4'd6:  fill_word = fill_line[223:192];
      4'd7:  fill_word = fill_line[255:224];
      4'd8:  fill_word = fill_line[287:256];
      4'd9:  fill_word = fill_line[319:288];
      4'd10: fill_word = fill_line[351:320];
      4'd11: fill_word = fill_line[383:352];
      4'd12: fill_word = fill_line[415:384];
      4'd13: fill_word = fill_line[447:416];
      4'd14: fill_word = fill_line[479:448];
      4'd15: fill_word = fill_line[511:480];
      default: fill_word = '0;
    endcase
  end

  assign resp_rdata = cache_hit ? hit_data : fill_word;
  assign ready = (state == IDLE);
  assign flush_done = (state == IDLE) && !flush_req;

  // Statistics
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stat_hits <= '0;
      stat_misses <= '0;
      stat_writebacks <= '0;
    end else begin
      if (state == TAG_CHECK && cache_hit) stat_hits <= stat_hits + 1;
      if (state == TAG_CHECK && !cache_hit) stat_misses <= stat_misses + 1;
      if (state == WRITEBACK && l2_ready) stat_writebacks <= stat_writebacks + 1;
    end
  end

  assign stats.hits = stat_hits;
  assign stats.misses = stat_misses;
  assign stats.writebacks = stat_writebacks;
  assign stats.invalidations = '0;

endmodule
