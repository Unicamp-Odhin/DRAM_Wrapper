module top #(
    parameter SYS_CLK_FREQ  = 50_000_000,  // 50 MHz
    parameter USER_CLK_FREQ = 100_000_000, // 100 MHz
    parameter REF_CLK_FREQ  = 200_000_000, // 200 MHz
    parameter DRAM_CLK_FREQ = 800_000_000, // 800 MHz
    parameter WORD_SIZE     = 256          // Word size for DRAM controller
) (
    input  logic        clk,
    input  logic        rst_n,

    output logic [7:0]  led,

    // DRAM interface
    inout  logic [31:0] ddram_dq,
    inout  logic [3:0]  ddram_dqs_n,
    inout  logic [3:0]  ddram_dqs_p,
    output logic [14:0] ddram_a,
    output logic [2:0]  ddram_ba,
    output logic        ddram_ras_n,
    output logic        ddram_cas_n,
    output logic        ddram_we_n,
    output logic        ddram_reset_n,
    output logic [0:0]  ddram_clk_p,
    output logic [0:0]  ddram_clk_n,
    output logic [0:0]  ddram_cke,
    output logic [0:0]  ddram_cs_n,
    output logic [3:0]  ddram_dm,
    output logic [0:0]  ddram_odt
);
    // PLL and clock generation
    logic locked, sys_clk_100mhz, initialized;

    clk_wiz_0 clk_wiz_0_inst (
        .clk_out1 (sys_clk_100mhz), // 100 MHz system clock
        .resetn   (rst_n),          // Active low reset
        .locked   (locked),         // Locked signal
        .clk_in1  (clk)             // System clock - 50 MHz
    );

    logic [WORD_SIZE - 1: 0] write_data, read_data;
    logic [24:0] real_addr;
    logic [31:0] addr;
    logic cyc, stb, we, ack;

    Wrapper #(
        .SYS_CLK_FREQ         (USER_CLK_FREQ),
        .WORD_SIZE            (WORD_SIZE),
        .ADDR_WIDTH           (25),
        .FIFO_DEPTH           (8)
    ) u_Wrapper (
        .sys_clk              (sys_clk_100mhz),                // 1 bit
        .rst_n                (rst_n),                         // 1 bit
        .initialized          (initialized),                   // 1 bit

        .cyc_i                (cyc),                           // 1 bit
        .stb_i                (stb),                           // 1 bit
        .we_i                 (we),                            // 1 bit
        .addr_i               (addr),                          // 32 bits
        .data_i               (write_data),                    // 256 bits
        .data_o               (read_data),                     // 256 bits
        .ack_o                (ack),                           // 1 bit

        .ddram_dq             (ddram_dq),                      // 32 bits
        .ddram_dqs_n          (ddram_dqs_n),                   // 4 bits
        .ddram_dqs_p          (ddram_dqs_p),                   // 4
        .ddram_a              (ddram_a),                       // 15 bits
        .ddram_ba             (ddram_ba),                      // 3 bits
        .ddram_cas_n          (ddram_cas_n),                   // 1 bit
        .ddram_cke            (ddram_cke),                     // 1 bit
        .ddram_clk_n          (ddram_clk_n),                   // 1 bit
        .ddram_clk_p          (ddram_clk_p),                   // 1 bit
        .ddram_cs_n           (ddram_cs_n),                    // 1 bit
        .ddram_dm             (ddram_dm),                      // 4 bits
        .ddram_odt            (ddram_odt),                     // 1 bit
        .ddram_ras_n          (ddram_ras_n),                   // 1 bit
        .ddram_reset_n        (ddram_reset_n),                 // 1 bit
        .ddram_we_n           (ddram_we_n)                     // 1 bit
    );

    typedef enum logic [2:0] {
        TST_IDLE,
        TST_WRITE,
        TST_DELAY,
        TST_WAIT_WRITE,
        TST_READ,
        TST_WAIT_READ,
        TST_CHECK
    } test_state_t;

    test_state_t test_state;
    logic [31:0] delay_counter;
    logic pass, fail;

    localparam NUM_BYTES = WORD_SIZE / 8;

    localparam TEST_VALUE = {NUM_BYTES{8'b10100101}}; // Padrão A5 repetido
    localparam logic [127:0] TEST_VALUE1 = {32{8'hA5}};
    localparam logic [127:0] TEST_VALUE2 = {32{8'h5A}};
    localparam logic [127:0] TEST_VALUE3 = {32{8'hFF}};
    localparam logic [127:0] TEST_VALUE4 = {32{8'h00}};
    localparam logic [127:0] TEST_VALUE5 = {32{8'hF0}};
    localparam logic [127:0] TEST_VALUE6 = {32{8'h0F}};
    localparam logic [127:0] TEST_VALUE7 = {32{8'hAA}};
    localparam logic [127:0] TEST_VALUE8 = {32{8'h55}};
    localparam logic [127:0] TEST_VALUE9 = 256'hAABB_CCDD_EEFF_0011_2233_4455_6677_8899_AABB_CCDD_EEFF_0011_2233_4455_6677_8899;

    logic [WORD_SIZE - 1 : 0] test_data;

    always_ff @( posedge  sys_clk_100mhz or negedge rst_n ) begin
        if(!rst_n) begin
            cyc  <= 0;
            stb  <= 0;
            pass <= 0;
            fail <= 0;
            we   <= 0;
            delay_counter <= 0;
            test_state <= TST_DELAY;
        end else begin
            case (test_state)
                TST_IDLE: begin
                    if(initialized) test_state <= TST_DELAY;
                end

                TST_DELAY: begin
                    if(delay_counter < 1000_000_000) begin
                        delay_counter <= delay_counter + 1;
                    end else begin
                        test_state <= TST_WRITE;
                    end
                end

                TST_WRITE: begin
                    real_addr  <= 0;
                    cyc        <= 1;
                    stb        <= 1;
                    we         <= 1;
                    write_data <= TEST_VALUE9;
                    test_state <= TST_WAIT_WRITE;
                    test_data  <= 0;
                end

                TST_WAIT_WRITE: begin
                    if(ack) begin
                        test_state <= TST_READ;
                        we         <= 1'b0;
                        cyc        <= 1'b0;
                        stb        <= 1'b0;
                    end
                end

                TST_READ: begin
                    we         <= 1'b0;
                    cyc        <= 1'b1;
                    stb        <= 1'b1;
                    test_state <= TST_WAIT_READ;
                end

                TST_WAIT_READ: begin
                    if(ack) begin
                        test_state <= TST_CHECK;
                        we         <= 1'b0;
                        cyc        <= 1'b0;
                        stb        <= 1'b0;
                        test_data  <= read_data;
                    end
                end

                TST_CHECK: begin
                    if(test_data == TEST_VALUE9) begin
                        pass <= 1'b1;
                        fail <= 1'b0;
                    end else begin
                        pass <= 1'b0;
                        fail <= 1'b1;
                    end
                end

                default: test_state <= TST_IDLE;
            endcase
        end
    end

    assign addr = {real_addr, 7'h0};
    assign led  = {pass, fail, 3'h0, 2'b11, initialized};

endmodule
