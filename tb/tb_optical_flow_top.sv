/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: tb/tb_optical_flow_top.sv
 *
 * Description: End-to-end testbench for optical flow accelerator.
 *              Verifies pixel streaming through all pipeline stages, flow output, timing (start
 *              to first valid output) and compares to expected values from Python ref.
 */

`timescale 1ns / 1ps

module tb_optical_flow_top ();

    // Parameters
    localparam int CLK_PERIOD = 10;  // 100 MHz
    localparam int IMAGE_WIDTH = 320;
    localparam int IMAGE_HEIGHT = 240;
    localparam int PIXEL_WIDTH = 8;
    localparam int GRAD_WIDTH = 12;
    localparam int ACCUM_WIDTH = 32;
    localparam int FLOW_WIDTH = 16;
    localparam int WINDOW_SIZE = 5;
    localparam int TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;

    // Expected values (from test frame generation - 2 pixel rightward motion)
    localparam real EXPECTED_U = 2.0;
    localparam real EXPECTED_V = 0.0;
    localparam real TOLERANCE = 0.5;  // Allow ±0.5 pixel error

    // Test regions (avoid edges where flow is zero)
    localparam int TEST_REGION_Y_MIN = 105;
    localparam int TEST_REGION_Y_MAX = 135;
    localparam int TEST_REGION_X_MIN = 55;
    localparam int TEST_REGION_X_MAX = 85;

    // DUT signals
    logic clk;
    logic rst_n;
    logic start;
    logic busy;
    logic done;
    logic signed [FLOW_WIDTH-1:0] flow_u;
    logic signed [FLOW_WIDTH-1:0] flow_v;
    logic flow_valid;

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // DUT instantiation
    optical_flow_top #(
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXEL_WIDTH (PIXEL_WIDTH),
        .GRAD_WIDTH  (GRAD_WIDTH),
        .ACCUM_WIDTH (ACCUM_WIDTH),
        .FLOW_WIDTH  (FLOW_WIDTH),
        .WINDOW_SIZE (WINDOW_SIZE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        .flow_u(flow_u),
        .flow_v(flow_v),
        .flow_valid(flow_valid)
    );

    // Statistics tracking
    integer valid_flow_count;
    integer test_region_count;
    real sum_u, sum_v;
    real sum_sq_u, sum_sq_v;
    integer first_valid_cycle;
    integer last_valid_cycle;

    // Pixel position tracking (for region filtering)
    integer pixel_x, pixel_y;

    // S8.7 fixed-point to float conversion
    function automatic real fixed_to_float(logic signed [FLOW_WIDTH-1:0] fixed_val);
        real result;
        result = $signed(fixed_val) / 128.0;  // 2^7 = 128
        return result;
    endfunction

    // Test stimulus
    initial begin
        $display("\n============================================");
        $display("Optical Flow Accelerator Testbench");
        $display("============================================");
        $display("Configuration:");
        $display("  Resolution: %0dx%0d", IMAGE_WIDTH, IMAGE_HEIGHT);
        $display("  Total pixels: %0d", TOTAL_PIXELS);
        $display("  Window size: %0dx%0d", WINDOW_SIZE, WINDOW_SIZE);
        $display("  Expected motion: u=%.1f, v=%.1f pixels", EXPECTED_U, EXPECTED_V);
        $display("  Test region: x[%0d:%0d], y[%0d:%0d]", TEST_REGION_X_MIN, TEST_REGION_X_MAX,
                 TEST_REGION_Y_MIN, TEST_REGION_Y_MAX);

        // Initialize
        rst_n = 0;
        start = 0;
        valid_flow_count = 0;
        test_region_count = 0;
        sum_u = 0.0;
        sum_v = 0.0;
        sum_sq_u = 0.0;
        sum_sq_v = 0.0;
        first_valid_cycle = -1;
        last_valid_cycle = 0;
        pixel_x = 0;
        pixel_y = 0;

        // Reset sequence
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // Start processing
        $display("\n[%0t] Starting optical flow processing...", $time);
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for busy to assert
        while (!busy) @(posedge clk);
        $display("[%0t] Processing active (busy asserted)", $time);

        // Monitor flow outputs
        fork
            begin
                while (!done) begin
                    @(posedge clk);

                    if (flow_valid) begin
                        real u_float, v_float;

                        if (first_valid_cycle == -1) begin
                            first_valid_cycle = valid_flow_count;
                            pixel_x = 4;  // FIrst valid output is pixel (4,4)
                            pixel_y = 4;
                            $display("[%0t] First valid flow output received", $time);
                            $display("  Latency: %0d clock cycles", first_valid_cycle);
                            $display("  Corresponds to pixel position (%0d, %0d)", pixel_x,
                                     pixel_y);
                        end

                        u_float = fixed_to_float(flow_u);
                        v_float = fixed_to_float(flow_v);

                        valid_flow_count++;
                        last_valid_cycle = valid_flow_count;

                        // Check if in test region (textured square interior)
                        if (pixel_x >= TEST_REGION_X_MIN && pixel_x <= TEST_REGION_X_MAX &&
                            pixel_y >= TEST_REGION_Y_MIN && pixel_y <= TEST_REGION_Y_MAX) begin

                            sum_u += u_float;
                            sum_v += v_float;
                            sum_sq_u += u_float * u_float;
                            sum_sq_v += v_float * v_float;
                            test_region_count++;

                            // Sample values for debugging
                            if (test_region_count % 100 == 1) begin
                                $display("  [x=%3d, y=%3d] u=%6.3f, v=%6.3f", pixel_x, pixel_y,
                                         u_float, v_float);
                            end
                        end

                        // Update pixel position (raster scan order)
                        if (pixel_x == IMAGE_WIDTH - 1) begin
                            pixel_x = 4;  // Reset to first valid column
                            pixel_y++;
                        end else begin
                            pixel_x++;
                        end
                    end
                end
            end

            // Timeout watchdog
            begin
                repeat (TOTAL_PIXELS * 3) @(posedge clk);
                $display("\n*** ERROR: Timeout waiting for completion ***");
                $finish;
            end
        join_any

        disable fork;  // Kill watchdog

        $display("\n[%0t] Processing complete (done asserted)", $time);

        // Calculate statistics
        if (test_region_count > 0) begin
            real mean_u, mean_v, std_u, std_v;
            real variance_u, variance_v;
            real error_u, error_v;

            mean_u = sum_u / test_region_count;
            mean_v = sum_v / test_region_count;

            variance_u = (sum_sq_u / test_region_count) - (mean_u * mean_u);
            variance_v = (sum_sq_v / test_region_count) - (mean_v * mean_v);

            std_u = $sqrt(variance_u);
            std_v = $sqrt(variance_v);

            error_u = mean_u - EXPECTED_U;
            error_v = mean_v - EXPECTED_V;

            $display("\n============================================");
            $display("Results Summary");
            $display("============================================");
            $display("Total valid flow vectors: %0d", valid_flow_count);
            $display("Vectors in test region: %0d", test_region_count);
            $display("Latency: %0d cycles (%.2f us @ 100MHz)", first_valid_cycle,
                     first_valid_cycle * CLK_PERIOD / 1000.0);

            $display("\nFlow Statistics (Test Region):");
            $display("  Mean:     u=%6.3f, v=%6.3f", mean_u, mean_v);
            $display("  Std Dev:  u=%6.3f, v=%6.3f", std_u, std_v);
            $display("  Expected: u=%6.3f, v=%6.3f", EXPECTED_U, EXPECTED_V);
            $display("  Error:    u=%6.3f, v=%6.3f", error_u, error_v);

            // Pass/fail determination
            $display("\n============================================");
            if ($abs(error_u) <= TOLERANCE && $abs(error_v) <= TOLERANCE) begin
                $display("*** TEST PASSED ***");
                $display("Flow vectors within tolerance (±%.1f pixels)", TOLERANCE);
            end else begin
                $display("*** TEST FAILED ***");
                $display("Flow error exceeds tolerance:");
                if ($abs(error_u) > TOLERANCE)
                    $display("  U component: %.3f > %.1f", $abs(error_u), TOLERANCE);
                if ($abs(error_v) > TOLERANCE)
                    $display("  V component: %.3f > %.1f", $abs(error_v), TOLERANCE);
            end
            $display("============================================\n");

        end else begin
            $display("\n*** ERROR: No flow vectors in test region ***");
            $display("This indicates a problem with the pipeline or test setup.\n");
        end

        repeat (20) @(posedge clk);
        $finish;
    end

    // Waveform dumping for debugging
    initial begin
        if ($value$plusargs("dump_waves")) begin
            $dumpfile("tb_optical_flow_top.vcd");
            $dumpvars(0, tb_optical_flow_top);
            $display("Waveform dumping enabled: tb_optical_flow_top.vcd");
        end
    end

endmodule : tb_optical_flow_top
