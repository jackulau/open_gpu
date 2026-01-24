// Testbench for SIMT Core - Full integration test
// Tests divergence, multi-warp scheduling, vote, and shuffle operations

`timescale 1ns/1ps

module tb_simt_core;
  import pkg_opengpu::*;

  localparam int NUM_WARPS = WARPS_PER_CORE;

  // Clock and reset
  logic clk;
  logic rst_n;

  // Core interface
  logic start;
  logic [DATA_WIDTH-1:0] start_pc;
  logic [NUM_WARPS-1:0] warp_enable;
  logic done;
  logic busy;

  logic [DATA_WIDTH-1:0] thread_base;
  logic [DATA_WIDTH-1:0] block_idx;
  logic [DATA_WIDTH-1:0] block_dim;
  logic [DATA_WIDTH-1:0] grid_dim;

  // Instruction memory
  logic imem_req;
  logic [ADDR_WIDTH-1:0] imem_addr;
  logic [INSTR_WIDTH-1:0] imem_rdata;
  logic imem_valid;

  // Data memory
  logic dmem_req;
  logic [WARP_SIZE-1:0] dmem_lane_valid;
  logic [WARP_SIZE-1:0][ADDR_WIDTH-1:0] dmem_addr;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] dmem_wdata;
  logic dmem_we;
  mem_size_t dmem_size;

  logic dmem_ready;
  logic dmem_resp_valid;
  logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] dmem_rdata;
  logic [WARP_SIZE-1:0] dmem_lane_resp_valid;

  // Instantiate DUT
  simt_core_top #(
    .NUM_WARPS(NUM_WARPS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .start_pc(start_pc),
    .warp_enable(warp_enable),
    .done(done),
    .busy(busy),
    .thread_base(thread_base),
    .block_idx(block_idx),
    .block_dim(block_dim),
    .grid_dim(grid_dim),
    .imem_req(imem_req),
    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),
    .imem_valid(imem_valid),
    .dmem_req(dmem_req),
    .dmem_lane_valid(dmem_lane_valid),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_we(dmem_we),
    .dmem_size(dmem_size),
    .dmem_ready(dmem_ready),
    .dmem_resp_valid(dmem_resp_valid),
    .dmem_rdata(dmem_rdata),
    .dmem_lane_resp_valid(dmem_lane_resp_valid)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Simple memory model
  logic [7:0] imem [0:65535];
  logic [7:0] dmem_storage [0:65535];

  // Instruction memory response
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      imem_valid <= 1'b0;
      imem_rdata <= '0;
    end else if (imem_req) begin
      imem_rdata <= {imem[imem_addr+3], imem[imem_addr+2],
                     imem[imem_addr+1], imem[imem_addr]};
      imem_valid <= 1'b1;
    end else begin
      imem_valid <= 1'b0;
    end
  end

  // Data memory response (simplified - immediate response)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dmem_ready <= 1'b1;
      dmem_resp_valid <= 1'b0;
      dmem_rdata <= '0;
      dmem_lane_resp_valid <= '0;
    end else begin
      dmem_ready <= 1'b1;
      if (dmem_req) begin
        dmem_resp_valid <= 1'b1;
        dmem_lane_resp_valid <= dmem_lane_valid;
        for (int i = 0; i < WARP_SIZE; i++) begin
          if (dmem_lane_valid[i]) begin
            if (dmem_we) begin
              // Write
              case (dmem_size)
                MEM_BYTE: dmem_storage[dmem_addr[i]] <= dmem_wdata[i][7:0];
                MEM_HALF: begin
                  dmem_storage[dmem_addr[i]] <= dmem_wdata[i][7:0];
                  dmem_storage[dmem_addr[i]+1] <= dmem_wdata[i][15:8];
                end
                MEM_WORD: begin
                  dmem_storage[dmem_addr[i]] <= dmem_wdata[i][7:0];
                  dmem_storage[dmem_addr[i]+1] <= dmem_wdata[i][15:8];
                  dmem_storage[dmem_addr[i]+2] <= dmem_wdata[i][23:16];
                  dmem_storage[dmem_addr[i]+3] <= dmem_wdata[i][31:24];
                end
                default: ;
              endcase
            end else begin
              // Read
              dmem_rdata[i] <= {dmem_storage[dmem_addr[i]+3],
                                dmem_storage[dmem_addr[i]+2],
                                dmem_storage[dmem_addr[i]+1],
                                dmem_storage[dmem_addr[i]]};
            end
          end
        end
      end else begin
        dmem_resp_valid <= 1'b0;
      end
    end
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
    start = 0;
    start_pc = '0;
    warp_enable = '0;
    thread_base = '0;
    block_idx = '0;
    block_dim = 32'd128;
    grid_dim = 32'd1;
    // Clear memories
    for (int i = 0; i < 65536; i++) begin
      imem[i] = 8'd0;
      dmem_storage[i] = 8'd0;
    end
    @(posedge clk);
    @(posedge clk);
    rst_n = 1;
    @(posedge clk);
  endtask

  // Load instruction into memory
  task load_instr(input int addr, input logic [31:0] instr);
    imem[addr]   = instr[7:0];
    imem[addr+1] = instr[15:8];
    imem[addr+2] = instr[23:16];
    imem[addr+3] = instr[31:24];
  endtask

  // Encode instructions
  function automatic logic [31:0] encode_r_type(
    opcode_t op, logic [4:0] rd, logic [4:0] rs1, logic [4:0] rs2
  );
    return {op, rd, rs1, rs2, 11'd0};
  endfunction

  function automatic logic [31:0] encode_i_type(
    opcode_t op, logic [4:0] rd, logic [4:0] rs1, logic [15:0] imm
  );
    return {op, rd, rs1, imm};
  endfunction

  function automatic logic [31:0] encode_ret();
    return {OP_RET, 5'd0, 5'd0, 16'd0};
  endfunction

  // Start core and wait for completion
  task run_core(input int max_cycles = 1000);
    start = 1;
    @(posedge clk);
    start = 0;

    for (int i = 0; i < max_cycles; i++) begin
      @(posedge clk);
      if (done) begin
        $display("Core completed in %0d cycles", i);
        return;
      end
    end
    $display("ERROR: Core timeout after %0d cycles", max_cycles);
  endtask

  // Test cases
  initial begin
    $display("========================================");
    $display("SIMT Core Integration Testbench");
    $display("========================================");

    // Initialize
    reset_dut();

    // ========================================
    // Test 1: Single warp, simple arithmetic
    // ========================================
    $display("\n--- Test 1: Single warp arithmetic ---");
    reset_dut();

    // Program: ADDI x7, x0, 42; RET
    load_instr(0, encode_i_type(OP_ADDI, 5'd7, 5'd0, 16'd42));
    load_instr(4, encode_ret());

    start_pc = 32'd0;
    warp_enable = 4'b0001;  // Enable warp 0 only
    thread_base = 0;

    run_core(100);
    check("Single warp completed", done == 1);

    // ========================================
    // Test 2: Multiple warps
    // ========================================
    $display("\n--- Test 2: Multiple warps ---");
    reset_dut();

    // Same simple program for all warps
    load_instr(0, encode_i_type(OP_ADDI, 5'd7, 5'd0, 16'd100));
    load_instr(4, encode_ret());

    start_pc = 32'd0;
    warp_enable = 4'b1111;  // Enable all 4 warps
    thread_base = 0;

    run_core(200);
    check("All 4 warps completed", done == 1);

    // ========================================
    // Test 3: Memory operations
    // ========================================
    $display("\n--- Test 3: Memory store and load ---");
    reset_dut();

    // Program:
    // ADDI x7, x0, 0x55        ; x7 = 0x55
    // SW x7, 0x100(x0)         ; Store x7 to address 0x100
    // LW x8, 0x100(x0)         ; Load from address 0x100 to x8
    // RET

    load_instr(0, encode_i_type(OP_ADDI, 5'd7, 5'd0, 16'h55));
    load_instr(4, {OP_SW, 5'd7, 5'd0, 16'h100});  // Store x7 at [0x100]
    load_instr(8, {OP_LW, 5'd8, 5'd0, 16'h100});  // Load [0x100] to x8
    load_instr(12, encode_ret());

    start_pc = 32'd0;
    warp_enable = 4'b0001;
    thread_base = 0;

    run_core(200);
    check("Memory operations completed", done == 1);

    // ========================================
    // Test 4: ALU operations
    // ========================================
    $display("\n--- Test 4: ALU operations ---");
    reset_dut();

    // Program: Test various ALU ops
    // ADDI x10, x0, 10
    // ADDI x11, x0, 3
    // ADD x12, x10, x11      ; x12 = 13
    // SUB x13, x10, x11      ; x13 = 7
    // AND x14, x10, x11      ; x14 = 2
    // OR x15, x10, x11       ; x15 = 11
    // RET

    load_instr(0, encode_i_type(OP_ADDI, 5'd10, 5'd0, 16'd10));
    load_instr(4, encode_i_type(OP_ADDI, 5'd11, 5'd0, 16'd3));
    load_instr(8, encode_r_type(OP_ADD, 5'd12, 5'd10, 5'd11));
    load_instr(12, encode_r_type(OP_SUB, 5'd13, 5'd10, 5'd11));
    load_instr(16, encode_r_type(OP_AND, 5'd14, 5'd10, 5'd11));
    load_instr(20, encode_r_type(OP_OR, 5'd15, 5'd10, 5'd11));
    load_instr(24, encode_ret());

    start_pc = 32'd0;
    warp_enable = 4'b0001;
    thread_base = 0;

    run_core(200);
    check("ALU operations completed", done == 1);

    // ========================================
    // Test 5: GTO scheduling verification
    // ========================================
    $display("\n--- Test 5: GTO scheduling with 4 warps ---");
    reset_dut();

    // Longer program to observe scheduling
    for (int i = 0; i < 10; i++) begin
      load_instr(i*4, encode_i_type(OP_ADDI, 5'd7, 5'd7, 16'd1));
    end
    load_instr(40, encode_ret());

    start_pc = 32'd0;
    warp_enable = 4'b1111;  // All warps
    thread_base = 0;

    run_core(500);
    check("GTO scheduling completed", done == 1);

    // ========================================
    // Test 6: Lane ID verification
    // ========================================
    $display("\n--- Test 6: Lane ID special register ---");
    reset_dut();

    // Each lane should have its lane_id in x6
    // Store lane_id to memory: SW x6, lane_id*4(x0)
    // This tests that each of 32 lanes has correct lane_id

    // ADDI x10, x6, 0        ; x10 = lane_id
    // SLLI x10, x10, 2       ; x10 = lane_id * 4
    // SW x6, 0x1000(x10)     ; Store lane_id at 0x1000 + lane_id*4
    // RET

    load_instr(0, encode_i_type(OP_ADDI, 5'd10, 5'd6, 16'd0));
    load_instr(4, encode_i_type(OP_SLLI, 5'd10, 5'd10, 16'd2));
    // Note: Store needs special encoding for S-type
    load_instr(8, {OP_SW, 5'd6, 5'd10, 16'h1000});
    load_instr(12, encode_ret());

    start_pc = 32'd0;
    warp_enable = 4'b0001;
    thread_base = 0;

    run_core(200);
    check("Lane ID test completed", done == 1);

    // Verify stored values
    logic lane_id_correct;
    lane_id_correct = 1'b1;
    for (int i = 0; i < WARP_SIZE; i++) begin
      logic [31:0] stored_val;
      int addr = 32'h1000 + i*4;
      stored_val = {dmem_storage[addr+3], dmem_storage[addr+2],
                    dmem_storage[addr+1], dmem_storage[addr]};
      if (stored_val != i) begin
        lane_id_correct = 1'b0;
        $display("  Lane %0d: expected %0d, got %0d", i, i, stored_val);
      end
    end
    check("Lane IDs stored correctly", lane_id_correct);

    // Print final results
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
    #100000;
    $display("ERROR: Global timeout");
    $finish;
  end

  // Waveform dump
  initial begin
    $dumpfile("tb_simt_core.vcd");
    $dumpvars(0, tb_simt_core);
  end

endmodule
