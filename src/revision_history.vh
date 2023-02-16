
//================================================================================================
//    Date         Version     Who  Changes
// -----------------------------------------------------------------------------------------------
// 29-Sep-2022     0.1.0-rc1   DWW  Initial creation
//
// 28-Oct-2022     0.2.0-rc1   DWW  Running at 40 GBit/second.  DMA byte order is fixed and
//                                  restart_manager has been added
//
// 17-Nov-2022     0.3.0-rc1   DWW  Added clock constraint in order to run QSFP at 100 GBit/sec
//                                  Added some ILAs, and added AXI slave to report the status
//                                  bits of the QSFP channels
//================================================================================================
localparam VERSION_MAJOR = 0;
localparam VERSION_MINOR = 3;
localparam VERSION_BUILD = 0;
localparam VERSION_RCAND = 1;

localparam VERSION_DAY   = 17;
localparam VERSION_MONTH = 11;
localparam VERSION_YEAR  = 2022;
