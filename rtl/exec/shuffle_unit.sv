// Shuffle Unit - Lane data exchange operations
// Implements SHFLIDX (indexed), SHFLUP, SHFLDN, SHFLXOR

module shuffle_unit
  import pkg_opengpu::*;
(
  // Input data from all lanes
  input  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] lane_data,

  // Shuffle operation
  input  shuffle_op_t                          shuffle_op,

  // Index/offset value (per-lane for SHFLIDX, shared for others)
  input  logic [WARP_SIZE-1:0][4:0]            shuffle_idx,

  // Width parameter (optional segmented shuffle)
  input  logic [4:0]                           width,

  // Active thread mask
  input  logic [WARP_SIZE-1:0]                 active_mask,

  // Output data (per-lane)
  output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] result,

  // Valid flags (per-lane) - indicates if source lane was active
  output logic [WARP_SIZE-1:0]                 result_valid
);

  // Compute source lane for each destination lane
  logic [WARP_SIZE-1:0][4:0] src_lane;

  always_comb begin
    for (int i = 0; i < WARP_SIZE; i++) begin
      case (shuffle_op)
        SHFL_IDX: begin
          // Direct indexed shuffle - get data from lane specified by shuffle_idx
          src_lane[i] = shuffle_idx[i];
        end

        SHFL_UP: begin
          // Shuffle up - lane i gets data from lane (i - offset)
          // Lower lanes get invalid data
          if (i >= shuffle_idx[0]) begin
            src_lane[i] = i[4:0] - shuffle_idx[0];
          end else begin
            src_lane[i] = i[4:0];  // Out of bounds, will be marked invalid
          end
        end

        SHFL_DOWN: begin
          // Shuffle down - lane i gets data from lane (i + offset)
          // Upper lanes get invalid data
          if ((i + shuffle_idx[0]) < WARP_SIZE) begin
            src_lane[i] = i[4:0] + shuffle_idx[0];
          end else begin
            src_lane[i] = i[4:0];  // Out of bounds, will be marked invalid
          end
        end

        SHFL_XOR: begin
          // XOR shuffle - lane i gets data from lane (i XOR offset)
          // Used for butterfly patterns in reductions
          src_lane[i] = i[4:0] ^ shuffle_idx[0];
        end

        default: begin
          src_lane[i] = i[4:0];  // Identity
        end
      endcase
    end
  end

  // Crossbar: route data from source lanes to destination lanes
  always_comb begin
    for (int i = 0; i < WARP_SIZE; i++) begin
      // Get data from computed source lane
      result[i] = lane_data[src_lane[i]];

      // Check if result is valid
      case (shuffle_op)
        SHFL_IDX: begin
          // Valid if source lane is active
          result_valid[i] = active_mask[i] && active_mask[src_lane[i]];
        end

        SHFL_UP: begin
          // Valid if this lane is active and source lane exists and is active
          result_valid[i] = active_mask[i] &&
                            (i >= shuffle_idx[0]) &&
                            active_mask[src_lane[i]];
        end

        SHFL_DOWN: begin
          // Valid if this lane is active and source lane exists and is active
          result_valid[i] = active_mask[i] &&
                            ((i + shuffle_idx[0]) < WARP_SIZE) &&
                            active_mask[src_lane[i]];
        end

        SHFL_XOR: begin
          // Valid if both this lane and XOR partner are active
          result_valid[i] = active_mask[i] && active_mask[src_lane[i]];
        end

        default: begin
          result_valid[i] = active_mask[i];
        end
      endcase
    end
  end

endmodule
