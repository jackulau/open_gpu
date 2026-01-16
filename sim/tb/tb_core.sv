// Testbench for OpenGPU core

`timescale 1ns/1ps

module tb_core;
  import pkg_opengpu::*;

  parameter int CLK_PERIOD = 10;
  parameter int TIMEOUT_CYCLES = 10000;

  logic clk, rst_n;
  logic start;
  logic [ADDR_WIDTH-1:0] pc_start;
  logic done, busy;

  logic [DATA_WIDTH-1:0] thread_idx, block_idx, block_dim, grid_dim, warp_idx, lane_idx;

  logic imem_req, imem_valid;
  logic [ADDR_WIDTH-1:0] imem_addr;
  logic [INSTR_WIDTH-1:0] imem_rdata;

  logic dmem_req, dmem_we, dmem_valid;
  logic [ADDR_WIDTH-1:0] dmem_addr;
  logic [DATA_WIDTH-1:0] dmem_wdata, dmem_rdata;
  logic [3:0] dmem_be;

  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  core_top u_core (.*);

  memory_model #(.MEM_SIZE_BYTES(65536)) u_memory (
    .clk(clk), .rst_n(rst_n),
    .imem_req(imem_req), .imem_addr(imem_addr),
    .imem_rdata(imem_rdata), .imem_valid(imem_valid),
    .dmem_req(dmem_req), .dmem_we(dmem_we), .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata), .dmem_be(dmem_be),
    .dmem_rdata(dmem_rdata), .dmem_valid(dmem_valid)
  );

  task reset_dut();
    rst_n = 0; start = 0; pc_start = 0;
    thread_idx = 0; block_idx = 0; block_dim = 256;
    grid_dim = 1; warp_idx = 0; lane_idx = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);
  endtask

  task start_core(input logic [31:0] start_pc = 0);
    pc_start = start_pc;
    start = 1;
    @(posedge clk);
    start = 0;
  endtask

  task wait_done(output int cycles);
    cycles = 0;
    while (!done && cycles < TIMEOUT_CYCLES) begin
      @(posedge clk);
      cycles++;
    end
    if (cycles >= TIMEOUT_CYCLES)
      $display("ERROR: Timeout after %0d cycles", cycles);
  endtask

  // Test: x9 = x7 + x8 = 5 + 3 = 8
  task test_simple();
    int cycles;
    logic [31:0] result;

    $display("\n=== Test: Simple (x7 = 5 + 3 = 8) ===\n");

    for (int i = 0; i < 256; i++) u_memory.mem[i] = 8'h00;

    // ADDI x7, x0, 5:  opcode=0x01, rd=7, rs1=0, imm=5
    {u_memory.mem[3], u_memory.mem[2], u_memory.mem[1], u_memory.mem[0]} = 32'h04E00005;

    // ADDI x8, x0, 3:  opcode=0x01, rd=8, rs1=0, imm=3
    {u_memory.mem[7], u_memory.mem[6], u_memory.mem[5], u_memory.mem[4]} = 32'h05000003;

    // ADD x9, x7, x8:  opcode=0x00, rd=9, rs1=7, rs2=8
    {u_memory.mem[11], u_memory.mem[10], u_memory.mem[9], u_memory.mem[8]} = 32'h01274000;

    // SW x9, 0(x0):    opcode=0x35, rs2=9, rs1=0, offset=0
    {u_memory.mem[15], u_memory.mem[14], u_memory.mem[13], u_memory.mem[12]} = 32'hD5200000;

    // RET:             opcode=0x58 -> 6-bit = 0x18
    {u_memory.mem[19], u_memory.mem[18], u_memory.mem[17], u_memory.mem[16]} = 32'h60000000;

    $display("Loaded instructions:");
    for (int i = 0; i < 5; i++)
      $display("  [%0d]: 0x%08x", i, u_memory.read_word(i*4));

    reset_dut();
    start_core(0);
    wait_done(cycles);

    result = u_memory.read_word(0);
    $display("\nExecuted in %0d cycles", cycles);
    $display("Result at mem[0] = %0d (expected 8)", result);
    $display(result == 8 ? "TEST PASSED!" : "TEST FAILED!");
  endtask

  // Test: 10 + 20 + 12 = 42
  task test_arithmetic();
    int cycles;
    logic [31:0] result;

    $display("\n=== Test: Arithmetic Operations ===\n");

    for (int i = 0; i < 256; i++) u_memory.mem[i] = 8'h00;

    // ADDI x7, x0, 10
    {u_memory.mem[3], u_memory.mem[2], u_memory.mem[1], u_memory.mem[0]} = 32'h04E0_000A;

    // ADDI x8, x0, 20
    {u_memory.mem[7], u_memory.mem[6], u_memory.mem[5], u_memory.mem[4]} = 32'h0500_0014;

    // ADD x9, x7, x8
    {u_memory.mem[11], u_memory.mem[10], u_memory.mem[9], u_memory.mem[8]} = 32'h0127_4000;

    // ADDI x10, x9, 12
    {u_memory.mem[15], u_memory.mem[14], u_memory.mem[13], u_memory.mem[12]} = 32'h0549_000C;

    // SW x10, 0(x0)
    {u_memory.mem[19], u_memory.mem[18], u_memory.mem[17], u_memory.mem[16]} = 32'hD540_0000;

    // RET
    {u_memory.mem[23], u_memory.mem[22], u_memory.mem[21], u_memory.mem[20]} = 32'h6000_0000;

    reset_dut();
    start_core(0);
    wait_done(cycles);

    result = u_memory.read_word(0);
    $display("Executed in %0d cycles", cycles);
    $display("Result at mem[0] = %0d (expected 42)", result);
    $display(result == 42 ? "TEST PASSED!" : "TEST FAILED!");
    u_memory.dump_memory(0, 8);
  endtask

  initial begin
    $display("\n============================================");
    $display("   OpenGPU Core Testbench");
    $display("============================================\n");

    test_simple();
    test_arithmetic();

    $display("\n============================================");
    $display("   All Tests Complete");
    $display("============================================\n");

    #100;
    $finish;
  end

  initial begin
    $dumpfile("tb_core.vcd");
    $dumpvars(0, tb_core);
  end

  initial begin
    #(CLK_PERIOD * TIMEOUT_CYCLES * 10);
    $display("FATAL: Global timeout!");
    $finish;
  end

endmodule
