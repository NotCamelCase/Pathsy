`ifndef __DEFINES_SVH__
`define __DEFINES_SVH__

// FP core latencies
// May I NOT need modifying this again... Amen.
`define LATENCY_FP32_COMPARE    1
`define LATENCY_CVT_FP32_QNM    2
`define LATENCY_CVT_QNM_FP32    3
`define LATENCY_FP32_ADDER      5
`define LATENCY_FP32_MULTIPLIER 6
`define LATENCY_FP32_SQRT       15
`define LATENCY_FP32_RSQRT      16
`define LATENCY_VEC3_DOT        (`LATENCY_FP32_MULTIPLIER + 2 * `LATENCY_FP32_ADDER)
`define LATENCY_VEC3_NORMALIZE  (`LATENCY_VEC3_DOT + `LATENCY_FP32_RSQRT + `LATENCY_FP32_MULTIPLIER)

// Rays per pixel
`define RPP                     64 // must be >= 16
`define RPP_WIDTH               $clog2(`RPP)

`define MAX_BOUNCES             4
`define BOUNCES_WIDTH           $clog2(`MAX_BOUNCES)

// Frame buffer resolution
`define SCREEN_WIDTH            640
`define SCREEN_HEIGHT           480

`define FB_MAX_ADDR             (`SCREEN_WIDTH * `SCREEN_HEIGHT)
`define FB_ADDR_WIDTH           $clog2(`FB_MAX_ADDR)

// Bit widths of pixel coordinates 
`define PX_WIDTH                $clog2(`SCREEN_WIDTH)
`define PY_WIDTH                $clog2(`SCREEN_HEIGHT)

// Stratified sample positions precision
`define SAMPLE_POS_WIDTH        11

`define NUM_SPHERES             7 // must be >= 2
`define SPHERES_WIDTH           $clog2(`NUM_SPHERES)

`define MATERIAL_DIFFUSE        1'b0
`define MATERIAL_SPECULAR       1'b1

// For finer-control of DSP usage within FP cores
typedef enum {
    FULL,
    MED,
    LOW
} DSP_USAGE;

// FP comparison op
typedef enum {
    LT,
    LTE,
    EQ,
    GT,
    GTE,
    NE  
} OP_CMP;

// Raw fp32
typedef logic[31:0] fp32_t;

// Packed vec3 definition
typedef struct packed {
    fp32_t  x;
    fp32_t  y;
    fp32_t  z;
} vec3_t;

// Packed ray definition
typedef struct packed {
    vec3_t  origin;
    vec3_t  dir;
} ray_t;

// Packed sample position definition
typedef struct packed {
    // Q0.11 per-sample offsets in [0, 1.0)
    logic[`SAMPLE_POS_WIDTH-1:0]  pos_y;
    logic[`SAMPLE_POS_WIDTH-1:0]  pos_x;
} sample_pos_t;

// Packed sphere definition
typedef struct packed {
    vec3_t  center;
    fp32_t  radius_squared;
} sphere_t;

// Packed HitInfo definition
typedef struct packed {
    logic                       hit;
    logic[`SPHERES_WIDTH-1:0]   sphere_id;
    fp32_t                      t;
    vec3_t                      sphere_center;
    ray_t                       ray;
} hit_info_t;

// Packed MaterialInfo definition
typedef struct packed {
    vec3_t  emission;
    vec3_t  albedo;
} material_info_t;

`endif