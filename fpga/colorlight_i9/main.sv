module main (
    input logic clk,  // board clock 25mhz 

    input  logic M_DATA,     // microfone data
    output logic M_CLK,  // microfone clock
    output logic M_LRSEL,    // Left/Right Select

    input  logic cs,    // enable spi
    input  logic mosi,
    input  logic sck,
    output logic miso,

    output logic [15:0] pcm_out,
    output logic        pcm_ready,
    input  logic        rst_n,

    output logic [7:0] LED
);


endmodule

