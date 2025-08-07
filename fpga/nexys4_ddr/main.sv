//`define COMPRESS_OUT 1
//`define SPI_RST_EN 1

module top (
    input logic clk,  // 100MHz

    output logic [15:0] LED,

    input  logic mosi,
    output logic miso,
    input  logic sck,
    input  logic cs,

    input logic CPU_RESETN,
    input logic soft_reset,

    output logic i2s_clk,  // Clock do I2S
    output logic i2s_ws,   // Word Select do I2S
    input  logic i2s_sd    // Dados do I2S
);



endmodule

