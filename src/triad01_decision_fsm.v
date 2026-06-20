/*
 * triad_decision_fsm.v
 * Hysteresis FSM for TRIAD01
 *
 * Prevents output thrashing by requiring raw_decision
 * to be stable for STABLE_THRESH consecutive cycles
 * before committing to a new output state.
 *
 * decision_valid goes HIGH once the output has stabilised
 * and stays HIGH until a new transition begins.
 *
 * Decision encoding:
 *   2'b10 = PRIMARY
 *   2'b01 = FALLBACK
 *   2'b00 = SAFE_HOLD
 */

`default_nettype none

module triad_decision_fsm (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [1:0] raw_decision,
    output reg  [1:0] decision,
    output reg        decision_valid
);

  // Number of consecutive stable cycles before committing
  localparam STABLE_THRESH = 4'd8;

  reg [3:0] stable_cnt;
  reg [1:0] candidate;   // decision we are evaluating

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      decision       <= 2'b00;  // SAFE_HOLD on reset
      decision_valid <= 1'b0;
      stable_cnt     <= 4'd0;
      candidate      <= 2'b00;
    end else begin
      if (raw_decision == candidate) begin
        // Candidate is holding — increment stability counter
        if (stable_cnt < STABLE_THRESH) begin
          stable_cnt <= stable_cnt + 4'd1;
        end
        // Commit once threshold reached
        if (stable_cnt >= STABLE_THRESH) begin
          decision       <= candidate;
          decision_valid <= 1'b1;
        end
      end else begin
        // New candidate appeared — restart evaluation
        candidate      <= raw_decision;
        stable_cnt     <= 4'd0;
        decision_valid <= 1'b0;
      end
    end
  end

endmodule