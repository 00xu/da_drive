`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
//////////////////////////////////////////////////////////////////////////////////
module fpga_top(
  input               sys_clk_p,                               //system clock positive
  input               sys_clk_n,
  input                rst_n,               //system clock negative 

     (* MARK_DEBUG="true" *)output  reg         cs       ,   
     (* MARK_DEBUG="true" *)output  reg         sclk     ,
     (* MARK_DEBUG="true" *)output  reg         da_sdi   ,   //对于从设备（AD）来说是输入
                             input                da_sdo          //对于从设备（AD）来说是输出
  );

    wire                clk_100m  ;
    wire                clk_50m   ;
    wire                clk       ;
  mmcm mmcm_inst
   (
    // Clock out ports
    .clk_out1(clk_100m),     // output clk_out1
    .clk_out2(clk_50m),     // output clk_out2
    // Status and control signals
    .locked(   ),       // output locked
   // Clock in ports
    .clk_in1_p(sys_clk_p),    // input clk_in1_p
    .clk_in1_n(sys_clk_n));    // input clk_in1_n
 
    assign    clk =  clk_100m;
    
    
    wire           data_vld;
    wire  [15:0]   data    ;
    wire           start   ;
    reg            config_flag;
    assign start    = 1'b1  ;

    parameter    DIV   ='h6; //6==16.67mhz
    parameter    DIV_2 =DIV/2;

    parameter IDLE       = 3'h0;
    parameter SPICONFIG  = 3'h1;
    parameter WR_ADRESS  = 3'h2;
    parameter WR_DATA    = 3'h3;
    
    (* MARK_DEBUG="true" *)reg  [2:0] state_c,state_n;
    wire idl2spiconfig_start          ;  
    wire spiconfig2idle_start         ;
    wire idl2wr_adress_start          ;  
    wire wr_adress2wr_data_start      ;
    wire wr_data2idle_start           ;
   
    (* MARK_DEBUG="true" *)reg [15:0]  cnt       ;
    wire        end_cnt   ;
    wire        add_cnt   ;
    
    (* MARK_DEBUG="true" *)reg [15:0]  cnt1       ;
    wire        end_cnt1   ;
    wire        add_cnt1   ;
    reg  [4:0]    x          ; 

    (* MARK_DEBUG="true" *)reg [15:0]  cnt2       ;
    wire        end_cnt2   ;
    wire        add_cnt2   ;

    //config_flag 信号生成  达到每次复位后进行一次配置操作
    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            config_flag <= 1'b1;
    end
        else if (state_c == SPICONFIG) begin
            config_flag <= 1'b0;
        end
        else 
            config_flag <=config_flag;    
    end



 //第wrfifo2idle_start  一段：同步时序always模块，格式化描述次态寄存器迁移到现态寄存器(不需更改）
    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state_c <= IDLE;
    end
        else begin
            state_c <= state_n;
        end
    end
 //第二段：组合逻辑always模块，描述状态转移条件判断
    always@(*)begin
        case(state_c)
            IDLE:begin
                if(idl2spiconfig_start)begin
                    state_n = SPICONFIG;
                end
                else if(idl2wr_adress_start)begin
                    state_n = WR_ADRESS;
                end
                else begin
                    state_n = state_c;
                end
            end
            SPICONFIG:begin
                if(spiconfig2idle_start)begin
                    state_n = IDLE;
                end
                else begin
                    state_n = state_c;
                end
            end
            WR_ADRESS:begin
                if(wr_adress2wr_data_start)begin
                    state_n = WR_DATA;
                end
                else begin
                    state_n = state_c;
                end
            end
            WR_DATA:begin
                if(wr_data2idle_start)begin
                    state_n = IDLE;
                end
                else begin
                    state_n = state_c;
                end
            end
            default:begin
                state_n = IDLE;
            end
        endcase
    end
 //第三段：设计转移条件
    
    assign idl2spiconfig_start         = state_c == IDLE         && config_flag==1 && end_cnt1;
    assign idl2wr_adress_start         = state_c == IDLE         && start==1   && end_cnt1    ;
    assign spiconfig2idle_start        = state_c == SPICONFIG    && end_cnt1;
    assign wr_adress2wr_data_start     = state_c == WR_ADRESS    && end_cnt1;
    assign wr_data2idle_start          = state_c == WR_DATA      && end_cnt2;
  
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            cnt <= 0;
        end
        else if(add_cnt)begin
            if(end_cnt)
                cnt <= 0;
            else
                cnt <= cnt + 1;
         end
    end
    
    assign add_cnt = 1'b1;     // assign add_cnt = state_c != IDLE;
    assign end_cnt = add_cnt && cnt ==  DIV-1;
    
    always @(posedge clk or negedge rst_n)begin 
    if(!rst_n)begin
        cnt1 <= 0;
    end
    else if(add_cnt1)begin
        if(end_cnt1)
            cnt1 <= 0;
        else
            cnt1 <= cnt1 + 1;
    end
    end
    
    assign add_cnt1 = end_cnt;
    assign end_cnt1 = add_cnt1 && cnt1== x-1;
    always@(*)begin
        if      (state_c == SPICONFIG)  x=24 ;  //8个地址+16数据 
        else  if(state_c == WR_ADRESS)  x=8  ; 
        else  if(state_c == WR_DATA  )  x=16 ;
        else  if(state_c == IDLE     )  x=1  ;
        else                            x= 0 ;
    end
 

    always @(posedge clk or negedge rst_n)begin 
    if(!rst_n)begin
        cnt2 <= 0;
    end
    else if(add_cnt2)begin
        if(end_cnt2)
            cnt2 <= 0;
        else
            cnt2 <= cnt2 + 1;
    end
    end
    
    assign add_cnt2 = state_c == WR_DATA && end_cnt1;
    assign end_cnt2 = state_c == WR_DATA && add_cnt2 && cnt2== 8-1;
 //**********sclk生成************// 
    wire    sclk_high;
    wire    sclk_low ;  
    always  @(posedge clk or negedge rst_n)begin   
        if(!rst_n)begin   
            sclk <=1'b0 ;     //初始化   
        end   
        else if(sclk_high)begin   
            sclk <= 1'b1;   
        end  
        else if(sclk_low)begin  
            sclk <= 1'b0;  
        end  
    end  
    assign  sclk_high = state_c != IDLE && add_cnt && cnt==0;   
    assign  sclk_low  = state_c != IDLE && add_cnt && cnt==DIV_2;  
  //**********sdi生成************//end_cn
    wire  [23:0] config_data;
    wire  [7:0]  first_address;   
    wire  [15:0] dout [7:0];


    `define VIO_OPERATE    1
    //`define MANUAL_OPERATE 2
    
    `ifdef  VIO_OPERATE
        vio_0 your_instance_name (
          .clk(clk),                // input wire clk
          .probe_out0(config_data),  // output wire [23 : 0] probe_out0
          .probe_out1(first_address),  // output wire [7 : 0] probe_out1
          .probe_out2(dout[0]),  // output wire [15 : 0] probe_out2
          .probe_out3(dout[1]),  // output wire [15 : 0] probe_out3
          .probe_out4(dout[2]),  // output wire [15 : 0] probe_out4
          .probe_out5(dout[3]),  // output wire [15 : 0] probe_out5
          .probe_out6(dout[4]),  // output wire [15 : 0] probe_out6
          .probe_out7(dout[5]),  // output wire [15 : 0] probe_out7
          .probe_out8(dout[6]),  // output wire [15 : 0] probe_out8
          .probe_out9(dout[7])  // output wire [15 : 0] probe_out9
        );
     `elsif MANUAL_OPERATE
         //assign       dout = 16'hC000;  
     assign config_data = 24'h030A2C;
     assign first_address = 8'h14;
     assign dout = '{16'hf00f,16'hff00,16'hff00,
                     16'hff00,16'hf00f,16'h0fff,
                     16'hffff,16'hff00};
     `endif       
    always  @(posedge clk or negedge rst_n)begin   
        if(!rst_n)begin   
            da_sdi <=1'b0 ;     //初始化   
        end   
        else if(state_c == SPICONFIG && sclk_high)begin   
            da_sdi <= config_data[23-cnt1];   
        end
        else if(state_c == WR_ADRESS && sclk_high)begin   
            da_sdi <= first_address[7-cnt1];   
        end
        else if(state_c == WR_DATA   && sclk_high)begin   
            da_sdi <= dout[cnt2][15-cnt1];   
        end
        else if(state_c == IDLE)begin
            da_sdi <= 1'b0;
        end       
        else 
            da_sdi <= da_sdi;   
    end      
  //**********cs生成************//  
    always  @(posedge clk or negedge rst_n)begin   
      if(!rst_n)begin   
          cs <= 1'b1 ;     //初始化   
      end   
      else if(state_c == SPICONFIG | state_c == WR_ADRESS)begin   
          cs <= 1'b0;  
      end  
      else if(state_c == IDLE) begin  
          cs <= 1'b1;  
      end  
  end  
  
//    adc  adc_inst(
//     .clk     (clk),
//     .rst_n   (rst_n),
//     .din     (rdata),
//     .din_vld (rdata_vld),
//     .volt    (),
//     .sign    ()
//     );  
 
endmodule
