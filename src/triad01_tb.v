/*
 * tb_triad01.v — TRIAD01 Testbench
 *
 * Tests all 6 scenarios from the truth table:
 *   T1: Normal operation — both RC and FC healthy → PRIMARY
 *   T2: RC loss          — RC drops, FC alive     → FALLBACK
 *   T3: FC also lost     — both gone              → SAFE_HOLD
 *   T4: RC recovers      — RC comes back          → PRIMARY
 *   T5: RC flicker       — RC drops for 3 cycles  → no change
 *   T6: Reset            — rst_n=0                → SAFE_HOLD, valid=0
 *
 * Run on EDA Playground: select Icarus Verilog 12, enable VCD dump.
 * Or in Vivado: add all src .v files + this testbench, run simulation.
 */

`default_nettype none
`timescale 1ns/1ps

module tb_triad01;

  // DUT signals
  reg  [7:0] ui_in;
  wire [7:0] uo_out;
  reg  [7:0] uio_in;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  reg        ena;
  reg        clk;
  reg        rst_n;

  // Readable aliases for outputs
  wire [1:0] decision       = uo_out[1:0];
  wire       decision_valid = uo_out[2];
  wire [1:0] fc_score       = uo_out[4:3];
  wire [1:0] rc_score       = uo_out[6:5];
  wire [1:0] raw_decision   = uio_out[1:0];

  // Decision encoding for display
  // 2'b10 = PRIMARY, 2'b01 = FALLBACK, 2'b00 = SAFE_HOLD

  // DUT instantiation
  tt_um_Alanduan21_triad01_top dut (
      .ui_in   (ui_in),
      .uo_out  (uo_out),
      .uio_in  (uio_in),
      .uio_out (uio_out),
      .uio_oe  (uio_oe),
      .ena     (ena),
      .clk     (clk),
      .rst_n   (rst_n)
  );

  // 10ns clock period (100 MHz)
  initial clk = 0;
  always #5 clk = ~clk;

  // VCD dump for waveform viewing
  initial begin
    $dumpfile("triad01.vcd");
    $dumpvars(0, tb_triad01);
  end

  // Helper task: apply inputs and wait N cycles
  task apply_inputs;
    input fc_l, rc_l, fc_c, rc_c;
    input integer cycles;
    begin
      ui_in[0] = fc_l;
      ui_in[1] = rc_l;
      ui_in[2] = fc_c;
      ui_in[3] = rc_c;
      repeat(cycles) @(posedge clk);
      #1; // small delay to let outputs settle after posedge
    end
  endtask

  // Helper task: print current state
  task print_state;
    input [63:0] label; // unused in basic iverilog, use $display directly
    begin
      $display("  fc_score=%b rc_score=%b raw=%b | decision=%b valid=%b",
               fc_score, rc_score, raw_decision, decision, decision_valid);
    end
  endtask

  // Helper task: check expected decision
  task check;
    input [1:0] expected_decision;
    input       expected_valid;
    begin
      if (decision !== expected_decision || decision_valid !== expected_valid) begin
        $display("  FAIL: got decision=%b valid=%b, expected decision=%b valid=%b",
                 decision, decision_valid, expected_decision, expected_valid);
      end else begin
        $display("  PASS: decision=%b valid=%b", decision, decision_valid);
      end
    end
  endtask

  integer i;

  initial begin
    // Initialise
    ena    = 1;
    ui_in  = 8'h00;
    uio_in = 8'h00;
    rst_n  = 0;

    // -------------------------------------------------------
    // T6: Reset behaviour (test first so we start clean)
    // -------------------------------------------------------
    $display("\n=== T6: Reset ===");
    repeat(3) @(posedge clk);
    #1;
    $display("  During reset:");
    print_state(0);
    check(2'b00, 1'b0);  // SAFE_HOLD, not valid

    // Release reset
    @(posedge clk); rst_n = 1;

    // -------------------------------------------------------
    // T1: Normal operation — both RC and FC healthy
    // Expected: PRIMARY (2'b10) after ~25 cycles
    // -------------------------------------------------------
    $display("\n=== T1: Both healthy → PRIMARY ===");
    // fc_live=1, rc_live=1, fc_conf=1, rc_conf=1
    apply_inputs(1, 1, 1, 1, 30);
    $display("  After 30 cycles:");
    print_state(0);
    check(2'b10, 1'b1);

    // -------------------------------------------------------
    // T5: RC flicker — drops for only 3 cycles
    // Expected: no change, still PRIMARY
    // -------------------------------------------------------
    $display("\n=== T5: RC flicker (3 cycles) → still PRIMARY ===");
    apply_inputs(1, 0, 1, 0, 3);   // RC drops briefly
    apply_inputs(1, 1, 1, 1, 5);   // RC recovers
    $display("  After flicker + recovery:");
    print_state(0);
    // rc_cnt only dropped from 15 by 3, now at 12 — still HIGH
    // decision should remain PRIMARY
    check(2'b10, 1'b1);

    // -------------------------------------------------------
    // T2: RC loss — RC drops, FC stays alive
    // Expected: FALLBACK (2'b01) after ~23 cycles
    // -------------------------------------------------------
    $display("\n=== T2: RC loss → FALLBACK ===");
    apply_inputs(1, 0, 1, 0, 30);  // RC gone, FC alive
    $display("  After 30 cycles:");
    print_state(0);
    check(2'b01, 1'b1);

    // -------------------------------------------------------
    // T3: FC also lost — both channels gone
    // Expected: SAFE_HOLD (2'b00) after ~23 cycles
    // -------------------------------------------------------
    $display("\n=== T3: Both lost → SAFE_HOLD ===");
    apply_inputs(0, 0, 0, 0, 30);  // both gone
    $display("  After 30 cycles:");
    print_state(0);
    check(2'b00, 1'b1);

    // -------------------------------------------------------
    // T4: RC recovers — both channels come back healthy
    // Expected: PRIMARY (2'b10) after ~23 cycles
    // -------------------------------------------------------
    $display("\n=== T4: RC recovers → PRIMARY ===");
    apply_inputs(1, 1, 1, 1, 30);
    $display("  After 30 cycles:");
    print_state(0);
    check(2'b10, 1'b1);

    // -------------------------------------------------------
    // Bonus: Watch intermediate scores during RC drain
    // -------------------------------------------------------
    $display("\n=== BONUS: RC drain over time (observe score transitions) ===");
    // RC was at 15, drop it and watch every 4 cycles
    apply_inputs(1, 0, 1, 0, 1);
    for (i = 0; i < 12; i = i + 1) begin
      apply_inputs(1, 0, 1, 0, 2);
      $display("  cycle ~%0d: rc_score=%b fc_score=%b decision=%b valid=%b",
               i*2, rc_score, fc_score, decision, decision_valid);
    end

    $display("\n=== All tests complete ===\n");
    $finish;
  end

  // Timeout watchdog
  initial begin
    #100000;
    $display("TIMEOUT: simulation exceeded limit");
    $finish;
  end

endmodule