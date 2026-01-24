// Testbench for L1 Data Cache
`timescale 1ns/1ps

module tb_l1_data_cache;

  import pkg_opengpu::*;

  // Clock and reset
  logic clk;
  logic rst_n;

  // CPU-side interface
  logic                          req_valid;
  logic                          req_we;
  logic [ADDR_WIDTH-1:0]         req_addr;
  logic [DATA_WIDTH-1:0]         req_wdata;
  logic [3:0]                    req_byte_en;
  mem_size_t                     req_size;

  logic                          resp_valid;
  logic                          resp_hit;
  logic [DATA_WIDTH-1:0]         resp_rdata;
  logic                          ready;

  // L2 interface
  logic                          l2_req_valid;
  logic [2:0]                    l2_req_type;
  logic [ADDR_WIDTH-1:0]         l2_req_addr;
  logic [CACHE_LINE_BITS-1:0]    l2_req_wdata;

  logic                          l2_resp_valid;
  logic [CACHE_LINE_BITS-1:0]    l2_resp_rdata;
  logic                          l2_ready;

  // Flush control
  logic                          flush_req;
  logic                          flush_done;

  // Statistics
  cache_stats_t                  stats;

  // Instantiate DUT
  l1_data_cache dut (
    .clk(clk),
    .rst_n(rst_n),
    .req_valid(req_valid),
    .req_we(req_we),
    .req_addr(req_addr),
    .req_wdata(req_wdata),
    .req_byte_en(req_byte_en),
    .req_size(req_size),
    .resp_valid(resp_valid),
    .resp_hit(resp_hit),
    .resp_rdata(resp_rdata),
    .ready(ready),
    .l2_req_valid(l2_req_valid),
    .l2_req_type(l2_req_type),
    .l2_req_addr(l2_req_addr),
    .l2_req_wdata(l2_req_wdata),
    .l2_resp_valid(l2_resp_valid),
    .l2_resp_rdata(l2_resp_rdata),
    .l2_ready(l2_ready),
    .flush_req(flush_req),
    .flush_done(flush_done),
    .stats(stats)
  );

  // Clock generation
  initial clk = 0;
  always #5 clk = ~clk;

  // Simulated L2 memory (simple model)
  logic [CACHE_LINE_BITS-1:0] l2_memory [0:1023];

  // L2 response delay
  int l2_delay_counter;
  logic [CACHE_LINE_BITS-1:0] l2_pending_data;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      l2_resp_valid <= 1'b0;
      l2_ready <= 1'b1;
      l2_delay_counter <= 0;
      l2_pending_data <= '0;
    end else begin
      l2_resp_valid <= 1'b0;

      if (l2_delay_counter > 0) begin
        l2_delay_counter <= l2_delay_counter - 1;
        if (l2_delay_counter == 1) begin
          l2_resp_valid <= 1'b1;
          l2_resp_rdata <= l2_pending_data;
        end
      end else if (l2_req_valid && l2_ready) begin
        if (l2_req_type == 3'd0) begin  // CACHE_READ
          // Simulate L2 read latency
          l2_pending_data <= l2_memory[l2_req_addr[15:6]];
          l2_delay_counter <= 3;  // 3 cycle L2 latency
          l2_ready <= 1'b0;
        end else begin
          // Writeback - accept immediately
          l2_memory[l2_req_addr[15:6]] <= l2_req_wdata;
          l2_resp_valid <= 1'b1;
        end
      end else begin
        l2_ready <= 1'b1;
      end
    end
  end

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

  // Wait for response
  task automatic wait_response();
    int timeout = 100;
    while (!resp_valid && timeout > 0) begin
      @(posedge clk);
      timeout--;
    end
    if (timeout == 0) $display("  [WARN] Timeout waiting for response");
  endtask

  // Do a cache read
  task automatic do_read(input logic [ADDR_WIDTH-1:0] addr, output logic [DATA_WIDTH-1:0] data, output logic hit);
    @(posedge clk);
    while (!ready) @(posedge clk);

    req_valid <= 1'b1;
    req_we <= 1'b0;
    req_addr <= addr;
    req_byte_en <= 4'hF;
    req_size <= MEM_WORD;

    @(posedge clk);
    req_valid <= 1'b0;

    wait_response();
    data = resp_rdata;
    hit = resp_hit;
    @(posedge clk);
  endtask

  // Do a cache write
  task automatic do_write(input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] data, output logic hit);
    @(posedge clk);
    while (!ready) @(posedge clk);

    req_valid <= 1'b1;
    req_we <= 1'b1;
    req_addr <= addr;
    req_wdata <= data;
    req_byte_en <= 4'hF;
    req_size <= MEM_WORD;

    @(posedge clk);
    req_valid <= 1'b0;

    wait_response();
    hit = resp_hit;
    @(posedge clk);
  endtask

  // Test variables
  logic [DATA_WIDTH-1:0] read_data;
  logic hit;

  initial begin
    $display("\n=== L1 Data Cache Testbench ===\n");

    // Initialize L2 memory with known pattern
    for (int i = 0; i < 1024; i++) begin
      for (int w = 0; w < 16; w++) begin
        l2_memory[i][w*32 +: 32] = (i << 16) | (w << 4) | 32'hA000;
      end
    end

    // Initialize signals
    rst_n = 0;
    req_valid = 0;
    req_we = 0;
    req_addr = 0;
    req_wdata = 0;
    req_byte_en = 0;
    req_size = MEM_WORD;
    flush_req = 0;

    // Reset
    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(5) @(posedge clk);

    // Test 1: Read miss (cold cache)
    $display("Test 1: Read miss (cold cache)");
    do_read(32'h0000_0100, read_data, hit);
    check("Read miss detected", !hit);
    // Address 0x100: line = 0x100/64 = 4, word within line = (0x100 % 64) / 4 = 0
    // Expected: word 0 of line 4 = (4 << 16) | (0 << 4) | 0xA000 = 0x0004A000
    check("Correct data from L2", read_data == 32'h0004_A000);

    // Test 2: Read hit (same line)
    $display("Test 2: Read hit (same line, different word)");
    do_read(32'h0000_0104, read_data, hit);
    check("Read hit detected", hit);
    // Address 0x104: same line 4, word within line = 4/4 = 1
    // Word 1 of line 4 = (4 << 16) | (1 << 4) | 0xA000 = 0x0004A010
    check("Correct data on hit", read_data == 32'h0004_A010);

    // Test 3: Write hit
    $display("Test 3: Write hit");
    do_write(32'h0000_0100, 32'hDEAD_BEEF, hit);
    check("Write hit detected", hit);

    // Verify write
    do_read(32'h0000_0100, read_data, hit);
    check("Write data persisted", read_data == 32'hDEAD_BEEF);

    // Test 4: Write miss (allocate on write)
    $display("Test 4: Write miss (allocate on write)");
    do_write(32'h0000_1000, 32'hCAFE_BABE, hit);
    check("Write miss detected", !hit);

    // Verify write
    do_read(32'h0000_1000, read_data, hit);
    check("Write-allocated data correct", read_data == 32'hCAFE_BABE);

    // Test 5: Multiple cache lines
    $display("Test 5: Access multiple cache lines");
    do_read(32'h0000_0040, read_data, hit);  // Line 1
    check("Line 1 miss", !hit);
    do_read(32'h0000_0080, read_data, hit);  // Line 2
    check("Line 2 miss", !hit);
    do_read(32'h0000_00C0, read_data, hit);  // Line 3
    check("Line 3 miss", !hit);

    // Re-read first line - should hit
    do_read(32'h0000_0044, read_data, hit);  // Line 1, word 1
    check("Line 1 now hits", hit);

    // Test 6: LRU eviction
    $display("Test 6: LRU eviction (fill 4 ways in same set)");
    // Access 4 different lines that map to same set
    // With 32KB cache, 4-way, 64-byte lines: 128 sets
    // Set index = addr[12:6] (7 bits for 128 sets)
    // Lines at 0x0000, 0x2000, 0x4000, 0x6000 map to set 0
    do_read(32'h0000_0000, read_data, hit);  // Way 0
    do_read(32'h0000_2000, read_data, hit);  // Way 1
    do_read(32'h0000_4000, read_data, hit);  // Way 2
    do_read(32'h0000_6000, read_data, hit);  // Way 3

    // Now access a 5th line in same set - should evict oldest
    do_read(32'h0000_8000, read_data, hit);
    check("5th line access causes miss", !hit);

    // Original line at 0x0000 should be evicted
    do_read(32'h0000_0000, read_data, hit);
    check("Evicted line causes miss", !hit);

    // Test 7: Statistics
    $display("Test 7: Statistics");
    check("Hits counter > 0", stats.hits > 0);
    check("Misses counter > 0", stats.misses > 0);
    $display("  Stats: hits=%0d, misses=%0d, writebacks=%0d",
             stats.hits, stats.misses, stats.writebacks);

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
