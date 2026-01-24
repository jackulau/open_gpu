// Warp Scheduler - GTO (Greedy-Then-Oldest) Policy
// Selects ready warp with highest age, preferring last-issued warp if still eligible

module warp_scheduler
  import pkg_opengpu::*;
#(
  parameter int NUM_WARPS = WARPS_PER_CORE
)(
  input  logic                          clk,
  input  logic                          rst_n,

  // Warp contexts - individual arrays for Icarus Verilog compatibility
  input  logic [NUM_WARPS-1:0][DATA_WIDTH-1:0]  ctx_pc,
  input  logic [NUM_WARPS-1:0][WARP_SIZE-1:0]   ctx_mask,
  input  logic [NUM_WARPS-1:0][2:0]             ctx_status,  // warp_status_t
  input  logic [NUM_WARPS-1:0][7:0]             ctx_age,
  input  logic [NUM_WARPS-1:0]                  ctx_valid,

  // Stall signals (warp cannot be issued)
  input  logic [NUM_WARPS-1:0]          warp_stall,

  // Selected warp output
  output logic                          warp_valid,
  output logic [WARP_ID_WIDTH-1:0]      selected_warp_id,
  output logic [DATA_WIDTH-1:0]         selected_pc,
  output logic [WARP_SIZE-1:0]          selected_mask,

  // Acknowledge - indicates warp was issued
  input  logic                          issue_ack,

  // All warps done indication
  output logic                          all_done
);

  // Last issued warp for greedy preference
  logic [WARP_ID_WIDTH-1:0] last_issued_warp;
  logic                     last_issued_valid;

  // Eligible warp detection
  logic [NUM_WARPS-1:0] warp_eligible;

  // Find eligible warps (valid, ready, not stalled)
  always_comb begin
    for (int i = 0; i < NUM_WARPS; i++) begin
      warp_eligible[i] = ctx_valid[i] &&
                         (ctx_status[i] == WARP_READY) &&
                         !warp_stall[i];
    end
  end

  // GTO selection logic
  logic                     found_warp;
  logic [WARP_ID_WIDTH-1:0] selected_id;
  logic [7:0]               max_age;

  always_comb begin
    found_warp = 1'b0;
    selected_id = '0;
    max_age = '0;

    // Step 1: Greedy - prefer last issued if still eligible
    if (last_issued_valid && warp_eligible[last_issued_warp]) begin
      found_warp = 1'b1;
      selected_id = last_issued_warp;
    end else begin
      // Step 2: Oldest - find eligible warp with highest age
      for (int i = 0; i < NUM_WARPS; i++) begin
        if (warp_eligible[i]) begin
          if (!found_warp || ctx_age[i] > max_age) begin
            found_warp = 1'b1;
            selected_id = i[WARP_ID_WIDTH-1:0];
            max_age = ctx_age[i];
          end
        end
      end
    end
  end

  // Output selected warp info
  assign warp_valid = found_warp;
  assign selected_warp_id = selected_id;
  assign selected_pc = ctx_pc[selected_id];
  assign selected_mask = ctx_mask[selected_id];

  // Track last issued warp
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      last_issued_warp <= '0;
      last_issued_valid <= 1'b0;
    end else if (issue_ack && warp_valid) begin
      last_issued_warp <= selected_warp_id;
      last_issued_valid <= 1'b1;
    end
  end

  // Check if all warps are done
  logic [NUM_WARPS-1:0] warp_done;
  always_comb begin
    for (int i = 0; i < NUM_WARPS; i++) begin
      warp_done[i] = !ctx_valid[i] || (ctx_status[i] == WARP_DONE);
    end
    all_done = &warp_done;
  end

endmodule
