/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: rtl/unopt/flow_solver.sv
 *
 * Description: Computes optical flow by solving a 2x2 system:
 *                 [ sum_Ix^2  sum_IxIy ] [ u ]   [ -sum_IxIt ]
 *                 [ sum_IxIy  sum_Iy^2 ] [ v ] = [ -sum_IyIt ]
 *              Solution computes using determinant calculation (2 mult, 1 sub), matrix adjugate,
 *              and two division operations (u and v components). All done in one cycle.
 */

`timescale 1ns / 1ps

module flow_solver #(
    parameter int ACCUM_WIDTH = 32,
    parameter int FLOW_WIDTH  = 16,  // S8.7 fixed-point
    parameter int FRAC_BITS   = 7
) (
    input logic clk,
    input logic rst_n,

    input logic signed [ACCUM_WIDTH-1:0] sum_IxIx,
    input logic signed [ACCUM_WIDTH-1:0] sum_IyIy,
    input logic signed [ACCUM_WIDTH-1:0] sum_IxIy,
    input logic signed [ACCUM_WIDTH-1:0] sum_IxIt,
    input logic signed [ACCUM_WIDTH-1:0] sum_IyIt,
    input logic                          accum_valid,

    input  logic [9:0] pixel_x_in,
    input  logic [8:0] pixel_y_in,
    output logic [9:0] pixel_x_out,
    output logic [8:0] pixel_y_out,

    output logic signed [FLOW_WIDTH-1:0] flow_u,
    output logic signed [FLOW_WIDTH-1:0] flow_v,
    output logic                         flow_valid
);

    // Determinant threshold (avoid division by zero)
    localparam logic signed [ACCUM_WIDTH-1:0] DET_THRESHOLD = 1000;

    /*
    * Matrix Inversion with DSP Inference
    *
    * Stage 1: Compute determinant and numerators using pipelined multipliers
    * Stage 2: Division (combinational)
    */

    // Stage 1: Pipelined matrix products (uses DSP48E1)
    (* use_dsp = "yes" *) logic signed [2*ACCUM_WIDTH-1:0] prod_det1, prod_det2;
    (* use_dsp = "yes" *) logic signed [2*ACCUM_WIDTH-1:0] prod_num_u1, prod_num_u2;
    (* use_dsp = "yes" *) logic signed [2*ACCUM_WIDTH-1:0] prod_num_v1, prod_num_v2;

    logic signed [ACCUM_WIDTH-1:0] sum_IxIx_d1, sum_IyIy_d1, sum_IxIy_d1;
    logic signed [ACCUM_WIDTH-1:0] sum_IxIt_d1, sum_IyIt_d1;
    logic accum_valid_d1;
    logic [9:0] pixel_x_in_d1;
    logic [8:0] pixel_y_in_d1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prod_det1 <= '0;
            prod_det2 <= '0;
            prod_num_u1 <= '0;
            prod_num_u2 <= '0;
            prod_num_v1 <= '0;
            prod_num_v2 <= '0;
            sum_IxIx_d1 <= '0;
            sum_IyIy_d1 <= '0;
            sum_IxIy_d1 <= '0;
            sum_IxIt_d1 <= '0;
            sum_IyIt_d1 <= '0;
            accum_valid_d1 <= 1'b0;
            pixel_x_in_d1 <= '0;
            pixel_y_in_d1 <= '0;
        end else begin
            // Determinant products: det = IxIx*IyIy - IxIy*IxIy
            prod_det1 <= sum_IxIx * sum_IyIy;
            prod_det2 <= sum_IxIy * sum_IxIy;

            // Numerator products for u: IyIy*IxIt - IxIy*IyIt
            prod_num_u1 <= sum_IyIy * sum_IxIt;
            prod_num_u2 <= sum_IxIy * sum_IyIt;

            // Numerator products for v: IxIx*IyIt - IxIy*IxIt
            prod_num_v1 <= sum_IxIx * sum_IyIt;
            prod_num_v2 <= sum_IxIy * sum_IxIt;

            // Pipeline control signals
            sum_IxIx_d1 <= sum_IxIx;
            sum_IyIy_d1 <= sum_IyIy;
            sum_IxIy_d1 <= sum_IxIy;
            sum_IxIt_d1 <= sum_IxIt;
            sum_IyIt_d1 <= sum_IyIt;
            accum_valid_d1 <= accum_valid;
            pixel_x_in_d1 <= pixel_x_in;
            pixel_y_in_d1 <= pixel_y_in;
        end
    end

    // Stage 2: Combinational division and result selection
    logic signed [ACCUM_WIDTH-1:0] det;
    logic signed [ACCUM_WIDTH-1:0] numerator_u, numerator_v;
    logic signed [FLOW_WIDTH-1:0] flow_u_comb, flow_v_comb;
    logic solvable;

    always_comb begin
        logic signed [ACCUM_WIDTH+FRAC_BITS-1:0] scaled_num_u, scaled_num_v;

        // Compute determinant from pipelined products
        det = prod_det1[ACCUM_WIDTH-1:0] - prod_det2[ACCUM_WIDTH-1:0];

        // Compute numerators from pipelined products
        numerator_u = prod_num_u1[ACCUM_WIDTH-1:0] - prod_num_u2[ACCUM_WIDTH-1:0];
        numerator_v = prod_num_v1[ACCUM_WIDTH-1:0] - prod_num_v2[ACCUM_WIDTH-1:0];

        // Check if system is solvable
        solvable = (det > DET_THRESHOLD) || (det < -DET_THRESHOLD);

        // Division with fixed-point scaling (combinational)
        if (solvable) begin
            scaled_num_u = numerator_u <<< FRAC_BITS;
            scaled_num_v = numerator_v <<< FRAC_BITS;

            flow_u_comb  = scaled_num_u / det;
            flow_v_comb  = scaled_num_v / det;

            // Clamp to ±8 pixels
            if (flow_u_comb > $signed(16'sd1024)) begin
                flow_u_comb = $signed(16'sd1024);
            end else if (flow_u_comb < $signed(-16'sd1024)) begin
                flow_u_comb = $signed(-16'sd1024);
            end

            if (flow_v_comb > $signed(16'sd1024)) begin
                flow_v_comb = $signed(16'sd1024);
            end else if (flow_v_comb < $signed(-16'sd1024)) begin
                flow_v_comb = $signed(-16'sd1024);
            end
        end else begin
            flow_u_comb = '0;
            flow_v_comb = '0;
        end
    end

    // Register outputs
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flow_u      <= '0;
            flow_v      <= '0;
            flow_valid  <= 1'b0;
            pixel_x_out <= '0;
            pixel_y_out <= '0;
        end else begin
            flow_u      <= flow_u_comb;
            flow_v      <= flow_v_comb;
            flow_valid  <= accum_valid_d1;
            pixel_x_out <= pixel_x_in_d1;
            pixel_y_out <= pixel_y_in_d1;
        end
    end

endmodule
