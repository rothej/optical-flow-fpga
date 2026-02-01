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
 *                 [ sum_IxIx  sum_IxIy ] [ u ]   [ -sum_IxIt ]
 *                 [ sum_IxIy  sum_IyIy ] [ v ] = [ -sum_IyIt ]
 *              Solution computes using determinant calculation (2 mult, 1 sub), matrix adjugate,
 *              and two division operations (u and v components). All done in one cycle - should
 *              fail timing.
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

    output logic signed [FLOW_WIDTH-1:0] flow_u,
    output logic signed [FLOW_WIDTH-1:0] flow_v,
    output logic                         flow_valid
);

    // Determinant threshold (avoid division by zero)
    localparam logic signed [ACCUM_WIDTH-1:0] DET_THRESHOLD = 1000;

    /*
    * Combinational Matrix Inversion.
    */
    logic signed [ACCUM_WIDTH-1:0] det;
    logic signed [ACCUM_WIDTH-1:0] numerator_u, numerator_v;
    logic signed [FLOW_WIDTH-1:0] flow_u_comb, flow_v_comb;
    logic solvable;

    always_comb begin
        // Compute determinant: det = IxIx * IyIy - IxIy * IxIy
        logic signed [2*ACCUM_WIDTH-1:0] prod1, prod2;
        prod1 = sum_IxIx * sum_IyIy;
        prod2 = sum_IxIy * sum_IxIy;
        det = prod1[ACCUM_WIDTH-1:0] - prod2[ACCUM_WIDTH-1:0];

        // Check if system is solvable (sufficient texture)
        solvable = (det > DET_THRESHOLD) || (det < -DET_THRESHOLD);

        // Compute numerators using Cramer's rule:
        // u = (IyIy * (-IxIt) - IxIy * (-IyIt)) / det
        // v = (IxIx * (-IyIt) - IxIy * (-IxIt)) / det
        logic signed [2*ACCUM_WIDTH-1:0] temp1, temp2;

        // Numerator for u
        temp1 = sum_IyIy * (-sum_IxIt);
        temp2 = sum_IxIy * (-sum_IyIt);
        numerator_u = temp1[ACCUM_WIDTH-1:0] - temp2[ACCUM_WIDTH-1:0];

        // Numerator for v
        temp1 = sum_IxIx * (-sum_IyIt);
        temp2 = sum_IxIy * (-sum_IxIt);
        numerator_v = temp1[ACCUM_WIDTH-1:0] - temp2[ACCUM_WIDTH-1:0];

        // Division (NON-PIPELINED - massive critical path!)
        // Scale to fixed-point S8.7 format
        if (solvable) begin
            logic signed [ACCUM_WIDTH+FRAC_BITS-1:0] scaled_num_u, scaled_num_v;
            scaled_num_u = numerator_u <<< FRAC_BITS;
            scaled_num_v = numerator_v <<< FRAC_BITS;

            flow_u_comb  = scaled_num_u / det;
            flow_v_comb  = scaled_num_v / det;
        end else begin
            flow_u_comb = '0;
            flow_v_comb = '0;
        end
    end

    // Register outputs
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flow_u     <= '0;
            flow_v     <= '0;
            flow_valid <= 1'b0;
        end else begin
            flow_u     <= flow_u_comb;
            flow_v     <= flow_v_comb;
            flow_valid <= accum_valid;
        end
    end

endmodule
