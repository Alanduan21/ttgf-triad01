/*
 * triad01_scan.v
 * Scan Chain DFT for TRIAD01
 *
 * Implements muxed scan flip-flops (MSFF) chaining the 8 most important
 * observable state bits into a single shift register:
 *   chain[7:4] = rc_cnt[3:0]   (from input_filter, via top-level port)
 *   chain[3:0] = fc_cnt[3:0]   (from input_filter, via top-level port)
 *
 * In normal mode (scan_en=0): FFs operate functionally.
 * In scan mode  (scan_en=1): FFs form a shift register for ATPG / debug.
 *
 * Usage: top-level exposes fc_cnt and rc_cnt as scan inputs.
 * The RP2040 on the TT PCB shifts patterns in via scan_in and reads
 * the observable state back via scan_out.
 *
 * Industry context (Marvell ATE):
 *   scan_in pattern = ATPG vector
 *   scan_out = expected response
 *   On silicon, the RP2040 drives scan_in via GPIO and checks scan_out.
 */

`default_nettype none

// Single muxed scan flip-flop
module triad01_scan_ff (
    input  wire clk,
    input  wire rst_n,
    input  wire scan_en,
    input  wire d_func,
    input  wire d_scan,
    output reg  q
);
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      q <= 1'b0;
    else
      q <= scan_en ? d_scan : d_func;
  end
endmodule


// Scan chain wrapper: 8 FFs covering fc_cnt[3:0] and rc_cnt[3:0]
module triad01_scan_chain (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       scan_en,
    input  wire       scan_in,
    output wire       scan_out,

    // Functional data inputs (wired to actual registers in top)
    input  wire [3:0] fc_cnt,
    input  wire [3:0] rc_cnt,

    // Scan-observable outputs
    output wire [3:0] fc_cnt_obs,
    output wire [3:0] rc_cnt_obs
);

  wire [7:0] chain;

  // FF 0..3: fc_cnt[3:0]
  triad01_scan_ff ff0 (.clk(clk), .rst_n(rst_n), .scan_en(scan_en),
                        .d_func(fc_cnt[0]), .d_scan(scan_in),  .q(chain[0]));
  triad01_scan_ff ff1 (.clk(clk), .rst_n(rst_n), .scan_en(scan_en),
                        .d_func(fc_cnt[1]), .d_scan(chain[0]), .q(chain[1]));
  triad01_scan_ff ff2 (.clk(clk), .rst_n(rst_n), .scan_en(scan_en),
                        .d_func(fc_cnt[2]), .d_scan(chain[1]), .q(chain[2]));
  triad01_scan_ff ff3 (.clk(clk), .rst_n(rst_n), .scan_en(scan_en),
                        .d_func(fc_cnt[3]), .d_scan(chain[2]), .q(chain[3]));

  // FF 4..7: rc_cnt[3:0]
  triad01_scan_ff ff4 (.clk(clk), .rst_n(rst_n), .scan_en(scan_en),
                        .d_func(rc_cnt[0]), .d_scan(chain[3]), .q(chain[4]));
  triad01_scan_ff ff5 (.clk(clk), .rst_n(rst_n), .scan_en(scan_en),
                        .d_func(rc_cnt[1]), .d_scan(chain[4]), .q(chain[5]));
  triad01_scan_ff ff6 (.clk(clk), .rst_n(rst_n), .scan_en(scan_en),
                        .d_func(rc_cnt[2]), .d_scan(chain[5]), .q(chain[6]));
  triad01_scan_ff ff7 (.clk(clk), .rst_n(rst_n), .scan_en(scan_en),
                        .d_func(rc_cnt[3]), .d_scan(chain[6]), .q(chain[7]));

  assign scan_out   = chain[7];
  assign fc_cnt_obs = chain[3:0];
  assign rc_cnt_obs = chain[7:4];

endmodule