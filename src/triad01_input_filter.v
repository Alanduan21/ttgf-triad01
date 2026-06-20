/*
 * triad_input_filter.v
 * Temporal confidence filter for TRIAD01
 *
 * Per-channel 4-bit up/down counter.
 * Increments when signal is live AND confident.
 * Decrements when signal is absent or low confidence.
 * Outputs a 2-bit score: HIGH / DEGRADED / LOW
 *
 * Score encoding:
 *   2'b10 = HIGH      (counter >= 12)
 *   2'b01 = DEGRADED  (counter 6..11)
 *   2'b00 = LOW       (counter <= 5)
 */
 
`default_nettype none

module triad_input_filter (
    input wire clk;
    input wire rst_n;

    // raw health inputs
    input wire fc_live,
    input  wire rc_live,   // RC signal present
    input  wire fc_conf,   // FC confidence qualifier
    input  wire rc_conf,   // RC confidence qualifier

    // 2-bit confidence scores out
    output wire [1:0] fc_score,
    output wire [1:0] rc_score
);

// 4-bit counters, range 0..15
  reg [3:0] fc_cnt;
  reg [3:0] rc_cnt;
 
  // Combined health input: both live AND confident required
  wire fc_input = fc_live & fc_conf;
  wire rc_input = rc_live & rc_conf;
 
  // FC counter
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fc_cnt <= 4'd0;
    end else begin
      if (fc_input && fc_cnt < 4'd15)
        fc_cnt <= fc_cnt + 4'd1;
      else if (!fc_input && fc_cnt > 4'd0)
        fc_cnt <= fc_cnt - 4'd1;
    end
  end
 
  // RC counter
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rc_cnt <= 4'd0;
    end else begin
      if (rc_input && rc_cnt < 4'd15)
        rc_cnt <= rc_cnt + 4'd1;
      else if (!rc_input && rc_cnt > 4'd0)
        rc_cnt <= rc_cnt - 4'd1;
    end
  end
 
  // Score thresholds
  // HIGH:     >= 12
  // DEGRADED: 6..11
  // LOW:      <= 5
  assign fc_score = (fc_cnt >= 4'd12) ? 2'b10 :
                    (fc_cnt >= 4'd6)  ? 2'b01 :
                                        2'b00;
 
  assign rc_score = (rc_cnt >= 4'd12) ? 2'b10 :
                    (rc_cnt >= 4'd6)  ? 2'b01 :
                                        2'b00;
 
endmodule