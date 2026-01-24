// Testbench for Forwarding Unit
// Tests data forwarding priority and correctness

`timescale 1ns/1ps

module tb_forwarding_unit;
  import pkg_opengpu::*;

  localparam int NUM_WARPS = 4;

  // Current instruction
  logic [WARP_ID_WIDTH-1:0] decode_warp_id;
  logic [REG_ADDR_WIDTH-1:0] decode_rs1, decode_rs2, decode_rs3;

  // Register file data
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rf_rs1_data, rf_rs2_data, rf_rs3_data;

  // Execute stage
  logic ex_valid;
  logic [WARP_ID_WIDTH-1:0] ex_warp_id;
  logic [REG_ADDR_WIDTH-1:0] ex_rd;
  logic ex_reg_write;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] ex_result;

  // Memory stage
  logic mem_valid;
  logic [WARP_ID_WIDTH-1:0] mem_warp_id;
  logic [REG_ADDR_WIDTH-1:0] mem_rd;
  logic mem_reg_write;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] mem_result;

  // Writeback stage
  logic wb_valid;
  logic [WARP_ID_WIDTH-1:0] wb_warp_id;
  logic [REG_ADDR_WIDTH-1:0] wb_rd;
  logic wb_reg_write;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] wb_result;

  // Outputs
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] fwd_rs1_data, fwd_rs2_data, fwd_rs3_data;
  logic [1:0] fwd_rs1_src, fwd_rs2_src, fwd_rs3_src;

  // Instantiate DUT
  forwarding_unit #(
    .NUM_WARPS(NUM_WARPS)
  ) dut (.*);

  // Test counters
  int tests_passed = 0;
  int tests_failed = 0;

  task check(string name, logic condition);
    if (condition) begin
      $display("[PASS] %s", name);
      tests_passed++;
    end else begin
      $display("[FAIL] %s", name);
      tests_failed++;
    end
  endtask

  task reset_signals();
    decode_warp_id = 0;
    decode_rs1 = 0;
    decode_rs2 = 0;
    decode_rs3 = 0;

    // Initialize RF data with known values
    for (int i = 0; i < WARP_SIZE; i++) begin
      rf_rs1_data[i] = 32'hAA111111;
      rf_rs2_data[i] = 32'hAA222222;
      rf_rs3_data[i] = 32'hAA333333;
    end

    ex_valid = 0;
    ex_warp_id = 0;
    ex_rd = 0;
    ex_reg_write = 0;
    for (int i = 0; i < WARP_SIZE; i++) ex_result[i] = 32'hEEEEAAAA;

    mem_valid = 0;
    mem_warp_id = 0;
    mem_rd = 0;
    mem_reg_write = 0;
    for (int i = 0; i < WARP_SIZE; i++) mem_result[i] = 32'hBBBBBBBB;

    wb_valid = 0;
    wb_warp_id = 0;
    wb_rd = 0;
    wb_reg_write = 0;
    for (int i = 0; i < WARP_SIZE; i++) wb_result[i] = 32'hCCCCCCCC;

    #10;  // Allow combinational logic to settle
  endtask

  initial begin
    $display("========================================");
    $display("Forwarding Unit Testbench");
    $display("========================================");

    // ========================================
    // Test 1: No forwarding (use RF data)
    // ========================================
    $display("\n--- Test 1: No forwarding ---");
    reset_signals();

    decode_warp_id = 0;
    decode_rs1 = 5'd10;
    decode_rs2 = 5'd11;
    decode_rs3 = 5'd12;

    #10;
    check("RS1 from register file", fwd_rs1_data[0] == 32'hAA111111);
    check("RS1 source is RF", fwd_rs1_src == 2'd0);
    check("RS2 from register file", fwd_rs2_data[0] == 32'hAA222222);
    check("RS3 from register file", fwd_rs3_data[0] == 32'hAA333333);

    // ========================================
    // Test 2: Forward from EX stage
    // ========================================
    $display("\n--- Test 2: Forward from EX ---");
    reset_signals();

    decode_warp_id = 0;
    decode_rs1 = 5'd10;

    ex_valid = 1;
    ex_warp_id = 0;
    ex_rd = 5'd10;
    ex_reg_write = 1;

    #10;
    check("RS1 forwarded from EX", fwd_rs1_data[0] == 32'hEEEEAAAA);
    check("RS1 source is EX", fwd_rs1_src == 2'd1);

    // ========================================
    // Test 3: Forward from MEM stage
    // ========================================
    $display("\n--- Test 3: Forward from MEM ---");
    reset_signals();

    decode_warp_id = 0;
    decode_rs1 = 5'd15;

    mem_valid = 1;
    mem_warp_id = 0;
    mem_rd = 5'd15;
    mem_reg_write = 1;

    #10;
    check("RS1 forwarded from MEM", fwd_rs1_data[0] == 32'hBBBBBBBB);
    check("RS1 source is MEM", fwd_rs1_src == 2'd2);

    // ========================================
    // Test 4: Forward from WB stage
    // ========================================
    $display("\n--- Test 4: Forward from WB ---");
    reset_signals();

    decode_warp_id = 0;
    decode_rs1 = 5'd20;

    wb_valid = 1;
    wb_warp_id = 0;
    wb_rd = 5'd20;
    wb_reg_write = 1;

    #10;
    check("RS1 forwarded from WB", fwd_rs1_data[0] == 32'hCCCCCCCC);
    check("RS1 source is WB", fwd_rs1_src == 2'd3);

    // ========================================
    // Test 5: Priority EX > MEM > WB
    // ========================================
    $display("\n--- Test 5: Priority test (EX > MEM > WB) ---");
    reset_signals();

    decode_warp_id = 0;
    decode_rs1 = 5'd10;

    // All stages have same register
    ex_valid = 1;
    ex_warp_id = 0;
    ex_rd = 5'd10;
    ex_reg_write = 1;

    mem_valid = 1;
    mem_warp_id = 0;
    mem_rd = 5'd10;
    mem_reg_write = 1;

    wb_valid = 1;
    wb_warp_id = 0;
    wb_rd = 5'd10;
    wb_reg_write = 1;

    #10;
    check("EX has priority", fwd_rs1_data[0] == 32'hEEEEAAAA);
    check("Source is EX", fwd_rs1_src == 2'd1);

    // Disable EX, check MEM has priority
    ex_valid = 0;
    #10;
    check("MEM has priority when EX disabled", fwd_rs1_data[0] == 32'hBBBBBBBB);
    check("Source is MEM", fwd_rs1_src == 2'd2);

    // Disable MEM, check WB has priority
    mem_valid = 0;
    #10;
    check("WB has priority when MEM disabled", fwd_rs1_data[0] == 32'hCCCCCCCC);
    check("Source is WB", fwd_rs1_src == 2'd3);

    // ========================================
    // Test 6: Different warps no forwarding
    // ========================================
    $display("\n--- Test 6: Different warps ---");
    reset_signals();

    decode_warp_id = 0;
    decode_rs1 = 5'd10;

    ex_valid = 1;
    ex_warp_id = 1;  // Different warp
    ex_rd = 5'd10;
    ex_reg_write = 1;

    #10;
    check("No forwarding from different warp", fwd_rs1_data[0] == 32'hAA111111);
    check("Source is RF", fwd_rs1_src == 2'd0);

    // ========================================
    // Test 7: x0 never forwarded
    // ========================================
    $display("\n--- Test 7: x0 uses register file ---");
    reset_signals();

    decode_warp_id = 0;
    decode_rs1 = 5'd0;  // x0

    ex_valid = 1;
    ex_warp_id = 0;
    ex_rd = 5'd0;
    ex_reg_write = 1;

    #10;
    check("x0 uses RF (not forwarded)", fwd_rs1_src == 2'd0);

    // ========================================
    // Test 8: Multiple source registers
    // ========================================
    $display("\n--- Test 8: Multiple source registers ---");
    reset_signals();

    decode_warp_id = 0;
    decode_rs1 = 5'd10;
    decode_rs2 = 5'd11;
    decode_rs3 = 5'd12;

    // RS1 from EX
    ex_valid = 1;
    ex_warp_id = 0;
    ex_rd = 5'd10;
    ex_reg_write = 1;

    // RS2 from MEM
    mem_valid = 1;
    mem_warp_id = 0;
    mem_rd = 5'd11;
    mem_reg_write = 1;

    // RS3 from WB
    wb_valid = 1;
    wb_warp_id = 0;
    wb_rd = 5'd12;
    wb_reg_write = 1;

    #10;
    check("RS1 from EX", fwd_rs1_data[0] == 32'hEEEEAAAA);
    check("RS2 from MEM", fwd_rs2_data[0] == 32'hBBBBBBBB);
    check("RS3 from WB", fwd_rs3_data[0] == 32'hCCCCCCCC);

    // ========================================
    // Test 9: reg_write must be set
    // ========================================
    $display("\n--- Test 9: reg_write required ---");
    reset_signals();

    decode_warp_id = 0;
    decode_rs1 = 5'd10;

    ex_valid = 1;
    ex_warp_id = 0;
    ex_rd = 5'd10;
    ex_reg_write = 0;  // Not writing!

    #10;
    check("No forwarding without reg_write", fwd_rs1_src == 2'd0);

    // Print results
    $display("\n========================================");
    $display("Test Results: %0d passed, %0d failed", tests_passed, tests_failed);
    $display("========================================");

    if (tests_failed == 0)
      $display("ALL TESTS PASSED");
    else
      $display("SOME TESTS FAILED");

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
    $dumpfile("tb_forwarding_unit.vcd");
    $dumpvars(0, tb_forwarding_unit);
  end

endmodule
