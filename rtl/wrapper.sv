module Wrapper #(
    parameter SYS_CLK_FREQ  = 100_000_000,
    parameter REF_CLK_FREQ  = 200_000_000,
    parameter DRAM_CLK_FREQ = 800_000_000,
    parameter WORD_SIZE     = 256,
    parameter ADDR_WIDTH    = 25,
    parameter FIFO_DEPTH    = 8
) (
    input  logic sys_clk,
    input  logic rst_n,
    output logic initialized,

    // Wishbone Interface
    input  logic                   cyc_i,
    input  logic                   stb_i,
    input  logic                   we_i,
    input  logic [31:0]            addr_i,
    input  logic [WORD_SIZE - 1:0] data_i,
    output logic [WORD_SIZE - 1:0] data_o,
    output logic                   ack_o,

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
    // Control signals
    logic ddram_init_done;
    logic ddram_init_error;
    logic ddram_pll_locked;

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

    litedram_core u_litedram_core (
        .clk                        (sys_clk),                       // 1 bit
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
        .pll_locked                 (ddram_pll_locked),               // 1 bit
        
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

        .uart_rx                    (0)
    );

    typedef struct packed {
        logic         we;
        logic [31:0]  addr;
        logic [WORD_SIZE-1:0] data;
    } req_t;

    typedef struct packed {
        logic [WORD_SIZE-1:0] data;
    } resp_t;

    req_t  req_fifo_wdata, req_fifo_rdata;
    logic  req_fifo_full, req_fifo_empty;
    logic  req_fifo_wr_en, req_fifo_rd_en;

    resp_t resp_fifo_wdata, resp_fifo_rdata;
    logic  resp_fifo_full, resp_fifo_empty;
    logic  resp_fifo_wr_en, resp_fifo_rd_en;

    // Async FIFOs
    async_fifo #(
        .DEPTH        (FIFO_DEPTH),
        .WIDTH        ($bits(req_t))
    ) request_fifo (
        .clk_wr       (sys_clk),
        .clk_rd       (user_clk),
        .rst_n        (rst_n),
        .wr_en_i      (req_fifo_wr_en),
        .rd_en_i      (req_fifo_rd_en),
        .write_data_i (req_fifo_wdata),
        .read_data_o  (req_fifo_rdata),
        .full_o       (req_fifo_full),
        .empty_o      (req_fifo_empty)
    );

    async_fifo #(
        .DEPTH        (FIFO_DEPTH),
        .WIDTH        ($bits(resp_t))
    ) response_fifo (
        .clk_wr       (user_clk),
        .clk_rd       (sys_clk),
        .rst_n        (rst_n),
        .wr_en_i      (resp_fifo_wr_en),
        .rd_en_i      (resp_fifo_rd_en),
        .write_data_i (resp_fifo_wdata),
        .read_data_o  (resp_fifo_rdata),
        .full_o       (resp_fifo_full),
        .empty_o      (resp_fifo_empty)
    );

    // FSM - Wishbone
    typedef enum logic [1:0] { 
        WB_IDLE,
        WB_ACK,
        WB_WBACK
    } wb_state_t;
    
    wb_state_t req_state;

    always_ff @(posedge sys_clk or negedge rst_n ) begin
        req_fifo_wr_en  <= 0;
        resp_fifo_rd_en <= 0;
        ack_o           <= 0;

        if(!rst_n) begin
            req_state <= WB_IDLE;
        end else begin
            case (req_state)
                WB_IDLE: begin
                    if (cyc_i && stb_i && !req_fifo_full) begin
                        req_state      <= WB_ACK;
                        req_fifo_wdata <= '{we: we_i, addr: addr_i, data: data_i};
                        req_fifo_wr_en <= 1;
                    end;
                end

                WB_ACK: begin
                    if (!resp_fifo_empty) begin
                        resp_fifo_rd_en <= 1;
                        req_state       <= WB_WBACK;
                    end
                end

                WB_WBACK: begin
                    ack_o     <= 1;
                    data_o    <= resp_fifo_rdata.data;
                    req_state <= WB_IDLE;
                end

                default: req_state <= WB_IDLE;
            endcase
        end
    end

    typedef enum logic [1:0] {
        IDLE,
        READ,
        REQUEST
    } lite_dram_state_t;

    lite_dram_state_t lite_dram_state;

    logic [WORD_SIZE-1:0] ddram_data_out;

    always_ff @( posedge user_clk or posedge user_rst ) begin
        resp_fifo_wr_en <= 1'b0;
        req_fifo_rd_en  <= 1'b0;

        if(user_rst) begin
            lite_dram_state          <= IDLE;
            user_port_wishbone_0_cyc <= 0;
            user_port_wishbone_0_stb <= 0;
            user_port_wishbone_0_we  <= 0;
        end else begin
            case (lite_dram_state)
                IDLE: begin
                    if(!req_fifo_empty && initialized) begin
                        req_fifo_rd_en             <= 1'b1;
                        lite_dram_state            <= READ;
                    end
                end

                READ: begin
                    user_port_wishbone_0_we    <= req_fifo_rdata.we;
                    user_port_wishbone_0_cyc   <= 1'b1;
                    user_port_wishbone_0_stb   <= 1'b1;
                    user_port_wishbone_0_adr   <= req_fifo_rdata.addr[31:7];
                    user_port_wishbone_0_dat_w <= req_fifo_rdata.data;
                    lite_dram_state            <= REQUEST;
                end

                REQUEST: begin
                    if(user_port_wishbone_0_ack) begin
                        user_port_wishbone_0_we  <= 1'b0;
                        user_port_wishbone_0_cyc <= 1'b0;
                        user_port_wishbone_0_stb <= 1'b0;
                        resp_fifo_wdata.data     <= user_port_wishbone_0_dat_r;
                        resp_fifo_wr_en          <= 1'b1;
                        lite_dram_state          <= IDLE;
                    end
                end
                
                default: lite_dram_state <= IDLE;
            endcase
        end
    end

    assign initialized = ddram_init_done & ~ddram_init_error & ddram_pll_locked;
    assign user_port_wishbone_0_sel = 32'hFFFFFFFF;

endmodule
