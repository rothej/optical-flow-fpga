# constraints/timing_opt.tcl

# Targeting 200 MHz
create_clock -period 5.000 -name sys_clk [get_ports clk]
set_input_delay -clock sys_clk 1.0 [get_ports {rst_n start}]
set_output_delay -clock sys_clk 1.0 [get_ports {flow_u* flow_v* flow_valid}]

# Pipeline stage constraints
set_max_delay 4.5 -from [get_pins u_gradient_compute/pipe_stage1_reg*/C] \
                   -to [get_pins u_gradient_compute/pipe_stage2_reg*/D]
