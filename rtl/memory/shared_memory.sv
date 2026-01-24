// Shared Memory - 48KB per SM with 32 banks
// Bank conflict detection and multi-cycle access for conflicts
// Simplified for Icarus Verilog compatibility

module shared_memory
  import pkg_opengpu::*;
#(
  parameter int SIZE_KB = SMEM_SIZE_KB,       // 48 KB
  parameter int NUM_BANKS = SMEM_BANKS,       // 32 banks
  parameter int BANK_WIDTH = SMEM_BANK_WIDTH  // 32-bit banks
)(
  input  logic                          clk,
  input  logic                          rst_n,

  // Multi-lane request interface (from SIMT lanes)
  input  logic [WARP_SIZE-1:0]          req_valid,
  input  logic [WARP_SIZE-1:0]          req_we,
  input  logic [WARP_SIZE-1:0][15:0]    req_addr,    // 16-bit address (48KB)
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] req_wdata,
  input  logic [WARP_SIZE-1:0]          req_mask,    // Active lanes

  output logic [WARP_SIZE-1:0]          resp_valid,
  output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] resp_rdata,
  output logic                          ready,
  output logic                          conflict_detected,
  output logic [WARP_SIZE-1:0]          conflict_lanes
);

  // Bank parameters
  localparam int BANK_SIZE = (SIZE_KB * 1024) / NUM_BANKS;  // Bytes per bank
  localparam int BANK_DEPTH = BANK_SIZE / 4;                 // Words per bank
  localparam int BANK_ADDR_BITS = $clog2(BANK_DEPTH);
  localparam int TOTAL_WORDS = (SIZE_KB * 1024) / 4;

  // Flat memory storage for Icarus compatibility
  logic [DATA_WIDTH-1:0] mem [0:TOTAL_WORDS-1];

  // Per-lane address breakdown (computed outside always_comb for Icarus)
  wire [WARP_SIZE-1:0][4:0] lane_bank;
  wire [WARP_SIZE-1:0][BANK_ADDR_BITS-1:0] lane_bank_addr;
  wire [WARP_SIZE-1:0][15:0] lane_word_addr;

  // Generate bank/address for each lane
  genvar gi;
  generate
    for (gi = 0; gi < WARP_SIZE; gi++) begin : gen_addr
      assign lane_bank[gi] = req_addr[gi][6:2];  // Bits 6:2 select bank (32 banks)
      assign lane_bank_addr[gi] = req_addr[gi][15:7];  // Upper bits select word within bank
      assign lane_word_addr[gi] = req_addr[gi][15:2];  // Word address for flat memory
    end
  endgenerate

  // Conflict detection - simplified approach
  // Check each pair of active lanes for bank conflicts
  logic [WARP_SIZE-1:0] active_lanes;
  assign active_lanes = req_valid & req_mask;

  // Conflict: two lanes access same bank with different addresses
  // Simplified: just check if any two active lanes have same bank but different addr
  logic any_conflict;
  logic [WARP_SIZE-1:0] lane_conflicts;

  // Compute conflicts using generate blocks
  wire [WARP_SIZE-1:0] lane_has_earlier_conflict;

  generate
    for (gi = 0; gi < WARP_SIZE; gi++) begin : gen_conflict
      // Check if any earlier lane has same bank but different address
      logic conflict_with_earlier;
      integer j;
      always_comb begin
        conflict_with_earlier = 1'b0;
        for (j = 0; j < gi; j++) begin
          if (active_lanes[j] && active_lanes[gi] &&
              lane_bank[j] == lane_bank[gi] &&
              lane_bank_addr[j] != lane_bank_addr[gi]) begin
            conflict_with_earlier = 1'b1;
          end
        end
      end
      assign lane_has_earlier_conflict[gi] = conflict_with_earlier;
    end
  endgenerate

  always_comb begin
    any_conflict = 1'b0;
    lane_conflicts = '0;
    for (int i = 0; i < WARP_SIZE; i++) begin
      if (lane_has_earlier_conflict[i]) begin
        any_conflict = 1'b1;
        lane_conflicts[i] = 1'b1;
        // Mark the earlier conflicting lane too
        for (int j = 0; j < i; j++) begin
          if (active_lanes[j] && lane_bank[j] == lane_bank[i] &&
              lane_bank_addr[j] != lane_bank_addr[i]) begin
            lane_conflicts[j] = 1'b1;
          end
        end
      end
    end
  end

  assign conflict_detected = any_conflict;
  assign conflict_lanes = lane_conflicts;

  // State machine for handling conflicts
  typedef enum logic [2:0] {
    IDLE,
    PROCESS,
    CONFLICT_RESOLVE,
    DONE
  } smem_state_t;

  smem_state_t state, next_state;

  // Conflict resolution - track which lanes are processed
  logic [WARP_SIZE-1:0] pending_lanes;
  logic [WARP_SIZE-1:0] processed_lanes;

  // Compute which lanes can be processed this cycle (no bank conflicts among them)
  logic [WARP_SIZE-1:0] current_batch;
  logic [NUM_BANKS-1:0] batch_bank_used;

  generate
    for (gi = 0; gi < WARP_SIZE; gi++) begin : gen_batch
      // Lane can be in batch if it's pending and no earlier pending lane uses same bank
      logic earlier_uses_bank;
      integer k;
      always_comb begin
        earlier_uses_bank = 1'b0;
        for (k = 0; k < gi; k++) begin
          if (pending_lanes[k] && !processed_lanes[k] && lane_bank[k] == lane_bank[gi]) begin
            earlier_uses_bank = 1'b1;
          end
        end
      end
      assign current_batch[gi] = pending_lanes[gi] && !processed_lanes[gi] && !earlier_uses_bank;
    end
  endgenerate

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
        if (|req_valid) begin
          if (any_conflict) begin
            next_state = CONFLICT_RESOLVE;
          end else begin
            next_state = PROCESS;
          end
        end
      end
      PROCESS: begin
        next_state = DONE;
      end
      CONFLICT_RESOLVE: begin
        // Done when all pending lanes are processed
        if ((pending_lanes & ~processed_lanes & ~current_batch) == '0) begin
          next_state = DONE;
        end
      end
      DONE: begin
        next_state = IDLE;
      end
      default: next_state = IDLE;
    endcase
  end

  // Track pending and processed lanes
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pending_lanes <= '0;
      processed_lanes <= '0;
    end else begin
      case (state)
        IDLE: begin
          if (|req_valid) begin
            pending_lanes <= req_valid & req_mask;
            processed_lanes <= '0;
          end
        end
        PROCESS: begin
          processed_lanes <= pending_lanes;
        end
        CONFLICT_RESOLVE: begin
          processed_lanes <= processed_lanes | current_batch;
        end
        DONE: begin
          pending_lanes <= '0;
          processed_lanes <= '0;
        end
        default: ;
      endcase
    end
  end

  // Read data register
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] read_data_reg;

  // Memory read/write - using generate for Icarus compatibility
  generate
    for (gi = 0; gi < WARP_SIZE; gi++) begin : gen_mem_access
      always_ff @(posedge clk) begin
        case (state)
          PROCESS: begin
            if (pending_lanes[gi]) begin
              if (req_we[gi]) begin
                mem[lane_word_addr[gi]] <= req_wdata[gi];
              end
              read_data_reg[gi] <= mem[lane_word_addr[gi]];
            end
          end
          CONFLICT_RESOLVE: begin
            if (current_batch[gi]) begin
              if (req_we[gi]) begin
                mem[lane_word_addr[gi]] <= req_wdata[gi];
              end
              read_data_reg[gi] <= mem[lane_word_addr[gi]];
            end
          end
          default: ;
        endcase
      end
    end
  endgenerate

  // Output signals
  assign ready = (state == IDLE);
  assign resp_valid = (state == DONE) ? processed_lanes : '0;
  assign resp_rdata = read_data_reg;

endmodule
