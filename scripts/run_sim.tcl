# scripts/run_sim.tcl

# Usage: vivado -mode batch -source scripts/run_sim.tcl -tclargs <testbench_name>

if {$argc != 1} {
    puts "ERROR: Testbench name required"
    puts "Usage: vivado -mode batch -source scripts/run_sim.tcl -tclargs <tb_name>"
    puts "Example: vivado -mode batch -source scripts/run_sim.tcl -tclargs tb_optical_flow_top"
    exit 1
}

set tb_name [lindex $argv 0]
set sim_dir "sim_${tb_name}"

# Create simulation project
create_project -force sim_project ${sim_dir} -part xc7a100tcsg324-1

# Add source files
add_files [glob rtl/unopt/*.sv]
add_files [glob rtl/common/*.sv]
add_files tb/${tb_name}.sv

# Set testbench as top
set_property top ${tb_name} [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sim_1

# Copy test frames to simulation directory
set sim_work_dir "${sim_dir}/sim_project.sim/sim_1/behav/xsim"
file mkdir ${sim_work_dir}/tb/test_frames
file copy -force tb/test_frames/frame_00.mem ${sim_work_dir}/tb/test_frames/
file copy -force tb/test_frames/frame_01.mem ${sim_work_dir}/tb/test_frames/
puts "Copied test frames to ${sim_work_dir}/tb/test_frames/"

# Launch simulation
launch_simulation

# Run simulation
run 100ms

# Close project
close_project

puts "\n=== Simulation Complete ==="
puts "Check ${sim_dir}/sim_project.sim/ for logs and waveforms"
