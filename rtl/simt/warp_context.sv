// Warp Context - Per-warp state management
// Manages PC, active mask, status, and age for each warp
// Rewritten for Icarus Verilog compatibility using separate arrays

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

  // Status update interface (single warp)
  input  logic [WARP_ID_WIDTH-1:0]      status_warp_id,
  input  logic                          status_update,
  input  warp_status_t                  new_status,

  // Barrier wake interface (multiple warps simultaneously)
  input  logic [NUM_WARPS-1:0]          barrier_wake,

  // Age update (from scheduler)
  input  logic [WARP_ID_WIDTH-1:0]      issued_warp_id,
  input  logic                          warp_issued,

  // Read interface - all warp contexts
  output warp_context_t                 contexts [NUM_WARPS],

  // Single warp read interface
  input  logic [WARP_ID_WIDTH-1:0]      read_warp_id,
  output warp_context_t                 read_context
);

  // Internal storage - separate arrays for Icarus Verilog compatibility
  logic [DATA_WIDTH-1:0]   warp_pc    [NUM_WARPS];
  logic [WARP_SIZE-1:0]    warp_mask  [NUM_WARPS];
  logic [2:0]              warp_status[NUM_WARPS];  // warp_status_t
  logic [7:0]              warp_age   [NUM_WARPS];
  logic                    warp_valid [NUM_WARPS];

  // Output all contexts - using direct assign for Icarus compatibility
  assign contexts[0].pc = warp_pc[0];
  assign contexts[0].active_mask = warp_mask[0];
  assign contexts[0].status = warp_status_t'(warp_status[0]);
  assign contexts[0].age = warp_age[0];
  assign contexts[0].valid = warp_valid[0];

  assign contexts[1].pc = warp_pc[1];
  assign contexts[1].active_mask = warp_mask[1];
  assign contexts[1].status = warp_status_t'(warp_status[1]);
  assign contexts[1].age = warp_age[1];
  assign contexts[1].valid = warp_valid[1];

  assign contexts[2].pc = warp_pc[2];
  assign contexts[2].active_mask = warp_mask[2];
  assign contexts[2].status = warp_status_t'(warp_status[2]);
  assign contexts[2].age = warp_age[2];
  assign contexts[2].valid = warp_valid[2];

  assign contexts[3].pc = warp_pc[3];
  assign contexts[3].active_mask = warp_mask[3];
  assign contexts[3].status = warp_status_t'(warp_status[3]);
  assign contexts[3].age = warp_age[3];
  assign contexts[3].valid = warp_valid[3];

  // Single warp read - manual mux for Icarus compatibility
  assign read_context.pc = (read_warp_id == 2'd0) ? warp_pc[0] :
                           (read_warp_id == 2'd1) ? warp_pc[1] :
                           (read_warp_id == 2'd2) ? warp_pc[2] : warp_pc[3];
  assign read_context.active_mask = (read_warp_id == 2'd0) ? warp_mask[0] :
                                    (read_warp_id == 2'd1) ? warp_mask[1] :
                                    (read_warp_id == 2'd2) ? warp_mask[2] : warp_mask[3];
  assign read_context.status = warp_status_t'((read_warp_id == 2'd0) ? warp_status[0] :
                                              (read_warp_id == 2'd1) ? warp_status[1] :
                                              (read_warp_id == 2'd2) ? warp_status[2] : warp_status[3]);
  assign read_context.age = (read_warp_id == 2'd0) ? warp_age[0] :
                            (read_warp_id == 2'd1) ? warp_age[1] :
                            (read_warp_id == 2'd2) ? warp_age[2] : warp_age[3];
  assign read_context.valid = (read_warp_id == 2'd0) ? warp_valid[0] :
                              (read_warp_id == 2'd1) ? warp_valid[1] :
                              (read_warp_id == 2'd2) ? warp_valid[2] : warp_valid[3];

  // Warp 0 state
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      warp_pc[0] <= '0;
      warp_mask[0] <= '0;
      warp_status[0] <= WARP_IDLE;
      warp_age[0] <= '0;
      warp_valid[0] <= 1'b0;
    end else begin
      // Warp initialization
      if (init_valid && init_warp_id == 2'd0) begin
        warp_pc[0] <= init_pc;
        warp_mask[0] <= init_mask;
        warp_status[0] <= WARP_READY;
        warp_age[0] <= '0;
        warp_valid[0] <= 1'b1;
      end else begin
        // PC update
        if (pc_update && pc_warp_id == 2'd0) begin
          warp_pc[0] <= new_pc;
        end
        // Mask update
        if (mask_update && mask_warp_id == 2'd0) begin
          warp_mask[0] <= new_mask;
          if (new_mask == '0) warp_status[0] <= WARP_DONE;
        end
        // Status update
        if (status_update && status_warp_id == 2'd0) begin
          warp_status[0] <= new_status;
        end
        // Barrier wake
        if (barrier_wake[0] && warp_status[0] == WARP_BLOCKED) begin
          warp_status[0] <= WARP_READY;
        end
        // Age management
        if (warp_issued) begin
          if (issued_warp_id == 2'd0) begin
            warp_age[0] <= '0;
          end else if (warp_valid[0] && warp_status[0] == WARP_READY && warp_age[0] < 8'hFF) begin
            warp_age[0] <= warp_age[0] + 1;
          end
        end
      end
    end
  end

  // Warp 1 state
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      warp_pc[1] <= '0;
      warp_mask[1] <= '0;
      warp_status[1] <= WARP_IDLE;
      warp_age[1] <= '0;
      warp_valid[1] <= 1'b0;
    end else begin
      if (init_valid && init_warp_id == 2'd1) begin
        warp_pc[1] <= init_pc;
        warp_mask[1] <= init_mask;
        warp_status[1] <= WARP_READY;
        warp_age[1] <= '0;
        warp_valid[1] <= 1'b1;
      end else begin
        if (pc_update && pc_warp_id == 2'd1) warp_pc[1] <= new_pc;
        if (mask_update && mask_warp_id == 2'd1) begin
          warp_mask[1] <= new_mask;
          if (new_mask == '0) warp_status[1] <= WARP_DONE;
        end
        if (status_update && status_warp_id == 2'd1) warp_status[1] <= new_status;
        if (barrier_wake[1] && warp_status[1] == WARP_BLOCKED) warp_status[1] <= WARP_READY;
        if (warp_issued) begin
          if (issued_warp_id == 2'd1) warp_age[1] <= '0;
          else if (warp_valid[1] && warp_status[1] == WARP_READY && warp_age[1] < 8'hFF) warp_age[1] <= warp_age[1] + 1;
        end
      end
    end
  end

  // Warp 2 state
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      warp_pc[2] <= '0;
      warp_mask[2] <= '0;
      warp_status[2] <= WARP_IDLE;
      warp_age[2] <= '0;
      warp_valid[2] <= 1'b0;
    end else begin
      if (init_valid && init_warp_id == 2'd2) begin
        warp_pc[2] <= init_pc;
        warp_mask[2] <= init_mask;
        warp_status[2] <= WARP_READY;
        warp_age[2] <= '0;
        warp_valid[2] <= 1'b1;
      end else begin
        if (pc_update && pc_warp_id == 2'd2) warp_pc[2] <= new_pc;
        if (mask_update && mask_warp_id == 2'd2) begin
          warp_mask[2] <= new_mask;
          if (new_mask == '0) warp_status[2] <= WARP_DONE;
        end
        if (status_update && status_warp_id == 2'd2) warp_status[2] <= new_status;
        if (barrier_wake[2] && warp_status[2] == WARP_BLOCKED) warp_status[2] <= WARP_READY;
        if (warp_issued) begin
          if (issued_warp_id == 2'd2) warp_age[2] <= '0;
          else if (warp_valid[2] && warp_status[2] == WARP_READY && warp_age[2] < 8'hFF) warp_age[2] <= warp_age[2] + 1;
        end
      end
    end
  end

  // Warp 3 state
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      warp_pc[3] <= '0;
      warp_mask[3] <= '0;
      warp_status[3] <= WARP_IDLE;
      warp_age[3] <= '0;
      warp_valid[3] <= 1'b0;
    end else begin
      if (init_valid && init_warp_id == 2'd3) begin
        warp_pc[3] <= init_pc;
        warp_mask[3] <= init_mask;
        warp_status[3] <= WARP_READY;
        warp_age[3] <= '0;
        warp_valid[3] <= 1'b1;
      end else begin
        if (pc_update && pc_warp_id == 2'd3) warp_pc[3] <= new_pc;
        if (mask_update && mask_warp_id == 2'd3) begin
          warp_mask[3] <= new_mask;
          if (new_mask == '0) warp_status[3] <= WARP_DONE;
        end
        if (status_update && status_warp_id == 2'd3) warp_status[3] <= new_status;
        if (barrier_wake[3] && warp_status[3] == WARP_BLOCKED) warp_status[3] <= WARP_READY;
        if (warp_issued) begin
          if (issued_warp_id == 2'd3) warp_age[3] <= '0;
          else if (warp_valid[3] && warp_status[3] == WARP_READY && warp_age[3] < 8'hFF) warp_age[3] <= warp_age[3] + 1;
        end
      end
    end
  end

endmodule
