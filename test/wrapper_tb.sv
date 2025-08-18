module wrapper_tb ();
    localparam WORD_SIZE = 256;

    logic rst_n;
    logic locked, sys_clk_100mhz, initialized;

    logic [WORD_SIZE - 1: 0] write_data, read_data;
    logic [24:0] real_addr;
    logic [31:0] addr;
    logic cyc, stb, we, ack;

    Wrapper #(
        .SYS_CLK_FREQ         (100_000_000),
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
        .ack_o                (ack)                            // 1 bit
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

    localparam logic [WORD_SIZE - 1: 0] TEST_VALUE  = {NUM_BYTES{8'hA5}}; // Padrão A5 repetido
    localparam logic [WORD_SIZE - 1: 0] TEST_VALUE1 = {32{8'hA5}};
    localparam logic [WORD_SIZE - 1: 0] TEST_VALUE2 = {32{8'h5A}};
    localparam logic [WORD_SIZE - 1: 0] TEST_VALUE3 = {32{8'hFF}};
    localparam logic [WORD_SIZE - 1: 0] TEST_VALUE4 = {32{8'h00}};
    localparam logic [WORD_SIZE - 1: 0] TEST_VALUE5 = {32{8'hF0}};
    localparam logic [WORD_SIZE - 1: 0] TEST_VALUE6 = {32{8'h0F}};
    localparam logic [WORD_SIZE - 1: 0] TEST_VALUE7 = {32{8'hAA}};
    localparam logic [WORD_SIZE - 1: 0] TEST_VALUE8 = {32{8'h55}};
    localparam logic [WORD_SIZE - 1: 0] TEST_VALUE9 = 256'h55BB_CCDD_EEFF_0011_2233_4455_6677_8899_AABB_CCDD_EEFF_0011_2233_4455_6677_8899;

    logic [WORD_SIZE - 1 : 0] test_data;

    always_ff @( posedge  sys_clk_100mhz or negedge rst_n ) begin
        if(!rst_n) begin
            cyc  <= 0;
            stb  <= 0;
            pass <= 0;
            fail <= 0;
            we   <= 0;
            delay_counter <= 0;
            test_state <= TST_IDLE;
        end else begin
            case (test_state)
                TST_IDLE: begin
                    if(initialized) test_state <= TST_WRITE;
                end

                TST_DELAY: begin
                    if(delay_counter < 100_000_000) begin
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
                    write_data <= TEST_VALUE;
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
                    if(test_data == TEST_VALUE) begin
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

    initial begin
        $dumpfile("build/wrapper_tb.vcd");
        $dumpvars(0, wrapper_tb);
        
        sys_clk_100mhz = 0;
        rst_n = 0;

        #30

        rst_n = 1;


        #400000;

        $finish;
    end

    always #10 sys_clk_100mhz <= ~sys_clk_100mhz;

endmodule
