/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: rtl/unopt/frame_memory.sv
 *
 * Description: Dual-port BRAM for storing pyramid levels.
 *              Infers Block RAM for efficient memory usage.
 */

`timescale 1ns / 1ps

module frame_memory #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 16,    // 2^16 = 65536 pixels max
    parameter int DEPTH      = 76800  // 320×240
) (
    input logic clk,

    // Port A (write)
    input logic [ADDR_WIDTH-1:0] addr_a,
    input logic [DATA_WIDTH-1:0] data_a,
    input logic                  we_a,

    // Port B (read)
    input  logic [ADDR_WIDTH-1:0] addr_b,
    output logic [DATA_WIDTH-1:0] data_b,
    input  logic                  re_b
);

    // Infer BRAM
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] mem[DEPTH];

    // Port A: Write
    always_ff @(posedge clk) begin
        if (we_a) begin
            mem[addr_a] <= data_a;
        end
    end

    // Port B: Read (registered output)
    always_ff @(posedge clk) begin
        if (re_b) begin
            data_b <= mem[addr_b];
        end
    end

endmodule : frame_memory
