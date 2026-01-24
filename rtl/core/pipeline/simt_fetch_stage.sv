// SIMT Fetch Stage - Multi-warp instruction fetch
// Fetches instructions for selected warp from scheduler

module simt_fetch_stage
  import pkg_opengpu::*;
(
  input  logic                          clk,
  input  logic                          rst_n,

  // Control
  input  logic                          enable,
  input  logic                          stall,
  input  logic                          flush,

  // From warp scheduler
  input  logic                          warp_valid,
  input  logic [WARP_ID_WIDTH-1:0]      warp_id,
  input  logic [DATA_WIDTH-1:0]         warp_pc,
  input  logic [WARP_SIZE-1:0]          warp_mask,

  // Scheduler acknowledge
  output logic                          issue_ack,

  // Instruction memory interface
  output logic                          imem_req,
  output logic [ADDR_WIDTH-1:0]         imem_addr,
  input  logic [INSTR_WIDTH-1:0]        imem_rdata,
  input  logic                          imem_valid,

  // To decode stage
  output logic [INSTR_WIDTH-1:0]        instr,
  output logic [ADDR_WIDTH-1:0]         pc,
  output logic [WARP_ID_WIDTH-1:0]      out_warp_id,
  output logic [WARP_SIZE-1:0]          out_mask,
  output logic                          valid
);

  // Fetch state
  typedef enum logic [1:0] {
    FETCH_IDLE,
    FETCH_REQ,
    FETCH_WAIT,
    FETCH_DONE
  } fetch_state_t;

  fetch_state_t state, next_state;

  // Registered warp info
  logic [WARP_ID_WIDTH-1:0] warp_id_reg;
  logic [DATA_WIDTH-1:0] pc_reg;
  logic [WARP_SIZE-1:0] mask_reg;

  // State machine
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= FETCH_IDLE;
    end else if (flush) begin
      state <= FETCH_IDLE;
    end else begin
      state <= next_state;
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      FETCH_IDLE: begin
        if (enable && warp_valid && !stall) begin
          next_state = FETCH_REQ;
        end
      end
      FETCH_REQ: begin
        next_state = FETCH_WAIT;
      end
      FETCH_WAIT: begin
        if (imem_valid) begin
          next_state = FETCH_DONE;
        end
      end
      FETCH_DONE: begin
        if (!stall) begin
          next_state = FETCH_IDLE;
        end
      end
      default: next_state = FETCH_IDLE;
    endcase
  end

  // Register warp info on fetch start
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      warp_id_reg <= '0;
      pc_reg <= '0;
      mask_reg <= '0;
    end else if (state == FETCH_IDLE && enable && warp_valid && !stall) begin
      warp_id_reg <= warp_id;
      pc_reg <= warp_pc;
      mask_reg <= warp_mask;
    end
  end

  // Memory interface
  assign imem_req = (state == FETCH_REQ);
  assign imem_addr = pc_reg;

  // Issue acknowledge
  assign issue_ack = (state == FETCH_IDLE) && enable && warp_valid && !stall;

  // Output to decode
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr <= INSTR_NOP;
      pc <= '0;
      out_warp_id <= '0;
      out_mask <= '0;
      valid <= 1'b0;
    end else if (flush) begin
      instr <= INSTR_NOP;
      valid <= 1'b0;
    end else if (state == FETCH_DONE && !stall) begin
      instr <= imem_rdata;
      pc <= pc_reg;
      out_warp_id <= warp_id_reg;
      out_mask <= mask_reg;
      valid <= 1'b1;
    end else if (!stall && state == FETCH_IDLE) begin
      valid <= 1'b0;
    end
  end

endmodule
