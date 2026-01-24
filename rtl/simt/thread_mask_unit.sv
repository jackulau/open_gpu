// Thread Mask Unit - Active mask management for SIMT execution
// Handles mask updates for divergence/reconvergence and predicated execution

module thread_mask_unit
  import pkg_opengpu::*;
(
  input  logic                    clk,
  input  logic                    rst_n,

  // Current mask input
  input  logic [WARP_SIZE-1:0]    current_mask,

  // Branch divergence input
  input  logic                    branch_valid,
  input  logic [WARP_SIZE-1:0]    branch_taken,     // Per-lane branch result

  // Divergence analysis output
  output logic                    is_divergent,
  output logic [WARP_SIZE-1:0]    taken_mask,       // Active lanes that took branch
  output logic [WARP_SIZE-1:0]    not_taken_mask,   // Active lanes that didn't take branch

  // Mask update operations
  input  logic                    mask_and,         // AND operation with input
  input  logic                    mask_or,          // OR operation with input
  input  logic                    mask_set,         // Direct set
  input  logic [WARP_SIZE-1:0]    mask_input,

  // Output mask
  output logic [WARP_SIZE-1:0]    new_mask,

  // Predicate evaluation (for predicated instructions)
  input  logic [WARP_SIZE-1:0]    predicate_values,
  input  logic                    predicate_valid,
  output logic [WARP_SIZE-1:0]    predicated_mask
);

  // Divergence detection
  always_comb begin
    taken_mask = current_mask & branch_taken;
    not_taken_mask = current_mask & ~branch_taken;

    // Divergent if both taken and not-taken have active lanes
    is_divergent = branch_valid &&
                   (taken_mask != '0) &&
                   (not_taken_mask != '0);
  end

  // Mask update logic
  always_comb begin
    if (mask_set) begin
      new_mask = mask_input;
    end else if (mask_and) begin
      new_mask = current_mask & mask_input;
    end else if (mask_or) begin
      new_mask = current_mask | mask_input;
    end else begin
      new_mask = current_mask;
    end
  end

  // Predicated mask (for conditional execution)
  assign predicated_mask = predicate_valid ?
                           (current_mask & predicate_values) :
                           current_mask;

  // Utility: count active lanes
  logic [5:0] active_count;
  always_comb begin
    active_count = '0;
    for (int i = 0; i < WARP_SIZE; i++) begin
      active_count = active_count + {5'b0, current_mask[i]};
    end
  end

  // Utility: check if all lanes active
  logic all_active;
  assign all_active = (current_mask == {WARP_SIZE{1'b1}});

  // Utility: check if no lanes active
  logic none_active;
  assign none_active = (current_mask == '0);

endmodule
