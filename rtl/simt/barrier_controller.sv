// Barrier Controller - Block-level and warp-level synchronization
// Manages barrier arrival tracking and warp wake-up for SYNC/WSYNC instructions

module barrier_controller
  import pkg_opengpu::*;
#(
  parameter int NUM_WARPS = WARPS_PER_CORE,
  parameter int NUM_BARRIERS = 16  // Max concurrent named barriers
)(
  input  logic                          clk,
  input  logic                          rst_n,

  // Barrier arrival from execute stage
  input  logic                          barrier_arrive,        // Warp arriving at barrier
  input  logic [WARP_ID_WIDTH-1:0]      arrive_warp_id,        // Which warp arrived
  input  logic [3:0]                    barrier_id,            // Barrier ID (0-15)
  input  logic                          is_block_barrier,      // SYNC (all warps) vs WSYNC (single warp)

  // Warp participation mask (which warps are active in this kernel)
  input  logic [NUM_WARPS-1:0]          active_warps,

  // Warp wake-up outputs
  output logic [NUM_WARPS-1:0]          warp_wake,             // Wake signals per warp
  output logic                          barrier_released,      // Barrier was released this cycle
  output logic [3:0]                    released_barrier_id,   // Which barrier was released

  // Status
  output logic [NUM_WARPS-1:0]          warps_at_barrier [NUM_BARRIERS],  // Warps waiting at each barrier
  output logic [NUM_BARRIERS-1:0]       barrier_active         // Which barriers have waiting warps
);

  // Per-barrier state
  logic [NUM_WARPS-1:0] barrier_arrived [NUM_BARRIERS];  // Which warps have arrived at each barrier

  // Barrier completion detection
  logic [NUM_BARRIERS-1:0] barrier_complete;

  // Detect when all participating warps have arrived at each barrier
  always_comb begin
    for (int b = 0; b < NUM_BARRIERS; b++) begin
      // Barrier is complete when all active warps have arrived
      barrier_complete[b] = barrier_active[b] &&
                            ((barrier_arrived[b] & active_warps) == active_warps);
    end
  end

  // Find which barrier (if any) completed this cycle
  // Using priority encoder for Icarus Verilog compatibility
  logic found_complete;
  logic [3:0] complete_barrier_id;

  always_comb begin
    found_complete = 1'b0;
    complete_barrier_id = 4'd0;
    // Manual priority encoder to avoid variable index issues
    if (barrier_complete[0]) begin found_complete = 1'b1; complete_barrier_id = 4'd0; end
    else if (barrier_complete[1]) begin found_complete = 1'b1; complete_barrier_id = 4'd1; end
    else if (barrier_complete[2]) begin found_complete = 1'b1; complete_barrier_id = 4'd2; end
    else if (barrier_complete[3]) begin found_complete = 1'b1; complete_barrier_id = 4'd3; end
    else if (barrier_complete[4]) begin found_complete = 1'b1; complete_barrier_id = 4'd4; end
    else if (barrier_complete[5]) begin found_complete = 1'b1; complete_barrier_id = 4'd5; end
    else if (barrier_complete[6]) begin found_complete = 1'b1; complete_barrier_id = 4'd6; end
    else if (barrier_complete[7]) begin found_complete = 1'b1; complete_barrier_id = 4'd7; end
    else if (barrier_complete[8]) begin found_complete = 1'b1; complete_barrier_id = 4'd8; end
    else if (barrier_complete[9]) begin found_complete = 1'b1; complete_barrier_id = 4'd9; end
    else if (barrier_complete[10]) begin found_complete = 1'b1; complete_barrier_id = 4'd10; end
    else if (barrier_complete[11]) begin found_complete = 1'b1; complete_barrier_id = 4'd11; end
    else if (barrier_complete[12]) begin found_complete = 1'b1; complete_barrier_id = 4'd12; end
    else if (barrier_complete[13]) begin found_complete = 1'b1; complete_barrier_id = 4'd13; end
    else if (barrier_complete[14]) begin found_complete = 1'b1; complete_barrier_id = 4'd14; end
    else if (barrier_complete[15]) begin found_complete = 1'b1; complete_barrier_id = 4'd15; end
  end

  // Barrier state machine
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int b = 0; b < NUM_BARRIERS; b++) begin
        barrier_arrived[b] <= '0;
      end
    end else begin
      // Handle new arrivals
      if (barrier_arrive) begin
        if (is_block_barrier) begin
          // SYNC: register warp at the specified barrier
          barrier_arrived[barrier_id][arrive_warp_id] <= 1'b1;
        end
        // WSYNC (warp-level sync) completes immediately for single warp
        // No state tracking needed - handled combinationally
      end

      // Release completed barriers
      if (found_complete) begin
        barrier_arrived[complete_barrier_id] <= '0;  // Reset for next barrier instance
      end
    end
  end

  // Track which barriers are active (have at least one waiting warp)
  always_comb begin
    for (int b = 0; b < NUM_BARRIERS; b++) begin
      barrier_active[b] = (barrier_arrived[b] != '0);
      warps_at_barrier[b] = barrier_arrived[b];
    end
  end

  // Generate wake signals
  always_comb begin
    warp_wake = '0;
    barrier_released = 1'b0;
    released_barrier_id = '0;

    if (found_complete) begin
      // Wake all warps that were waiting at the completed barrier
      warp_wake = barrier_arrived[complete_barrier_id];
      barrier_released = 1'b1;
      released_barrier_id = complete_barrier_id;
    end

    // WSYNC (warp-level sync) wakes immediately - all threads in warp sync
    // This just completes in one cycle since it's a single warp
    if (barrier_arrive && !is_block_barrier) begin
      warp_wake[arrive_warp_id] = 1'b1;
    end
  end

  // Assertions for debugging
  `ifdef SIMULATION
    // Check for double arrival (shouldn't happen)
    always @(posedge clk) begin
      if (barrier_arrive && is_block_barrier) begin
        assert (!barrier_arrived[barrier_id][arrive_warp_id])
          else $warning("Warp %0d arrived at barrier %0d twice", arrive_warp_id, barrier_id);
      end
    end

    // Check barrier released correctly
    always @(posedge clk) begin
      if (barrier_released) begin
        $display("[BARRIER] Barrier %0d released, waking warps: %b",
                 released_barrier_id, warp_wake);
      end
    end
  `endif

endmodule
