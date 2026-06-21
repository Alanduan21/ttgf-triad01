/*
 * triad01_pwm_gen.v
 * 50 Hz PWM Generator for TRIAD-SAFE
 *
 * Generates a standard RC-servo / ESC PWM signal:
 *   Period  = 20 ms  (50 Hz)
 *   Pulse   = 1..2 ms (pulse_width input, in clock cycles)
 *
 * At clk = 10 MHz (TinyTapeout default):
 *   Period   = 200,000 cycles
 *   Min pulse =  10,000 cycles  (1 ms)
 *   Max pulse =  20,000 cycles  (2 ms)
 *   Neutral  =  15,000 cycles  (1.5 ms)
 *
 * pulse_width input is 17-bit to accommodate 10..200000 range.
 * pwm_memory supplies scaled values; this module just counts.
 *
 * pwm_out is HIGH for the first pulse_width cycles of each period,
 * then LOW for the remainder — standard servo PWM.
 *
 * TinyTapeout note:
 *   At 10 MHz the period counter reaches 200000, fitting in 18 bits.
 *   At 50 MHz multiply all cycle counts by 5.
 */

`default_nettype none

module triad01_pwm_gen (
    input  wire        clk,
    input  wire        rst_n,

    // Pulse width in clock cycles (from pwm_memory)
    // 10 MHz: 10000..20000 = 1..2 ms
    input  wire [16:0] pulse_width,

    // PWM output — connect to servo/ESC signal line
    output reg         pwm_out
);

  // Period counter: 200000 cycles at 10 MHz = 20 ms = 50 Hz
  localparam PERIOD = 18'd200000;

  reg [17:0] cnt;  // 18-bit to hold 0..199999

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt     <= 18'd0;
      pwm_out <= 1'b0;
    end else begin
      if (cnt >= PERIOD - 1)
        cnt <= 18'd0;
      else
        cnt <= cnt + 18'd1;

      // High for the first pulse_width cycles, then low
      pwm_out <= (cnt < {1'b0, pulse_width}) ? 1'b1 : 1'b0;
    end
  end

endmodule
