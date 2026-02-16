/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: tb/tb_optical_flow_top_pyramidal.sv
 *
 * Description: Tests pyramid builder and FSM with streaming pixel inputs.
 */

`timescale 1ns / 1ps

module tb_optical_flow_top_pyramidal ();
    logic clk, rst_n;
    logic start, busy, done;

    // Pixel streaming interface
    logic [7:0] pixel_curr, pixel_prev;
    logic pixel_valid;

    // Frame buffer arrays (testbench-only)
    logic [7:0] frame0_mem[76800];  // 320x240
    logic [7:0] frame1_mem[76800];

    // Instantiate DUT with streaming interface
    optical_flow_top_pyramidal #(
        .IMAGE_WIDTH (320),
        .IMAGE_HEIGHT(240)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        .pixel_curr(pixel_curr),
        .pixel_prev(pixel_prev),
        .pixel_valid(pixel_valid),
        .flow_u(),
        .flow_v(),
        .flow_valid()
    );

    // Clock gen (100 MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // Load test frames
    initial begin
        $readmemh("tb/test_frames/frame_00.mem", frame0_mem);
        $readmemh("tb/test_frames/frame_01.mem", frame1_mem);
        $display("Test frames loaded: 320×240 pixels");
    end

    // Pixel streaming task
    task automatic stream_frames();
        integer i;
        pixel_valid = 0;
        @(posedge clk);

        for (i = 0; i < 76800; i++) begin
            @(posedge clk);
            pixel_curr  = frame0_mem[i];
            pixel_prev  = frame1_mem[i];
            pixel_valid = 1;
        end

        @(posedge clk);
        pixel_valid = 0;
    endtask

    // Test sequence
    initial begin
        $display("=== Pyramidal Builder Test ===");

        rst_n = 0;
        start = 0;
        pixel_curr = 0;
        pixel_prev = 0;
        pixel_valid = 0;

        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // Trigger pyramid build
        start = 1;
        @(posedge clk);
        start = 0;

        // Stream pixels in parallel with FSM operation
        fork
            stream_frames();
        join_none

        // Wait for completion (or timeout)
        fork
            begin
                wait (done);
                $display("Pyramid build complete at %0t", $time);
            end
            begin
                repeat (1_000_000) @(posedge clk);
                $display("ERROR: Timeout after 10ms");
                $finish;
            end
        join_any

        // Check FSM reached DONE state
        if (dut.u_fsm.state == dut.u_fsm.DONE_ST) begin
            $display("*** TEST PASSED: FSM reached DONE ***");
        end else begin
            $display("*** TEST FAILED: FSM stuck in state %0d ***", dut.u_fsm.state);
        end

        repeat (20) @(posedge clk);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #100ms;
        $display("FATAL: Simulation timeout");
        $finish;
    end
endmodule : tb_optical_flow_top_pyramidal
