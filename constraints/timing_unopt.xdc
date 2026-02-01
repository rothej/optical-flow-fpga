# constraints/timing_unopt.xdc

# Targeting 100 MHz
create_clock -period 10.000 -name sys_clk [get_ports clk]
set_input_delay -clock sys_clk 2.0 [get_ports {rst_n start}]
set_output_delay -clock sys_clk 2.0 [get_ports {flow_u* flow_v* flow_valid}]
