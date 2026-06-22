/*
 * triad01_lbist.v
 * Logic Built-In Self Test for TRIAD01
 *
 * Implements a standard LBIST architecture:
 *   LFSR  — Linear Feedback Shift Register (16-bit, Galois form)
 *           Generates pseudo-random test stimulus autonomously.
 *           Polynomial: x^16 + x^15 + x^13 + x^4 + 1  (maximal length)
 *
 *   MISR  — Multiple Input Signature Register (16-bit)
 *           Compresses all circuit outputs over N cycles into a
 *           single 16-bit signature. Compare to golden value to
 *           determine pass/fail.
 *
 * Test flow:
 *   1. Assert bist_en=1 (and mode_sel=1 from top)
 *   2. Wait BIST_CYCLES clock cycles
 *   3. Read bist_done=1
 *   4. Read bist_pass=1 (match) or bist_pass=0 (fault detected)
 *
 * Golden signature:
 *   Obtained by running this module in simulation with a known-good
 *   design and reading misr_reg at cycle BIST_CYCLES.
 *   Hardcoded as GOLDEN_SIG below. Update after simulation.
 *
 * LFSR drives: fc_live, rc_live, fc_conf, rc_conf stimulus bits
 *   (bits [3:0] of LFSR) into the DUT during BIST.
 *
 * MISR captures: uo_out[7:0] each cycle, XOR-accumulates into signature.
 *
 * Industry context (Marvell ATE):
 *   This is the on-chip equivalent of an ATE running ATPG patterns.
 *   The LFSR replaces the pattern generator. The MISR replaces the
 *   response compactor. bist_pass replaces the ATE go/no-go output.
 */

`default_nettype none

module triad01_lbist (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bist_en,      // start/enable BIST

    // Captured outputs from DUT to compress
    input  wire [7:0]  dut_out,      // connect to uo_out in top level

    // LFSR stimulus outputs — drive into DUT inputs during BIST
    output wire        bist_fc_live,
    output wire        bist_rc_live,
    output wire        bist_fc_conf,
    output wire        bist_rc_conf,

    // Results
    output reg         bist_done,
    output reg         bist_pass
);

  // Number of cycles to run BIST
  // 256 cycles gives good fault coverage for this design size
  localparam BIST_CYCLES = 9'd256;

  // Golden MISR signature — UPDATE THIS after first simulation run
  // Placeholder: 16'hDEAD — replace with actual simulation output
  localparam GOLDEN_SIG  = 16'hDEAD;

  // 16-bit Galois LFSR
  // Polynomial: x^16 + x^15 + x^13 + x^4 + 1
  // Taps at bits 15, 13, 4 (0-indexed from LSB)
  reg [15:0] lfsr;

  // 16-bit MISR (Multiple Input Signature Register)
  // Each cycle: misr = (misr >> 1) ^ (dut_out XOR feedback)
  // Simplified: misr XORs in new output each cycle with rotation
  reg [15:0] misr;

  // Cycle counter
  reg [8:0]  bist_cnt;

  // Running flag
  reg        bist_running;

  // LFSR update (Galois form — single XOR gate per tap)
  wire lfsr_feedback = lfsr[0];
  wire [15:0] lfsr_next = {1'b0, lfsr[15:1]} ^
                           (lfsr_feedback ? 16'b1010_0000_0001_0001 : 16'b0);
  // Taps: bit15=1, bit13=1, bit4=1, bit0=1 (feedback polynomial)

  // MISR update: rotate right and XOR in captured output
  wire [15:0] misr_next = {misr[0], misr[15:1]} ^ {8'b0, dut_out};

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lfsr         <= 16'hACE1;  // non-zero seed
      misr         <= 16'h0000;
      bist_cnt     <= 9'd0;
      bist_done    <= 1'b0;
      bist_pass    <= 1'b0;
      bist_running <= 1'b0;
    end else begin
      if (bist_en && !bist_running && !bist_done) begin
        // Start BIST
        bist_running <= 1'b1;
        bist_cnt     <= 9'd0;
        lfsr         <= 16'hACE1;
        misr         <= 16'h0000;
        bist_done    <= 1'b0;
        bist_pass    <= 1'b0;
      end else if (bist_running) begin
        // Running — update LFSR, MISR, counter each cycle
        lfsr     <= lfsr_next;
        misr     <= misr_next;
        bist_cnt <= bist_cnt + 9'd1;

        if (bist_cnt >= BIST_CYCLES - 1) begin

          
          // Done — compare MISR to golden signature
          bist_running <= 1'b0;
          bist_done    <= 1'b1;
          bist_pass    <= (misr_next == GOLDEN_SIG) ? 1'b1 : 1'b0;

          // debug print MISR
          $display("TRIAD01 LBIST FINAL MISR = %h", misr_next);
        end
      end else if (!bist_en) begin
        // Reset done flag when bist_en deasserted
        bist_done <= 1'b0;
        // should we reset bist_pass here
      end
    end
  end

  // LFSR bits drive DUT inputs during BIST
  assign bist_fc_live = lfsr[0];
  assign bist_rc_live = lfsr[1];
  assign bist_fc_conf = lfsr[2];
  assign bist_rc_conf = lfsr[3];

endmodule