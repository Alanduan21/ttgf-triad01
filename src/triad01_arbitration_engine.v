/*
 * triad_ternary_engine.v
 * Ternary policy inference engine for TRIAD01
 *
 * Pure combinational lookup over 2-bit scores from input_filter.
 * Implements a fixed ternary weight policy:
 *   RC preferred over FC on tie (human override priority)
 *   DEGRADED + LOW on both channels → SAFE_HOLD
 *
 * Decision encoding:
 *   2'b10 = PRIMARY    (RC controls)
 *   2'b01 = FALLBACK   (FC controls)
 *   2'b00 = SAFE_HOLD  (freeze last command)
 *
 * Score encoding (from input_filter):
 *   2'b10 = HIGH
 *   2'b01 = DEGRADED
 *   2'b00 = LOW
 */

`default_nettype none

module triad01_arbitration_engine (
    input  wire [1:0] fc_score,
    input  wire [1:0] rc_score,
    output reg  [1:0] raw_decision
);

  // Combinational policy table
  always @(*) begin
    casez ({rc_score, fc_score})
      // RC HIGH — always PRIMARY regardless of FC
      4'b10_10: raw_decision = 2'b10; // RC=HIGH,  FC=HIGH
      4'b10_01: raw_decision = 2'b10; // RC=HIGH,  FC=DEGRADED
      4'b10_00: raw_decision = 2'b10; // RC=HIGH,  FC=LOW

      // RC DEGRADED
      4'b01_10: raw_decision = 2'b01; // RC=DEGRADED, FC=HIGH     → FC better
      4'b01_01: raw_decision = 2'b00; // RC=DEGRADED, FC=DEGRADED → neither trusted
      4'b01_00: raw_decision = 2'b00; // RC=DEGRADED, FC=LOW      → neither trusted

      // RC LOW
      4'b00_10: raw_decision = 2'b01; // RC=LOW, FC=HIGH     → fallback to FC
      4'b00_01: raw_decision = 2'b00; // RC=LOW, FC=DEGRADED → safe hold
      4'b00_00: raw_decision = 2'b00; // RC=LOW, FC=LOW      → safe hold

      default:  raw_decision = 2'b00; // defensive default
    endcase
  end

endmodule