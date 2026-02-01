# scripts/synth_config.tcl

# Usage: vivado -mode batch -source scripts/synth_config.tcl -tclargs <unopt|opt>

if {$argc != 1} {
    puts "ERROR: Configuration argument required"
    puts "Usage: vivado -mode batch -source scripts/synth_config.tcl -tclargs <unopt|opt>"
    exit 1
}

set config [lindex $argv 0]

if {$config == "unopt"} {
    puts "Building UNOPTIMIZED configuration (Part 1)"
    set rtl_dir "rtl/unopt"
    set constraint_file "constraints/timing_unopt.xdc"
    set output_dir "prj/unopt"
} elseif {$config == "opt"} {
    puts "Building OPTIMIZED configuration (Part 2)"
    set rtl_dir "rtl/opt"
    set constraint_file "constraints/timing_opt.xdc"
    set output_dir "prj/opt"
} else {
    puts "ERROR: Unknown configuration '$config'"
    puts "Valid options: unopt, opt"
    exit 1
}

# Create project
create_project optical_flow_${config} ${output_dir} -part xc7a100tcsg324-1 -force

# Add source files
add_files [glob ${rtl_dir}/*.sv]
add_files rtl/common/*.sv  ; # Shared modules
add_files -fileset constrs_1 ${constraint_file}
add_files -fileset sim_1 tb/*.sv

# Set top module
set_property top optical_flow_top [current_fileset]

# Run synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Generate timing report
open_run synth_1
report_timing_summary -file ${output_dir}/timing_summary_${config}.rpt
report_utilization -file ${output_dir}/utilization_${config}.rpt
