module top #(
    parameter SYS_CLK_FREQ  = 50_000_000,  // 50 MHz
    parameter USER_CLK_FREQ = 100_000_000, // 100 MHz
    parameter REF_CLK_FREQ  = 200_000_000, // 200 MHz
    parameter DRAM_CLK_FREQ = 800_000_000, // 800 MHz
    parameter WORD_SIZE     = 256          // Word size for DRAM controller
) (
    input  logic        board_clk,
    input  logic        rst_n,

    input  logic        rxd,
    output logic        txd,

    output logic [7:0]  led,
    input  logic [3:0]  btn,
    input  logic [33:0] gpio,

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
    logic locked, dram_pll_locked, sys_clk_100mhz, init_done_ctrl;

    clk_wiz_0 clk_wiz_0_inst (
        .clk_out1 (sys_clk_100mhz), // 100 MHz system clock
        .resetn   (rst_n),          // Active low reset
        .locked   (locked),         // Locked signal
        .clk_in1  (board_clk)       // System clock - 50 MHz
    );

    // Control signals
    logic ddram_init_done;
    logic ddram_init_error;

    // User port signals
    logic user_rst;
    logic user_clk;

    // User wishbone signals
    logic user_port_wishbone_0_ack;
    logic [24:0] user_port_wishbone_0_adr;
    logic user_port_wishbone_0_cyc;
    logic [255:0] user_port_wishbone_0_dat_r;
    logic [255:0] user_port_wishbone_0_dat_w;
    logic user_port_wishbone_0_err;
    logic [31:0] user_port_wishbone_0_sel;
    logic user_port_wishbone_0_stb;
    logic user_port_wishbone_0_we;

    logic [255:0] read_data;

    litedram_core u_litedram_core (
        .clk                        (sys_clk_100mhz),                // 1 bit
        .rst                        (~rst_n),                        // 1 bit
        
        .ddram_dq                   (ddram_dq),                      // 32 bits
        .ddram_dqs_n                (ddram_dqs_n),                   // 4 bits
        .ddram_dqs_p                (ddram_dqs_p),                   // 4
        .ddram_a                    (ddram_a),                       // 15 bits
        .ddram_ba                   (ddram_ba),                      // 3 bits
        .ddram_cas_n                (ddram_cas_n),                   // 1 bit
        .ddram_cke                  (ddram_cke),                     // 1 bit
        .ddram_clk_n                (ddram_clk_n),                   // 1 bit
        .ddram_clk_p                (ddram_clk_p),                   // 1 bit
        .ddram_cs_n                 (ddram_cs_n),                    // 1 bit
        .ddram_dm                   (ddram_dm),                      // 4 bits
        .ddram_odt                  (ddram_odt),                     // 1 bit
        .ddram_ras_n                (ddram_ras_n),                   // 1 bit
        .ddram_reset_n              (ddram_reset_n),                 // 1 bit
        .ddram_we_n                 (ddram_we_n),                    // 1 bit
        .init_done                  (ddram_init_done),               // 1 bit
        .init_error                 (ddram_init_error),              // 1 bit
        .pll_locked                 (dram_pll_locked),               // 1 bit
        
        .user_clk                   (user_clk),                      // 1 bit
        .user_port_wishbone_0_ack   (user_port_wishbone_0_ack),      // 1 bit
        .user_port_wishbone_0_adr   (user_port_wishbone_0_adr),      // 25 bits
        .user_port_wishbone_0_cyc   (user_port_wishbone_0_cyc),      // 1 bit
        .user_port_wishbone_0_dat_r (user_port_wishbone_0_dat_r),    // 256 bits
        .user_port_wishbone_0_dat_w (user_port_wishbone_0_dat_w),    // 256 bits
        .user_port_wishbone_0_err   (user_port_wishbone_0_err),      // 1 bit
        .user_port_wishbone_0_sel   (user_port_wishbone_0_sel),      // 32 bits
        .user_port_wishbone_0_stb   (user_port_wishbone_0_stb),      // 1 bit
        .user_port_wishbone_0_we    (user_port_wishbone_0_we),       // 1 bit
        .user_rst                   (user_rst),                      // 1 bit
        
        .uart_rx(0)
    );

    typedef enum logic [2:0] {
        TST_IDLE,
        TST_WRITE,
        TST_WAIT_WRITE,
        TST_READ,
        TST_WAIT_READ,
        TST_CHECK
    } test_state_t;

    test_state_t test_state;
    logic [15:0] delay_counter;
    logic pass, fail;

    assign led = {pass, 1'b1, ddram_init_done, 1'b0, ddram_init_error ,2'b00, fail};
    //assign led = 8'hFF; // For debugging, set all LEDs to ON

    localparam NUM_BYTES = WORD_SIZE / 8;

    localparam TEST_VALUE = {NUM_BYTES{8'b10100101}}; // Padrão A5 repetido
    localparam logic [127:0] TEST_VALUE1 = {16{8'hA5}};
    localparam logic [127:0] TEST_VALUE2 = {16{8'h5A}};
    localparam logic [127:0] TEST_VALUE3 = {16{8'hFF}};
    localparam logic [127:0] TEST_VALUE4 = {16{8'h00}};
    localparam logic [127:0] TEST_VALUE5 = {16{8'hF0}};
    localparam logic [127:0] TEST_VALUE6 = {16{8'h0F}};
    localparam logic [127:0] TEST_VALUE7 = {16{8'hAA}};
    localparam logic [127:0] TEST_VALUE8 = {16{8'h55}};
    localparam logic [127:0] TEST_VALUE9 = 256'hAABB_CCDD_EEFF_0011_2233_4455_6677_8899_AABB_CCDD_EEFF_0011_2233_4455_6677_8899;

    always_ff @( posedge user_clk ) begin
        if(user_rst) begin
            fail <= 0;
            pass <= 0;
            test_state <= TST_IDLE;
            user_port_wishbone_0_cyc <= 0;
            user_port_wishbone_0_stb <= 0;
            user_port_wishbone_0_adr <= 0;
            user_port_wishbone_0_we  <= 0;
            user_port_wishbone_0_sel <= 32'hFFFFFFFF;
        end else begin
            case (test_state)
                TST_IDLE: begin
                    if(ddram_init_done && !ddram_init_error) begin    
                        test_state <= TST_WRITE;
                    end
                end 

                TST_WRITE: begin
                    user_port_wishbone_0_sel   <= 32'hFFFFFFFF;
                    user_port_wishbone_0_dat_w <= TEST_VALUE9;
                    user_port_wishbone_0_we    <= 1'b1;
                    user_port_wishbone_0_cyc   <= 1'b1;
                    user_port_wishbone_0_stb   <= 1'b1;
                    test_state                 <= TST_WAIT_WRITE;
                end

                TST_WAIT_WRITE: begin
                    if(user_port_wishbone_0_ack) begin
                        test_state <= TST_READ;
                        user_port_wishbone_0_we  <= 1'b0;
                        user_port_wishbone_0_cyc <= 1'b0;
                        user_port_wishbone_0_stb <= 1'b0;
                    end
                end

                TST_READ: begin
                    user_port_wishbone_0_we  <= 1'b0;
                    user_port_wishbone_0_cyc <= 1'b1;
                    user_port_wishbone_0_stb <= 1'b1;
                    test_state <= TST_WAIT_READ;
                end

                TST_WAIT_READ: begin
                    if(user_port_wishbone_0_ack) begin
                        test_state <= TST_CHECK;
                        user_port_wishbone_0_we  <= 1'b0;
                        user_port_wishbone_0_cyc <= 1'b0;
                        user_port_wishbone_0_stb <= 1'b0;
                        read_data <= user_port_wishbone_0_dat_r;
                    end
                end

                TST_CHECK: begin
                    if(read_data == TEST_VALUE9) begin
                        pass <= 1'b1;
                        fail <= 1'b0;
                    end else begin
                        pass <= 1'b0;
                        fail <= 1'b1;
                    end
                end

                default: test_state <= TST_IDLE; // Reset to idle state 
            endcase
        end
    end

endmodule