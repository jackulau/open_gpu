// Warp Context - Per-warp state management
// Manages PC, active mask, status, and age for each warp

module warp_context
  import pkg_opengpu::*;
#(
  parameter int NUM_WARPS = WARPS_PER_CORE
)(
  input  logic                          clk,
  input  logic                          rst_n,

  // Warp initialization
  input  logic [WARP_ID_WIDTH-1:0]      init_warp_id,
  input  logic                          init_valid,
  input  logic [DATA_WIDTH-1:0]         init_pc,
  input  logic [WARP_SIZE-1:0]          init_mask,

  // PC update interface
  input  logic [WARP_ID_WIDTH-1:0]      pc_warp_id,
  input  logic                          pc_update,
  input  logic [DATA_WIDTH-1:0]         new_pc,

  // Mask update interface
  input  logic [WARP_ID_WIDTH-1:0]      mask_warp_id,
  input  logic                          mask_update,
  input  logic [WARP_SIZE-1:0]          new_mask,

  // Status update interface
  input  logic [WARP_ID_WIDTH-1:0]      status_warp_id,
  input  logic                          status_update,
  input  warp_status_t                  new_status,

  // Age update (from scheduler)
  input  logic [WARP_ID_WIDTH-1:0]      issued_warp_id,
  input  logic                          warp_issued,

  // Read interface - all warp contexts
  output warp_context_t                 contexts [NUM_WARPS],

  // Single warp read interface
  input  logic [WARP_ID_WIDTH-1:0]      read_warp_id,
  output warp_context_t                 read_context
);

  // Internal storage
  warp_context_t warp_state [NUM_WARPS];

  // Output all contexts
  always_comb begin
    for (int i = 0; i < NUM_WARPS; i++) begin
      contexts[i] = warp_state[i];
    end
  end

  // Single warp read
  assign read_context = warp_state[read_warp_id];

  // State updates
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < NUM_WARPS; i++) begin
        warp_state[i].pc <= '0;
        warp_state[i].active_mask <= '0;
        warp_state[i].status <= WARP_IDLE;
        warp_state[i].age <= '0;
        warp_state[i].valid <= 1'b0;
      end
    end else begin
      // Warp initialization
      if (init_valid) begin
        warp_state[init_warp_id].pc <= init_pc;
        warp_state[init_warp_id].active_mask <= init_mask;
        warp_state[init_warp_id].status <= WARP_READY;
        warp_state[init_warp_id].age <= '0;
        warp_state[init_warp_id].valid <= 1'b1;
      end

      // PC update
      if (pc_update) begin
        warp_state[pc_warp_id].pc <= new_pc;
      end

      // Mask update
      if (mask_update) begin
        warp_state[mask_warp_id].active_mask <= new_mask;
        // If mask becomes zero, mark warp as done
        if (new_mask == '0) begin
          warp_state[mask_warp_id].status <= WARP_DONE;
        end
      end

      // Status update
      if (status_update) begin
        warp_state[status_warp_id].status <= new_status;
      end

      // Age management (GTO scheduling support)
      if (warp_issued) begin
        // Reset age of issued warp to 0
        warp_state[issued_warp_id].age <= '0;
        // Increment age of all other valid, ready warps
        for (int i = 0; i < NUM_WARPS; i++) begin
          if (i[WARP_ID_WIDTH-1:0] != issued_warp_id &&
              warp_state[i].valid &&
              warp_state[i].status == WARP_READY &&
              warp_state[i].age < 8'hFF) begin
            warp_state[i].age <= warp_state[i].age + 1;
          end
        end
      end
    end
  end

  // Count active warps
  function automatic logic [WARP_ID_WIDTH:0] count_active_warps();
    logic [WARP_ID_WIDTH:0] count;
    count = '0;
    for (int i = 0; i < NUM_WARPS; i++) begin
      if (warp_state[i].valid && warp_state[i].status != WARP_DONE) begin
        count = count + 1;
      end
    end
    return count;
  endfunction

  // Check if all warps are done
  function automatic logic all_warps_done();
    logic all_done;
    all_done = 1'b1;
    for (int i = 0; i < NUM_WARPS; i++) begin
      if (warp_state[i].valid && warp_state[i].status != WARP_DONE) begin
        all_done = 1'b0;
      end
    end
    return all_done;
  endfunction

endmodule
