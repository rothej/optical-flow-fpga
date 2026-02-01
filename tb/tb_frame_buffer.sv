/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: tb_frame_buffer.sv
 *
 * Description: Testbench for frame buffer - verifies pixel streaming.
 */
`timescale 1ns / 1ps

module tb_frame_buffer ();

    localparam int CLK_PERIOD = 10;  // 100 MHz
    localparam int PIXEL_WIDTH = 8;
    localparam int IMAGE_WIDTH = 320;
    localparam int IMAGE_HEIGHT = 240;
    localparam int TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;

    // Clock and reset
    logic clk;
    logic rst_n;

    // Frame buffer interface
    logic start;
    logic [PIXEL_WIDTH-1:0] pixel_curr;
    logic [PIXEL_WIDTH-1:0] pixel_prev;
    logic pixel_valid;
    logic frame_done;

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // DUT instantiation
    frame_buffer_simple #(
        .PIXEL_WIDTH (PIXEL_WIDTH),
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .FRAME0_FILE ("frame_00.mem"),
        .FRAME1_FILE ("frame_01.mem")
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .pixel_curr(pixel_curr),
        .pixel_prev(pixel_prev),
        .pixel_valid(pixel_valid),
        .frame_done(frame_done)
    );

    // Statistics
    integer white_pixels_curr = 0;
    integer white_pixels_prev = 0;
    integer total_pixels = 0;

    // Test stimulus
    initial begin
        $display("=== Frame Buffer Testbench ===");
        $display("Resolution: %0dx%0d", IMAGE_WIDTH, IMAGE_HEIGHT);
        $display("Total pixels: %0d", TOTAL_PIXELS);

        // Initialize
        rst_n = 0;
        start = 0;

        // Reset
        repeat (5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Start streaming
        $display("\nStarting pixel stream at time %0t", $time);
        start = 1;
        @(posedge clk);
        start = 0;

        // Count pixels
        while (!frame_done) begin
            @(posedge clk);
            if (pixel_valid) begin
                total_pixels++;
                if (pixel_curr == 8'hFF) white_pixels_curr++;
                if (pixel_prev == 8'hFF) white_pixels_prev++;

                // Sample some pixels for debugging
                if (total_pixels % 10000 == 0) begin
                    $display("  Pixel %0d: curr=0x%02h, prev=0x%02h", total_pixels, pixel_curr,
                             pixel_prev);
                end
            end
        end

        // Results
        $display("\n=== Results ===");
        $display("Total pixels streamed: %0d", total_pixels);
        $display("White pixels (curr frame): %0d", white_pixels_curr);
        $display("White pixels (prev frame): %0d", white_pixels_prev);
        $display("Expected white pixels: %0d (40x40 square = 1600)", 40 * 40);

        if (total_pixels == TOTAL_PIXELS) begin
            $display("\n*** TEST PASSED: All pixels streamed correctly ***");
        end else begin
            $display("\n*** TEST FAILED: Pixel count mismatch ***");
        end

        repeat (10) @(posedge clk);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * TOTAL_PIXELS * 2 + 1000);
        $display("\n*** ERROR: Testbench timeout ***");
        $finish;
    end

endmodule
