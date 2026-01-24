// Testbench for Warp Scheduler (GTO Policy)

`timescale 1ns/1ps

module tb_warp_scheduler;
  import pkg_opengpu::*;

  localparam int NUM_WARPS = WARPS_PER_CORE;

  // Clock and reset
  logic clk;
  logic rst_n;

  // DUT signals - packed arrays for interface
  logic [NUM_WARPS-1:0][DATA_WIDTH-1:0] ctx_pc;
  logic [NUM_WARPS-1:0][WARP_SIZE-1:0] ctx_mask;
  logic [NUM_WARPS-1:0][2:0] ctx_status;
  logic [NUM_WARPS-1:0][7:0] ctx_age;
  logic [NUM_WARPS-1:0] ctx_valid;

  logic [NUM_WARPS-1:0] warp_stall;
  logic warp_valid;
  logic [WARP_ID_WIDTH-1:0] selected_warp_id;
  logic [DATA_WIDTH-1:0] selected_pc;
  logic [WARP_SIZE-1:0] selected_mask;
  logic issue_ack;
  logic all_done;

  // Instantiate DUT
  warp_scheduler #(
    .NUM_WARPS(NUM_WARPS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .ctx_pc(ctx_pc),
    .ctx_mask(ctx_mask),
    .ctx_status(ctx_status),
    .ctx_age(ctx_age),
    .ctx_valid(ctx_valid),
    .warp_stall(warp_stall),
    .warp_valid(warp_valid),
    .selected_warp_id(selected_warp_id),
    .selected_pc(selected_pc),
    .selected_mask(selected_mask),
    .issue_ack(issue_ack),
    .all_done(all_done)
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
    warp_stall = '0;
    issue_ack = 0;
    ctx_pc = '0;
    ctx_mask = '0;
    ctx_status = '0;
    ctx_age = '0;
    ctx_valid = '0;
    @(posedge clk);
    @(posedge clk);
    rst_n = 1;
    @(posedge clk);
  endtask

  // Setup a warp
  task setup_warp(
    input int warp_id,
    input logic [DATA_WIDTH-1:0] pc,
    input logic [WARP_SIZE-1:0] mask,
    input logic [2:0] status,
    input logic [7:0] age
  );
    ctx_pc[warp_id] = pc;
    ctx_mask[warp_id] = mask;
    ctx_status[warp_id] = status;
    ctx_age[warp_id] = age;
    ctx_valid[warp_id] = 1'b1;
  endtask

  // Issue and acknowledge
  task issue_warp();
    issue_ack = 1;
    @(posedge clk);
    issue_ack = 0;
    @(posedge clk);
  endtask

  // Main test sequence
  initial begin
    $display("========================================");
    $display("Warp Scheduler (GTO) Testbench");
    $display("========================================");

    // Initialize
    reset_dut();

    // Test 1: No valid warps
    $display("\n--- Test 1: No valid warps ---");
    @(posedge clk);
    check("No warp selected when none valid", warp_valid == 0);
    check("All done when no warps", all_done == 1);

    // Test 2: Single ready warp
    $display("\n--- Test 2: Single ready warp ---");
    setup_warp(0, 32'h100, 32'hFFFFFFFF, WARP_READY, 8'd0);
    @(posedge clk);
    check("Warp 0 selected", warp_valid == 1 && selected_warp_id == 0);
    check("Correct PC", selected_pc == 32'h100);
    check("Correct mask", selected_mask == 32'hFFFFFFFF);
    check("Not all done", all_done == 0);

    // Test 3: Multiple warps - oldest selected
    $display("\n--- Test 3: Multiple warps - oldest selected ---");
    setup_warp(0, 32'h100, 32'hFFFFFFFF, WARP_READY, 8'd5);
    setup_warp(1, 32'h200, 32'hFFFFFFFF, WARP_READY, 8'd10);  // Oldest
    setup_warp(2, 32'h300, 32'hFFFFFFFF, WARP_READY, 8'd3);
    setup_warp(3, 32'h400, 32'hFFFFFFFF, WARP_READY, 8'd7);
    @(posedge clk);
    check("Oldest warp (1) selected", warp_valid == 1 && selected_warp_id == 1);
    check("Warp 1 PC correct", selected_pc == 32'h200);

    // Test 4: Greedy preference after issue
    $display("\n--- Test 4: Greedy preference ---");
    // Issue warp 1
    issue_warp();
    // Now warp 1 should still be selected (greedy)
    @(posedge clk);
    check("Greedy: last issued warp 1 still selected", selected_warp_id == 1);

    // Make warp 1 not ready
    ctx_status[1] = WARP_WAITING;
    @(posedge clk);
    // Now should select oldest among remaining (warp 3 has age 7)
    check("After warp 1 waiting, warp 3 selected (age 7)", selected_warp_id == 3);

    // Test 5: Stall handling
    $display("\n--- Test 5: Stall handling ---");
    ctx_status[1] = WARP_READY;  // Restore warp 1
    warp_stall = 4'b1010;  // Stall warps 1 and 3
    @(posedge clk);
    // Should select from warps 0 or 2 (0 has age 5, 2 has age 3)
    check("Stalled warps skipped, warp 0 selected", selected_warp_id == 0);

    // Stall all warps
    warp_stall = 4'b1111;
    @(posedge clk);
    check("All warps stalled - no valid selection", warp_valid == 0);

    // Test 6: All warps done
    $display("\n--- Test 6: All warps done ---");
    warp_stall = '0;
    ctx_status[0] = WARP_DONE;
    ctx_status[1] = WARP_DONE;
    ctx_status[2] = WARP_DONE;
    ctx_status[3] = WARP_DONE;
    @(posedge clk);
    check("No warp selected when all done", warp_valid == 0);
    check("All done signal asserted", all_done == 1);

    // Test 7: Mixed status warps
    $display("\n--- Test 7: Mixed status warps ---");
    ctx_status[0] = WARP_DONE;
    ctx_status[1] = WARP_WAITING;
    ctx_status[2] = WARP_READY;
    ctx_age[2] = 8'd5;
    ctx_status[3] = WARP_BLOCKED;
    @(posedge clk);
    check("Only ready warp (2) selected", warp_valid == 1 && selected_warp_id == 2);
    check("Not all done with mixed status", all_done == 0);

    // Test 8: Warp with zero mask still eligible (mask managed externally)
    $display("\n--- Test 8: Scheduler respects ready status ---");
    reset_dut();
    setup_warp(0, 32'h100, 32'h0, WARP_READY, 8'd0);  // Zero mask but ready
    @(posedge clk);
    check("Warp with zero mask but READY is selected", warp_valid == 1 && selected_warp_id == 0);

    // Test 9: GTO aging priority
    $display("\n--- Test 9: GTO aging verification ---");
    reset_dut();
    // All same age initially
    setup_warp(0, 32'h100, 32'hFFFFFFFF, WARP_READY, 8'd0);
    setup_warp(1, 32'h200, 32'hFFFFFFFF, WARP_READY, 8'd0);
    setup_warp(2, 32'h300, 32'hFFFFFFFF, WARP_READY, 8'd0);
    setup_warp(3, 32'h400, 32'hFFFFFFFF, WARP_READY, 8'd0);
    @(posedge clk);

    // First selection should be warp 0 (first found with same age)
    check("Initial: warp 0 selected", selected_warp_id == 0);
    issue_warp();

    // Greedy should keep warp 0
    @(posedge clk);
    check("Greedy: still warp 0", selected_warp_id == 0);

    // Stall warp 0 to break greedy
    warp_stall = 4'b0001;
    // Simulate age increment (normally done by warp_context)
    ctx_age[1] = 8'd1;
    ctx_age[2] = 8'd1;
    ctx_age[3] = 8'd1;
    @(posedge clk);

    // Should select one of the aged warps (all have age 1, so first found)
    check("After stall, another warp selected", selected_warp_id != 0);

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
    $dumpfile("tb_warp_scheduler.vcd");
    $dumpvars(0, tb_warp_scheduler);
  end

endmodule
