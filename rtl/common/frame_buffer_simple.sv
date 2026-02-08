/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: rtl/common/frame_buffer_simple.sv
 *
 * Description: Simulation-only dual frame buffer using $readmemh.
 *              Streams out pixels from two frames sequentially.
 */

`timescale 1ns / 1ps

module frame_buffer_simple #(
    parameter int    PIXEL_WIDTH  = 8,
    parameter int    IMAGE_WIDTH  = 320,
    parameter int    IMAGE_HEIGHT = 240,
    parameter string FRAME0_FILE  = "tb/test_frames/frame_00.mem",
    parameter string FRAME1_FILE  = "tb/test_frames/frame_01.mem"
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   start,
    output logic [            9:0] pixel_x,
    output logic [            8:0] pixel_y,
    output logic [PIXEL_WIDTH-1:0] pixel_curr,
    output logic [PIXEL_WIDTH-1:0] pixel_prev,
    output logic                   pixel_valid,
    output logic                   frame_done
);

    localparam int TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;

    // Frame memories
    logic [PIXEL_WIDTH-1:0] frame_0[TOTAL_PIXELS];
    logic [PIXEL_WIDTH-1:0] frame_1[TOTAL_PIXELS];

    // Load frames from files (sim only)
    initial begin
        $readmemh(FRAME0_FILE, frame_0);
        $readmemh(FRAME1_FILE, frame_1);
        $display("Frame buffer loaded:");
        $display("  Frame 0: %s", FRAME0_FILE);
        $display("  Frame 1: %s", FRAME1_FILE);
        $display("  Total pixels per frame: %0d", TOTAL_PIXELS);
    end

    // Pixel counter
    logic [$clog2(TOTAL_PIXELS):0] pixel_cnt;
    logic streaming;

    // Calculate x,y from linear pixel counter
    always_comb begin
        pixel_x = pixel_cnt % IMAGE_WIDTH;
        pixel_y = pixel_cnt / IMAGE_WIDTH;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_cnt   <= '0;
            streaming   <= 1'b0;
            pixel_valid <= 1'b0;
            frame_done  <= 1'b0;
            pixel_curr  <= '0;
            pixel_prev  <= '0;
        end else begin
            frame_done <= 1'b0;  // Single-cycle pulse

            if (start && !streaming) begin
                // Start streaming
                streaming   <= 1'b1;
                pixel_cnt   <= '0;
                pixel_valid <= 1'b1;
            end else if (streaming) begin
                if (pixel_cnt == TOTAL_PIXELS - 1) begin
                    streaming  <= 1'b0;
                    frame_done <= 1'b1;
                    pixel_cnt  <= '0;
                end else begin
                    pixel_cnt <= pixel_cnt + 1;
                end
            end else begin
                pixel_valid <= 1'b0;
            end

            // Output pixels (frame_1 is "current", frame_0 is "previous")
            if (streaming) begin
                pixel_curr <= frame_1[pixel_cnt];
                pixel_prev <= frame_0[pixel_cnt];
            end
        end
    end

endmodule : frame_buffer_simple
