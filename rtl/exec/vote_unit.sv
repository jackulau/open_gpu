// Vote Unit - Warp-wide voting operations
// Implements VOTEALL, VOTEANY, VOTEBAL (ballot)

module vote_unit
  import pkg_opengpu::*;
(
  // Input predicate values (per-lane)
  input  logic [WARP_SIZE-1:0]      predicate,

  // Active thread mask
  input  logic [WARP_SIZE-1:0]      active_mask,

  // Vote operation type
  input  vote_op_t                  vote_op,

  // Vote result (broadcast to all lanes or ballot mask)
  output logic [DATA_WIDTH-1:0]     result,

  // Boolean results for specific vote ops
  output logic                      vote_all_result,
  output logic                      vote_any_result,
  output logic [WARP_SIZE-1:0]      vote_ballot_result
);

  // Masked predicate - only consider active lanes
  logic [WARP_SIZE-1:0] masked_predicate;
  assign masked_predicate = predicate & active_mask;

  // VOTEALL: All active lanes have predicate true
  assign vote_all_result = (masked_predicate == active_mask) && (active_mask != '0);

  // VOTEANY: Any active lane has predicate true
  assign vote_any_result = (masked_predicate != '0);

  // VOTEBAL: Return mask of active lanes with true predicate
  assign vote_ballot_result = masked_predicate;

  // Result selection based on operation
  always_comb begin
    case (vote_op)
      VOTE_ALL: result = {31'd0, vote_all_result};
      VOTE_ANY: result = {31'd0, vote_any_result};
      VOTE_BAL: result = vote_ballot_result;
      default:  result = '0;
    endcase
  end

endmodule
