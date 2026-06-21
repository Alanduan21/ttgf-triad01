/*
 * triad01_scan.v
 * Scan Chain for TRIAD01 DFT
 *
 * Implements muxed scan flip-flops (MSFF) chaining the 8 most important
 * observable state bits into a single shift register:
 *   chain[7:4] = rc_cnt[3:0]   (from input_filter, via top-level port)
 *   chain[3:0] = fc_cnt[3:0]   (from input_filter, via top-level port)
 *
 * The scan FFs capture a snapshot of all internal state, allowing:
 *   - Stuck-at fault detection (shift in known pattern, compare out)
 *   - Internal state initialisation for targeted testing
 *   - Post-silicon debug of internal registers
 *
 *
 * In normal mode (scan_en=0): FFs operate functionally.
 * In scan mode  (scan_en=1): FFs form a shift register for ATPG / debug.
 * scan_in → [FF0] → [FF1] → ... → [FFn] → scan_out
 * Usage: top-level exposes fc_cnt and rc_cnt as scan inputs.
 * The RP2040 on the TT PCB shifts patterns in via scan_in and reads
 * the observable state back via scan_out.
 *
 * Industry context (ATE):
 *   The scan_in pattern is equivalent to an ATPG vector.
 *   scan_out is compared to the expected response.
 *   On the TT PCB, the RP2040 shifts patterns via SPI/GPIO.
 */

`default_nettype none

// Single muxed scan flip-flop
// In functional mode: Q captures D_func each clock
// In scan mode:       Q captures D_scan (shift register)
module triad01_scan_ff (
    input  wire clk,
    input  wire rst_n,
    input  wire scan_en,
    input  wire d_func,    // functional data input
    input  wire d_scan,    // scan chain input (from previous FF)
    output reg  q          // output (to functional logic + next scan FF)
);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      q <= 1'b0;
    else
      q <= scan_en ? d_scan : d_func;
  end

endmodule


// Scan chain wrapper: bundles N scan FFs into a named chain
// This instance wraps the 8 most important state bits for demo:
//   [7:4] fc_cnt[3:0]   from input_filter
//   [3:0] rc_cnt[3:0]   from input_filter
// Plus decision FSM state and MAC outputs as stretch goal
//
// For TT demo: shift 8 bits in, 8 bits out. 
module triad01_scan_chain (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       scan_en,
    input  wire       scan_in,
    output wire       scan_out,

    // Functional data inputs (from actual registers)
    input  wire [3:0] fc_cnt_w,
    input  wire [3:0] rc_cnt_w,

    // Scan-observable outputs (read back internal state)
    // In functional mode these are just wires to internal state.
    // In scan mode they're the shift register taps.
    output wire [3:0] fc_cnt_obs,
    output wire [3:0] rc_cnt_obs
);

  wire [7:0] chain;  // internal scan chain wires

  // FF 0..3: fc_cnt[3:0]
  triad01_scan_ff ff0 (.clk(clk), .rst_n(rst_n), .scan_en(scan_en),
                        .d_func(fc_cnt_w[0]), .d_scan(scan_in),   .q(chain[0]));
  triad01_scan_ff ff1 (.clk(clk), .rst_n(rst_n), .scan_en(scan_en),
                        .d_func(fc_cnt[1]), .d_scan(chain[0]),  .q(chain[1]));
  triad01_scan_ff ff2 (.clk(clk), .rst_n(rst_n), .scan_en(scan_en),
                        .d_func(fc_cnt_w[2]), .d_scan(chain[1]),  .q(chain[2]));
  triad01_scan_ff ff3 (.clk(clk), .rst_n(rst_n), .scan_en(scan_en),
                        .d_func(fc_cnt_w[3]), .d_scan(chain[2]),  .q(chain[3]));

  // FF 4..7: rc_cnt[3:0]
  triad01_scan_ff ff4 (.clk(clk), .rst_n(rst_n), .scan_en(scan_en),
                        .d_func(rc_cnt_w[0]), .d_scan(chain[3]),  .q(chain[4]));
  triad01_scan_ff ff5 (.clk(clk), .rst_n(rst_n), .scan_en(scan_en),
                        .d_func(rc_cnt_w[1]), .d_scan(chain[4]),  .q(chain[5]));
  triad01_scan_ff ff6 (.clk(clk), .rst_n(rst_n), .scan_en(scan_en),
                        .d_func(rc_cnt_w[2]), .d_scan(chain[5]),  .q(chain[6]));
  triad01_scan_ff ff7 (.clk(clk), .rst_n(rst_n), .scan_en(scan_en),
                        .d_func(rc_cnt_w[3]), .d_scan(chain[6]),  .q(chain[7]));

  assign scan_out    = chain[7];
  assign fc_cnt_obs  = chain[3:0];
  assign rc_cnt_obs  = chain[7:4];

endmodule