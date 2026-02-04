/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: optical_flow_top.sv
 *
 * Description: Top-level Lucas-Kanade optical flow accelerator.
 *              Unoptimized version - should fail timing at 100 MHz target.
 */

`timescale 1ns / 1ps

module optical_flow_top #(
    parameter int IMAGE_WIDTH  = 320,
    parameter int IMAGE_HEIGHT = 240,
    parameter int PIXEL_WIDTH  = 8,
    parameter int GRAD_WIDTH   = 12,
    parameter int ACCUM_WIDTH  = 32,
    parameter int FLOW_WIDTH   = 16,
    parameter int WINDOW_SIZE  = 5
) (
    input logic clk,
    input logic rst_n,

    // Control interface
    input  logic start,  // Start processing
    output logic busy,   // Processing active
    output logic done,   // Frame complete

    // Flow output (streaming)
    output logic        [           9:0] flow_x,
    output logic        [           8:0] flow_y,
    output logic signed [FLOW_WIDTH-1:0] flow_u,
    output logic signed [FLOW_WIDTH-1:0] flow_v,
    output logic                         flow_valid
);

    /*
     * Frame Buffer (Simulation Only)
     */
    logic [PIXEL_WIDTH-1:0] pixel_curr, pixel_prev;
    logic pixel_valid;
    logic frame_done;

    frame_buffer_simple #(
        .PIXEL_WIDTH (PIXEL_WIDTH),
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) u_frame_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .pixel_curr(pixel_curr),
        .pixel_prev(pixel_prev),
        .pixel_valid(pixel_valid),
        .frame_done(frame_done)
    );

    // Gradient computation
    logic signed [GRAD_WIDTH-1:0] grad_x, grad_y, grad_t;
    logic grad_valid;

    gradient_compute #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .GRAD_WIDTH (GRAD_WIDTH)
    ) u_gradient_compute (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_curr(pixel_curr),
        .pixel_prev(pixel_prev),
        .pixel_valid(pixel_valid),
        .grad_x(grad_x),
        .grad_y(grad_y),
        .grad_t(grad_t),
        .grad_valid(grad_valid)
    );

    // Window accumulator (structure tensor)
    logic signed [ACCUM_WIDTH-1:0] sum_IxIx, sum_IyIy, sum_IxIy;
    logic signed [ACCUM_WIDTH-1:0] sum_IxIt, sum_IyIt;
    logic accum_valid;

    window_accumulator #(
        .WIDTH(IMAGE_WIDTH),
        .HEIGHT(IMAGE_HEIGHT),
        .GRAD_WIDTH(GRAD_WIDTH),
        .WINDOW_SIZE(WINDOW_SIZE),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) u_window_accumulator (
        .clk(clk),
        .rst_n(rst_n),
        .grad_x(grad_x),
        .grad_y(grad_y),
        .grad_t(grad_t),
        .grad_valid(grad_valid),
        .sum_IxIx(sum_IxIx),
        .sum_IyIy(sum_IyIy),
        .sum_IxIy(sum_IxIy),
        .sum_IxIt(sum_IxIt),
        .sum_IyIt(sum_IyIt),
        .accum_valid(accum_valid)
    );

    // Flow solver (Cramer's rule)
    flow_solver #(
        .ACCUM_WIDTH(ACCUM_WIDTH),
        .FLOW_WIDTH (FLOW_WIDTH),
        .FRAC_BITS  (7)
    ) u_flow_solver (
        .clk(clk),
        .rst_n(rst_n),
        .sum_IxIx(sum_IxIx),
        .sum_IyIy(sum_IyIy),
        .sum_IxIy(sum_IxIy),
        .sum_IxIt(sum_IxIt),
        .sum_IyIt(sum_IyIt),
        .accum_valid(accum_valid),
        .flow_u(flow_u),
        .flow_v(flow_v),
        .flow_valid(flow_valid)
    );

    /*
     * Status Signals.
     */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            if (start) begin
                busy <= 1'b1;
                done <= 1'b0;
            end else if (frame_done) begin
                busy <= 1'b0;
                done <= 1'b1;
            end else if (done) begin
                done <= 1'b0;  // Clear done after 1 cycle
            end
        end
    end

endmodule : optical_flow_top
