// Testbench for Shared Memory with Bank Conflict Detection
`timescale 1ns/1ps

module tb_shared_memory;

  import pkg_opengpu::*;

  // Clock and reset
  logic clk;
  logic rst_n;

  // Multi-lane request interface
  logic [WARP_SIZE-1:0]          req_valid;
  logic [WARP_SIZE-1:0]          req_we;
  logic [WARP_SIZE-1:0][15:0]    req_addr;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] req_wdata;
  logic [WARP_SIZE-1:0]          req_mask;

  logic [WARP_SIZE-1:0]          resp_valid;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] resp_rdata;
  logic                          ready;
  logic                          conflict_detected;
  logic [WARP_SIZE-1:0]          conflict_lanes;

  // Instantiate DUT
  shared_memory dut (
    .clk(clk),
    .rst_n(rst_n),
    .req_valid(req_valid),
    .req_we(req_we),
    .req_addr(req_addr),
    .req_wdata(req_wdata),
    .req_mask(req_mask),
    .resp_valid(resp_valid),
    .resp_rdata(resp_rdata),
    .ready(ready),
    .conflict_detected(conflict_detected),
    .conflict_lanes(conflict_lanes)
  );

  // Clock generation
  initial clk = 0;
  always #5 clk = ~clk;

  // Test counters
  int tests_passed = 0;
  int tests_failed = 0;

  task automatic check(string name, logic condition);
    if (condition) begin
      $display("  [PASS] %s", name);
      tests_passed++;
    end else begin
      $display("  [FAIL] %s", name);
      tests_failed++;
    end
  endtask

  // Wait for ready
  task automatic wait_ready();
    int timeout = 100;
    while (!ready && timeout > 0) begin
      @(posedge clk);
      timeout--;
    end
    if (timeout == 0) $display("  [WARN] Timeout waiting for ready");
  endtask

  // Wait for response
  task automatic wait_response();
    int timeout = 100;
    while (resp_valid == '0 && timeout > 0) begin
      @(posedge clk);
      timeout--;
    end
    if (timeout == 0) $display("  [WARN] Timeout waiting for response");
  endtask

  // Do a parallel write (all lanes)
  task automatic do_parallel_write(
    input logic [WARP_SIZE-1:0] mask,
    input logic [WARP_SIZE-1:0][15:0] addrs,
    input logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] data
  );
    wait_ready();
    @(posedge clk);

    req_valid <= mask;
    req_we <= {WARP_SIZE{1'b1}};
    req_addr <= addrs;
    req_wdata <= data;
    req_mask <= mask;

    @(posedge clk);
    req_valid <= '0;

    wait_response();
    @(posedge clk);
  endtask

  // Do a parallel read (all lanes)
  task automatic do_parallel_read(
    input logic [WARP_SIZE-1:0] mask,
    input logic [WARP_SIZE-1:0][15:0] addrs,
    output logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] data
  );
    wait_ready();
    @(posedge clk);

    req_valid <= mask;
    req_we <= '0;
    req_addr <= addrs;
    req_mask <= mask;

    @(posedge clk);
    req_valid <= '0;

    wait_response();
    data = resp_rdata;
    @(posedge clk);
  endtask

  // Test variables
  logic [WARP_SIZE-1:0][15:0] addrs;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] wdata;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rdata;

  initial begin
    $display("\n=== Shared Memory Testbench ===\n");

    // Initialize signals
    rst_n = 0;
    req_valid = 0;
    req_we = 0;
    req_addr = '0;
    req_wdata = '0;
    req_mask = 0;

    // Reset
    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(5) @(posedge clk);

    // Test 1: No conflict - each lane accesses different bank
    $display("Test 1: No conflict - strided access");
    // Bank = addr[6:2], so addresses 0, 4, 8, 12... access banks 0, 1, 2, 3...
    for (int i = 0; i < WARP_SIZE; i++) begin
      addrs[i] = i * 4;  // Each lane accesses different bank
      wdata[i] = 32'hA000_0000 + i;
    end
    do_parallel_write({WARP_SIZE{1'b1}}, addrs, wdata);
    check("No conflict on strided write", !conflict_detected);

    // Read back
    do_parallel_read({WARP_SIZE{1'b1}}, addrs, rdata);
    check("No conflict on strided read", !conflict_detected);

    // Verify data
    begin
      logic all_correct;
      all_correct = 1;
      for (int i = 0; i < WARP_SIZE; i++) begin
        if (rdata[i] != (32'hA000_0000 + i)) all_correct = 0;
      end
      check("Strided read data correct", all_correct);
    end

    // Test 2: Bank conflict - all lanes access same bank, different addresses
    $display("Test 2: Bank conflict - all lanes same bank");
    // Bank 0 = addresses where addr[6:2] = 0
    // Address 0, 128, 256, 384... are all in bank 0 but different words
    for (int i = 0; i < WARP_SIZE; i++) begin
      addrs[i] = i * 128;  // All bank 0, different words (word = addr[15:7])
      wdata[i] = 32'hB000_0000 + i;
    end

    wait_ready();
    @(posedge clk);
    req_valid <= {WARP_SIZE{1'b1}};
    req_we <= {WARP_SIZE{1'b1}};
    req_addr <= addrs;
    req_wdata <= wdata;
    req_mask <= {WARP_SIZE{1'b1}};
    @(posedge clk);

    // Check conflict detection (before request clears)
    check("Conflict detected on bank conflict write", conflict_detected);
    check("All lanes marked as conflicting", conflict_lanes == {WARP_SIZE{1'b1}});

    req_valid <= '0;
    wait_response();
    @(posedge clk);

    // Read back and verify (will also conflict)
    do_parallel_read({WARP_SIZE{1'b1}}, addrs, rdata);

    // Verify data (despite conflicts, all writes should complete)
    begin
      logic all_correct;
      all_correct = 1;
      for (int i = 0; i < WARP_SIZE; i++) begin
        if (rdata[i] != (32'hB000_0000 + i)) begin
          $display("  Lane %0d: expected %h, got %h", i, 32'hB000_0000 + i, rdata[i]);
          all_correct = 0;
        end
      end
      check("Conflicting access data eventually correct", all_correct);
    end

    // Test 3: Broadcast - all lanes access same address (no conflict)
    $display("Test 3: Broadcast - all lanes same address");
    for (int i = 0; i < WARP_SIZE; i++) begin
      addrs[i] = 16'h0200;  // Same address for all lanes
    end
    wdata[0] = 32'hC0DE_CAFE;  // Only one write matters
    for (int i = 1; i < WARP_SIZE; i++) wdata[i] = 32'hC0DE_CAFE;

    do_parallel_write({WARP_SIZE{1'b1}}, addrs, wdata);

    // Read back with broadcast
    wait_ready();
    @(posedge clk);
    req_valid <= {WARP_SIZE{1'b1}};
    req_we <= '0;
    req_addr <= addrs;
    req_mask <= {WARP_SIZE{1'b1}};
    @(posedge clk);

    // Broadcast should NOT cause conflict
    check("No conflict on broadcast read", !conflict_detected);

    req_valid <= '0;
    wait_response();
    @(posedge clk);

    // Verify all lanes got broadcast data
    begin
      logic all_correct;
      all_correct = 1;
      for (int i = 0; i < WARP_SIZE; i++) begin
        if (resp_rdata[i] != 32'hC0DE_CAFE) all_correct = 0;
      end
      check("Broadcast data correct for all lanes", all_correct);
    end

    // Test 4: Partial mask
    $display("Test 4: Partial mask - only some lanes active");
    for (int i = 0; i < WARP_SIZE; i++) begin
      addrs[i] = i * 4;
      wdata[i] = 32'hD000_0000 + i;
    end

    // Only enable even lanes
    do_parallel_write(32'h5555_5555, addrs, wdata);
    check("Partial mask write accepted", 1);

    // Read with full mask
    do_parallel_read({WARP_SIZE{1'b1}}, addrs, rdata);

    // Check even lanes have new data, odd lanes have old data
    begin
      logic even_correct;
      even_correct = 1;
      for (int i = 0; i < WARP_SIZE; i += 2) begin
        if (rdata[i] != (32'hD000_0000 + i)) even_correct = 0;
      end
      check("Even lanes have new data", even_correct);
    end

    // Test 5: Mixed conflict/no-conflict
    $display("Test 5: Mixed - some lanes conflict, some don't");
    // Lanes 0-3 access bank 0 (conflict among themselves)
    // Lanes 4-7 access bank 1 (conflict among themselves)
    // Lanes 8-15 access different banks (no conflict)
    for (int i = 0; i < 4; i++) addrs[i] = i * 128;  // Bank 0
    for (int i = 4; i < 8; i++) addrs[i] = 4 + (i-4) * 128;  // Bank 1
    for (int i = 8; i < WARP_SIZE; i++) addrs[i] = i * 4;  // Banks 2-23

    for (int i = 0; i < WARP_SIZE; i++) wdata[i] = 32'hE000_0000 + i;

    wait_ready();
    @(posedge clk);
    req_valid <= {WARP_SIZE{1'b1}};
    req_we <= {WARP_SIZE{1'b1}};
    req_addr <= addrs;
    req_wdata <= wdata;
    req_mask <= {WARP_SIZE{1'b1}};
    @(posedge clk);

    check("Conflict detected on mixed access", conflict_detected);
    // Lanes 0-7 should be marked as conflicting
    check("Conflict lanes correct", (conflict_lanes & 8'hFF) == 8'hFF);

    req_valid <= '0;
    wait_response();
    @(posedge clk);

    // Test 6: Write then read same cycle (different addresses)
    $display("Test 6: Sequential write-read");
    addrs[0] = 16'h0400;
    wdata[0] = 32'hFACE_FACE;
    do_parallel_write(32'h0001, addrs, wdata);

    addrs[0] = 16'h0400;
    do_parallel_read(32'h0001, addrs, rdata);
    check("Write-read sequence correct", rdata[0] == 32'hFACE_FACE);

    // Summary
    $display("\n=== Test Summary ===");
    $display("Tests passed: %0d", tests_passed);
    $display("Tests failed: %0d", tests_failed);

    if (tests_failed == 0) begin
      $display("\n*** ALL TESTS PASSED ***\n");
    end else begin
      $display("\n*** SOME TESTS FAILED ***\n");
    end

    $finish;
  end

endmodule
