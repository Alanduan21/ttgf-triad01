/*
 * triad01_pwm_memory.v
 * PWM History Memory for TRIAD-SAFE
 *
 * Maintains a 3-deep shift register of the last three valid PWM
 * pulse-width commands (14-bit each, range 10000..20000 cycles
 * representing 1ms..2ms at 10MHz, or scaled for 50MHz).
 *
 * In FALLBACK  → output pwm_hist[0] (most recent good value)
 * In SAFE_HOLD → output 30000 - pwm_hist[2] (reverse of oldest saved)
 *
 * PWM value encoding (at 50MHz clock):
 *   Minimum pulse: 50000 cycles = 1ms  (motors off / full reverse)
 *   Center:        75000 cycles = 1.5ms (neutral)
 *   Maximum pulse: 100000 cycles = 2ms  (full forward)
 *   Safe neutral:  50000 cycles (motors off on total loss)
 *
 * Reversal: reverse_pwm = 150000 - pwm_hist[2]
 *   e.g. if last known = 90000 (forward), reverse = 60000 (reverse thrust)
 *   if last known = 60000 (reverse), reverse = 90000 (forward — corrects)
 *   center 75000 reverses to 75000 (neutral, safe)
 */

`default_nettype none

module triad01_pwm_memory (
    input  wire        clk,
    input  wire        rst_n,

    // Current PWM command in (14-bit serial loaded, from top level)
    input  wire [16:0] pwm_cmd,        // 17-bit: 50000..100000 range
    input  wire        pwm_valid,      // pulse: latch pwm_cmd into history

    // Decision from FSM
    input  wire [1:0]  decision,       // 2'b10=PRIMARY 2'b01=FALLBACK 2'b00=SAFE_HOLD

    // Output PWM pulse width to generator
    output reg  [16:0] pwm_out_width,  // selected pulse width

    // Debug: expose history slot 0
    output wire [16:0] pwm_hist0
);

  // Decision encoding
  localparam PRIMARY   = 2'b10;
  localparam FALLBACK  = 2'b01;
  localparam SAFE_HOLD = 2'b00;

  // Safe neutral pulse width at 50MHz: 1ms = 50000 cycles
  localparam SAFE_PWM  = 17'd50000;
  // Reversal constant: min+max = 50000+100000 = 150000
  localparam REV_CONST = 17'd150000;

  // 3-deep PWM history shift register
  reg [16:0] pwm_hist [0:2];

  assign pwm_hist0 = pwm_hist[0];

  integer i;

  // History update: shift on every valid PWM pulse
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pwm_hist[0] <= SAFE_PWM;
      pwm_hist[1] <= SAFE_PWM;
      pwm_hist[2] <= SAFE_PWM;
    end else if (pwm_valid && decision == PRIMARY) begin
      // Only update history when in PRIMARY (live commands)
      pwm_hist[2] <= pwm_hist[1];
      pwm_hist[1] <= pwm_hist[0];
      pwm_hist[0] <= pwm_cmd;
    end
  end

  // Output mux: select PWM based on decision
  always @(*) begin
    case (decision)
      PRIMARY:   pwm_out_width = pwm_cmd;              // live command
      FALLBACK:  pwm_out_width = pwm_hist[0];          // hold last good
      SAFE_HOLD: pwm_out_width = REV_CONST - pwm_hist[2]; // reverse oldest
      default:   pwm_out_width = SAFE_PWM;             // defensive
    endcase
  end

endmodule