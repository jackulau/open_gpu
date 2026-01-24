// Testbench for SIMT Stack

`timescale 1ns/1ps

module tb_simt_stack;
  import pkg_opengpu::*;

  // Clock and reset
  logic clk;
  logic rst_n;

  // DUT signals
  logic                    push;
  logic                    pop;
  simt_stack_entry_t       push_entry;
  simt_stack_entry_t       top_entry;
  logic                    stack_empty;
  logic                    stack_full;
  logic [$clog2(SIMT_STACK_DEPTH):0] stack_depth;
  logic [DATA_WIDTH-1:0]   current_pc;
  logic                    at_reconvergence;

  // Instantiate DUT
  simt_stack #(
    .DEPTH(SIMT_STACK_DEPTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .push(push),
    .pop(pop),
    .push_entry(push_entry),
    .top_entry(top_entry),
    .stack_empty(stack_empty),
    .stack_full(stack_full),
    .stack_depth(stack_depth),
    .current_pc(current_pc),
    .at_reconvergence(at_reconvergence)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Test counters
  int tests_passed = 0;
  int tests_failed = 0;

  // Helper task for checking results
  task check(string name, logic condition);
    if (condition) begin
      $display("[PASS] %s", name);
      tests_passed++;
    end else begin
      $display("[FAIL] %s", name);
      tests_failed++;
    end
  endtask

  // Reset task
  task reset_dut();
    rst_n = 0;
    push = 0;
    pop = 0;
    push_entry = '0;
    current_pc = '0;
    @(posedge clk);
    @(posedge clk);
    rst_n = 1;
    @(posedge clk);
  endtask

  // Push entry task
  task push_stack(
    input logic [DATA_WIDTH-1:0] reconv_pc,
    input logic [WARP_SIZE-1:0] active,
    input logic [WARP_SIZE-1:0] taken
  );
    push = 1;
    push_entry.reconvergence_pc = reconv_pc;
    push_entry.active_mask = active;
    push_entry.taken_mask = taken;
    @(posedge clk);
    push = 0;
    @(posedge clk);
  endtask

  // Pop entry task
  task pop_stack();
    pop = 1;
    @(posedge clk);
    pop = 0;
    @(posedge clk);
  endtask

  // Main test sequence
  initial begin
    $display("========================================");
    $display("SIMT Stack Testbench");
    $display("========================================");

    // Initialize
    reset_dut();

    // Test 1: Check empty stack on reset
    $display("\n--- Test 1: Empty stack after reset ---");
    check("Stack empty on reset", stack_empty == 1);
    check("Stack depth is 0", stack_depth == 0);
    check("Stack not full", stack_full == 0);

    // Test 2: Push single entry
    $display("\n--- Test 2: Push single entry ---");
    push_stack(32'h100, 32'hFFFFFFFF, 32'h0000FFFF);
    check("Stack not empty after push", stack_empty == 0);
    check("Stack depth is 1", stack_depth == 1);
    check("Top reconvergence PC correct", top_entry.reconvergence_pc == 32'h100);
    check("Top active mask correct", top_entry.active_mask == 32'hFFFFFFFF);
    check("Top taken mask correct", top_entry.taken_mask == 32'h0000FFFF);

    // Test 3: Reconvergence detection
    $display("\n--- Test 3: Reconvergence detection ---");
    current_pc = 32'h50;
    @(posedge clk);
    check("Not at reconvergence (PC mismatch)", at_reconvergence == 0);
    current_pc = 32'h100;
    @(posedge clk);
    check("At reconvergence (PC match)", at_reconvergence == 1);

    // Test 4: Pop entry
    $display("\n--- Test 4: Pop entry ---");
    pop_stack();
    check("Stack empty after pop", stack_empty == 1);
    check("Stack depth is 0", stack_depth == 0);

    // Test 5: Multiple pushes (nested divergence)
    $display("\n--- Test 5: Nested divergence (multiple pushes) ---");
    push_stack(32'h200, 32'hFFFFFFFF, 32'h00FF00FF);  // Level 1
    push_stack(32'h150, 32'h00FF00FF, 32'h000F000F);  // Level 2
    push_stack(32'h120, 32'h000F000F, 32'h00030003);  // Level 3

    check("Stack depth is 3", stack_depth == 3);
    check("Top is level 3", top_entry.reconvergence_pc == 32'h120);

    // Pop and check each level
    pop_stack();
    check("After pop 1: depth is 2", stack_depth == 2);
    check("After pop 1: top is level 2", top_entry.reconvergence_pc == 32'h150);

    pop_stack();
    check("After pop 2: depth is 1", stack_depth == 1);
    check("After pop 2: top is level 1", top_entry.reconvergence_pc == 32'h200);

    pop_stack();
    check("After pop 3: stack empty", stack_empty == 1);

    // Test 6: Stack full condition
    $display("\n--- Test 6: Stack full detection ---");
    for (int i = 0; i < SIMT_STACK_DEPTH; i++) begin
      push_stack(32'h1000 + i*4, 32'hFFFFFFFF, 32'h0000FFFF);
    end
    check("Stack is full", stack_full == 1);
    check("Stack depth is max", stack_depth == SIMT_STACK_DEPTH);

    // Push when full should be ignored
    push_stack(32'hDEAD, 32'hBEEF, 32'hCAFE);
    check("Stack still full after push-when-full", stack_full == 1);
    check("Top unchanged", top_entry.reconvergence_pc == 32'h1000 + (SIMT_STACK_DEPTH-1)*4);

    // Clean up stack
    for (int i = 0; i < SIMT_STACK_DEPTH; i++) begin
      pop_stack();
    end
    check("Stack empty after full cleanup", stack_empty == 1);

    // Test 7: Simultaneous push and pop (replace)
    $display("\n--- Test 7: Simultaneous push and pop ---");
    push_stack(32'h300, 32'hAAAAAAAA, 32'h55555555);
    check("Setup: depth is 1", stack_depth == 1);

    // Simultaneous push and pop
    push = 1;
    pop = 1;
    push_entry.reconvergence_pc = 32'h400;
    push_entry.active_mask = 32'hBBBBBBBB;
    push_entry.taken_mask = 32'h66666666;
    @(posedge clk);
    push = 0;
    pop = 0;
    @(posedge clk);

    check("Depth still 1 after push+pop", stack_depth == 1);
    check("Top replaced with new entry", top_entry.reconvergence_pc == 32'h400);
    check("New active mask", top_entry.active_mask == 32'hBBBBBBBB);

    // Cleanup
    pop_stack();

    // Test 8: Typical divergence scenario
    $display("\n--- Test 8: Typical if-else divergence ---");
    // Simulate: if (lane_id < 16) { ... } else { ... }
    // All 32 threads active, lanes 0-15 take if-branch, 16-31 take else-branch

    // Push divergence point (using literals directly)
    push_stack(32'h500, 32'hFFFFFFFF, 32'h0000FFFF);
    check("Divergence pushed", stack_depth == 1);

    // Check masks
    check("Active mask is all", top_entry.active_mask == 32'hFFFFFFFF);
    check("Taken mask is lower half", top_entry.taken_mask == 32'h0000FFFF);

    // Simulate reaching reconvergence
    current_pc = 32'h500;
    @(posedge clk);
    check("Reached reconvergence point", at_reconvergence == 1);

    // Pop to restore mask
    pop_stack();
    check("Stack empty after reconvergence", stack_empty == 1);

    // Print results
    $display("\n========================================");
    $display("Test Results: %0d passed, %0d failed", tests_passed, tests_failed);
    $display("========================================");

    if (tests_failed == 0) begin
      $display("ALL TESTS PASSED");
    end else begin
      $display("SOME TESTS FAILED");
    end

    $finish;
  end

  // Timeout
  initial begin
    #10000;
    $display("ERROR: Timeout");
    $finish;
  end

  // Waveform dump
  initial begin
    $dumpfile("tb_simt_stack.vcd");
    $dumpvars(0, tb_simt_stack);
  end

endmodule
