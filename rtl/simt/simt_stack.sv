// SIMT Stack - Per-warp divergence handling stack
// Stores reconvergence points and thread masks for branch divergence

module simt_stack
  import pkg_opengpu::*;
#(
  parameter int DEPTH = SIMT_STACK_DEPTH  // Stack depth (32 entries)
)(
  input  logic                    clk,
  input  logic                    rst_n,

  // Stack operations
  input  logic                    push,
  input  logic                    pop,
  input  simt_stack_entry_t       push_entry,

  // Stack output
  output simt_stack_entry_t       top_entry,
  output logic                    stack_empty,
  output logic                    stack_full,
  output logic [$clog2(DEPTH):0]  stack_depth,

  // Reconvergence check
  input  logic [DATA_WIDTH-1:0]   current_pc,
  output logic                    at_reconvergence
);

  // Stack storage
  simt_stack_entry_t stack_mem [DEPTH];
  logic [$clog2(DEPTH):0] sp;  // Stack pointer (points to next free slot)

  // Stack status
  assign stack_empty = (sp == '0);
  assign stack_full = (sp == DEPTH[$clog2(DEPTH):0]);
  assign stack_depth = sp;

  // Top of stack (valid only when not empty)
  assign top_entry = stack_empty ? '0 : stack_mem[sp - 1];

  // Check if current PC matches reconvergence point at top of stack
  assign at_reconvergence = !stack_empty && (current_pc == top_entry.reconvergence_pc);

  // Stack operations
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sp <= '0;
      for (int i = 0; i < DEPTH; i++) begin
        stack_mem[i] <= '0;
      end
    end else begin
      // Handle simultaneous push and pop (replace top)
      if (push && pop && !stack_empty) begin
        stack_mem[sp - 1] <= push_entry;
      end
      // Push new entry
      else if (push && !stack_full) begin
        stack_mem[sp] <= push_entry;
        sp <= sp + 1;
      end
      // Pop top entry
      else if (pop && !stack_empty) begin
        sp <= sp - 1;
      end
    end
  end

  // Assertions for debugging
  `ifdef SIMULATION
    always_ff @(posedge clk) begin
      if (push && stack_full && !pop) begin
        $error("SIMT Stack: Overflow - push when full");
      end
      if (pop && stack_empty) begin
        $error("SIMT Stack: Underflow - pop when empty");
      end
    end
  `endif

endmodule
