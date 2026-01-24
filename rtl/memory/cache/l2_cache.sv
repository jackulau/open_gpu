// L2 Unified Cache - 512KB, 8-way set associative
// Shared by all L1 caches, write-back policy
// Compatible with Icarus Verilog

module l2_cache
  import pkg_opengpu::*;
#(
  parameter int CACHE_SIZE_KB = L2_SIZE_KB,   // 512 KB
  parameter int NUM_WAYS = L2_WAYS,           // 8-way
  parameter int LINE_BYTES = CACHE_LINE_BYTES,// 64 bytes
  parameter int NUM_PORTS = 4                 // Number of L1 requestors
)(
  input  logic                          clk,
  input  logic                          rst_n,

  // L1-side interface (multiple ports)
  input  logic [NUM_PORTS-1:0]                       l1_req_valid,
  input  logic [NUM_PORTS-1:0][2:0]                  l1_req_type,  // Raw bits for Icarus
  input  logic [NUM_PORTS-1:0][ADDR_WIDTH-1:0]       l1_req_addr,
  input  logic [NUM_PORTS-1:0][CACHE_LINE_BITS-1:0]  l1_req_wdata,

  output logic [NUM_PORTS-1:0]                       l1_resp_valid,
  output logic [NUM_PORTS-1:0][CACHE_LINE_BITS-1:0]  l1_resp_rdata,
  output logic [NUM_PORTS-1:0]                       l1_ready,

  // Memory-side interface
  output logic                          mem_req_valid,
  output logic                          mem_req_we,
  output logic [ADDR_WIDTH-1:0]         mem_req_addr,
  output logic [CACHE_LINE_BITS-1:0]    mem_req_wdata,

  input  logic                          mem_resp_valid,
  input  logic [CACHE_LINE_BITS-1:0]    mem_resp_rdata,
  input  logic                          mem_ready,

  // Flush control
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

  // Cache storage
  logic [TAG_BITS-1:0]          tag_array [0:NUM_SETS-1][0:NUM_WAYS-1];
  logic [CACHE_LINE_BITS-1:0]   data_array [0:NUM_SETS-1][0:NUM_WAYS-1];
  logic [NUM_WAYS-1:0]          valid_array [0:NUM_SETS-1];
  logic [NUM_WAYS-1:0]          dirty_array [0:NUM_SETS-1];

  // LRU state (3 bits per way for 8-way)
  logic [2:0] lru_array [0:NUM_SETS-1][0:NUM_WAYS-1];

  // Arbiter - round-robin selection
  logic [$clog2(NUM_PORTS)-1:0] arb_select;
  logic [NUM_PORTS-1:0]         arb_grant;
  logic                         arb_valid;

  // Selected request
  logic                         sel_valid;
  logic [2:0]                   sel_type;
  logic [ADDR_WIDTH-1:0]        sel_addr;
  logic [CACHE_LINE_BITS-1:0]   sel_wdata;
  logic [$clog2(NUM_PORTS)-1:0] sel_port;

  // State machine
  typedef enum logic [2:0] {
    IDLE,
    TAG_CHECK,
    WRITEBACK,
    FILL_REQ,
    FILL_WAIT,
    UPDATE,
    RESPOND
  } l2_state_t;

  l2_state_t state, next_state;

  // Round-robin arbiter
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      arb_select <= '0;
    end else if (arb_valid && (state == IDLE)) begin
      arb_select <= arb_select + 1;
    end
  end

  always_comb begin
    arb_grant = '0;
    arb_valid = 1'b0;
    sel_valid = 1'b0;
    sel_type = 3'd0;
    sel_addr = '0;
    sel_wdata = '0;
    sel_port = '0;

    // Check ports in round-robin order
    for (int i = 0; i < NUM_PORTS; i++) begin
      int idx;
      idx = (arb_select + i) % NUM_PORTS;
      if (l1_req_valid[idx] && !arb_valid) begin
        arb_grant[idx] = 1'b1;
        arb_valid = 1'b1;
        sel_valid = 1'b1;
        sel_type = l1_req_type[idx];
        sel_addr = l1_req_addr[idx];
        sel_wdata = l1_req_wdata[idx];
        sel_port = idx[$clog2(NUM_PORTS)-1:0];
      end
    end
  end

  // Address field extraction
  logic [OFFSET_BITS-1:0] offset;
  logic [SET_BITS-1:0]    set_idx;
  logic [TAG_BITS-1:0]    tag;

  assign offset = sel_addr[OFFSET_BITS-1:0];
  assign set_idx = sel_addr[OFFSET_BITS +: SET_BITS];
  assign tag = sel_addr[ADDR_WIDTH-1 -: TAG_BITS];

  // Registered request
  logic [2:0]                   req_type_reg;
  logic [ADDR_WIDTH-1:0]        req_addr_reg;
  logic [CACHE_LINE_BITS-1:0]   req_wdata_reg;
  logic [$clog2(NUM_PORTS)-1:0] req_port_reg;
  logic [SET_BITS-1:0]          req_set_idx;
  logic [TAG_BITS-1:0]          req_tag;

  // Hit detection
  logic [NUM_WAYS-1:0] way_hit;
  logic cache_hit;
  logic [2:0] hit_way;

  always_comb begin
    way_hit = '0;
    cache_hit = 1'b0;
    hit_way = '0;

    for (int w = 0; w < NUM_WAYS; w++) begin
      if (valid_array[req_set_idx][w] && (tag_array[req_set_idx][w] == req_tag)) begin
        way_hit[w] = 1'b1;
        cache_hit = 1'b1;
        hit_way = w[2:0];
      end
    end
  end

  // Victim selection
  logic [2:0] victim_way;
  logic victim_dirty;
  logic all_valid;

  assign all_valid = &valid_array[req_set_idx];

  always_comb begin
    victim_way = '0;
    for (int w = 0; w < NUM_WAYS; w++) begin
      if (!valid_array[req_set_idx][w]) begin
        victim_way = w[2:0];
      end
    end
    if (all_valid) begin
      logic [2:0] max_age;
      max_age = '0;
      for (int w = 0; w < NUM_WAYS; w++) begin
        if (lru_array[req_set_idx][w] >= max_age) begin
          max_age = lru_array[req_set_idx][w];
          victim_way = w[2:0];
        end
      end
    end
    victim_dirty = valid_array[req_set_idx][victim_way] &&
                   dirty_array[req_set_idx][victim_way];
  end

  // Response data
  logic [CACHE_LINE_BITS-1:0] resp_data;

  // Statistics
  logic [31:0] stat_hits, stat_misses, stat_writebacks;

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
        if (sel_valid) next_state = TAG_CHECK;
      end
      TAG_CHECK: begin
        if (req_type_reg == 3'd2) begin  // CACHE_WRITEBACK
          // Direct writeback from L1
          next_state = UPDATE;
        end else if (cache_hit) begin
          next_state = RESPOND;
        end else if (victim_dirty) begin
          next_state = WRITEBACK;
        end else begin
          next_state = FILL_REQ;
        end
      end
      WRITEBACK: begin
        if (mem_ready) next_state = FILL_REQ;
      end
      FILL_REQ: begin
        if (mem_ready) next_state = FILL_WAIT;
      end
      FILL_WAIT: begin
        if (mem_resp_valid) next_state = UPDATE;
      end
      UPDATE: begin
        next_state = RESPOND;
      end
      RESPOND: begin
        next_state = IDLE;
      end
      default: next_state = IDLE;
    endcase
  end

  // Register incoming request
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      req_type_reg <= 3'd0;
      req_addr_reg <= '0;
      req_wdata_reg <= '0;
      req_port_reg <= '0;
      req_set_idx <= '0;
      req_tag <= '0;
    end else if (state == IDLE && sel_valid) begin
      req_type_reg <= sel_type;
      req_addr_reg <= sel_addr;
      req_wdata_reg <= sel_wdata;
      req_port_reg <= sel_port;
      req_set_idx <= set_idx;
      req_tag <= tag;
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
          lru_array[s][w] <= w[2:0];
        end
      end
    end else begin
      case (state)
        TAG_CHECK: begin
          if (cache_hit) begin
            // Update LRU
            for (int w = 0; w < NUM_WAYS; w++) begin
              if (w[2:0] == hit_way) begin
                lru_array[req_set_idx][w] <= '0;
              end else if (lru_array[req_set_idx][w] < lru_array[req_set_idx][hit_way]) begin
                lru_array[req_set_idx][w] <= lru_array[req_set_idx][w] + 1;
              end
            end
          end
        end

        UPDATE: begin
          if (req_type_reg == 3'd2) begin  // CACHE_WRITEBACK
            // Write-back from L1
            if (cache_hit) begin
              data_array[req_set_idx][hit_way] <= req_wdata_reg;
              dirty_array[req_set_idx][hit_way] <= 1'b1;
            end else begin
              tag_array[req_set_idx][victim_way] <= req_tag;
              data_array[req_set_idx][victim_way] <= req_wdata_reg;
              valid_array[req_set_idx][victim_way] <= 1'b1;
              dirty_array[req_set_idx][victim_way] <= 1'b1;
            end
          end else begin
            // Fill from memory
            tag_array[req_set_idx][victim_way] <= req_tag;
            data_array[req_set_idx][victim_way] <= mem_resp_rdata;
            valid_array[req_set_idx][victim_way] <= 1'b1;
            dirty_array[req_set_idx][victim_way] <= 1'b0;

            // Update LRU
            for (int w = 0; w < NUM_WAYS; w++) begin
              if (w[2:0] == victim_way) begin
                lru_array[req_set_idx][w] <= '0;
              end else begin
                lru_array[req_set_idx][w] <= lru_array[req_set_idx][w] + 1;
              end
            end
          end
        end
        default: ;
      endcase
    end
  end

  // Response data selection
  always_comb begin
    if (cache_hit) begin
      resp_data = data_array[req_set_idx][hit_way];
    end else begin
      resp_data = mem_resp_rdata;
    end
  end

  // Memory interface
  assign mem_req_valid = (state == WRITEBACK) || (state == FILL_REQ);
  assign mem_req_we = (state == WRITEBACK);
  assign mem_req_addr = (state == WRITEBACK) ?
                        {tag_array[req_set_idx][victim_way], req_set_idx, {OFFSET_BITS{1'b0}}} :
                        {req_addr_reg[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
  assign mem_req_wdata = data_array[req_set_idx][victim_way];

  // L1 interface
  always_comb begin
    l1_resp_valid = '0;
    l1_resp_rdata = '0;
    l1_ready = '0;

    // Ready signals - always ready when idle
    for (int i = 0; i < NUM_PORTS; i++) begin
      l1_ready[i] = (state == IDLE);
    end

    // Response to requesting port
    if (state == RESPOND) begin
      l1_resp_valid[req_port_reg] = 1'b1;
      l1_resp_rdata[req_port_reg] = resp_data;
    end
  end

  assign flush_done = (state == IDLE) && !flush_req;

  // Statistics
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stat_hits <= '0;
      stat_misses <= '0;
      stat_writebacks <= '0;
    end else begin
      if (state == TAG_CHECK && cache_hit && req_type_reg != 3'd2)
        stat_hits <= stat_hits + 1;
      if (state == TAG_CHECK && !cache_hit && req_type_reg != 3'd2)
        stat_misses <= stat_misses + 1;
      if (state == WRITEBACK && mem_ready)
        stat_writebacks <= stat_writebacks + 1;
    end
  end

  assign stats.hits = stat_hits;
  assign stats.misses = stat_misses;
  assign stats.writebacks = stat_writebacks;
  assign stats.invalidations = '0;

endmodule
