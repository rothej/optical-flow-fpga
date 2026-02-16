# scripts/synth_config.tcl

# Usage: vivado -mode batch -source scripts/synth_config.tcl -tclargs <unopt|opt>

if {$argc < 1 || $argc > 2} {
    puts "ERROR: Invalid number of arguments"
    puts "Usage: vivado -mode batch -source scripts/synth_config.tcl -tclargs <unopt|opt> [true|false]"
    puts "  Argument 1: Configuration (unopt or opt)"
    puts "  Argument 2: Run implementation (true or false, default: false)"
    exit 1
}

# Parse arguments
set config [lindex $argv 0]
set run_impl "false"
if {$argc == 2} {
    set run_impl [lindex $argv 1]
}

if {$config == "unopt"} {
    puts "Building UNOPTIMIZED configuration"
    set rtl_dir "rtl/unopt"
    set constraint_file "constraints/timing_unopt.xdc"
    set output_dir "prj/unopt"
} elseif {$config == "opt"} {
    puts "Building OPTIMIZED configuration"
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
add_files [glob rtl/common/*.sv]  ; # Shared modules
add_files -fileset constrs_1 ${constraint_file}
add_files -fileset sim_1 [glob tb/*.sv]

# Set top module
set_property top optical_flow_top_pyramidal [current_fileset]

# Run synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Generate timing report
open_run synth_1
report_timing_summary -file ${output_dir}/timing_summary_${config}.rpt
report_utilization -file ${output_dir}/utilization_${config}.rpt

# Optional Implementation
set run_impl [lindex $argv 1]

if {$run_impl eq "true"} {
    puts "========================================"
    puts "Running Implementation (Place & Route)"
    puts "========================================"

    # Optimization
    opt_design
    puts "INFO: opt_design complete"

    # Placement
    place_design
    puts "INFO: place_design complete"

    # Post-placement optimization
    phys_opt_design
    puts "INFO: phys_opt_design complete"

    # Routing
    route_design
    puts "INFO: route_design complete"

    # Post-route reports
    report_timing_summary -file ${output_dir}/timing_postroute_${config}.rpt
    report_utilization -file ${output_dir}/utilization_postroute_${config}.rpt
    report_route_status -file ${output_dir}/route_status_${config}.rpt

    # Save implemented design
    write_checkpoint -force ${output_dir}/optical_flow_postroute_${config}.dcp

    puts "INFO: Implementation reports written to ${output_dir}/"
}

exit
