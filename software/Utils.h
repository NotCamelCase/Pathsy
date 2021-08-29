#pragma once

#include <iostream>
#include <fstream>
#include <bitset>

#include "MathLib.h"

// Remember to re-generate ROMs!
constexpr uint32_t  g_cRaysPerPixel = 64;
constexpr uint32_t  g_cSamplePosFraction = 11;
constexpr bool      g_cSaveSamplePosROM = false;
constexpr bool      g_cUpdateGammaROM = false;

struct SamplePos
{
    uint64_t    pos_x : g_cSamplePosFraction;
    uint64_t    pos_y : g_cSamplePosFraction;
};

uint32_t FloatAsUint(float f)
{
    return *(reinterpret_cast<uint32_t*>(&f));
}

auto FloatToBinaryStr(float f)
{
    return std::bitset<32>(FloatAsUint(f));
}

constexpr int64_t FloatToFixed(float f, uint32_t frac)
{
    return (int64_t)(f * (float)(1 << frac));
}

constexpr float FixedToFloat(int64_t i, uint32_t frac)
{
    return i / (float)(1 << frac);
}

float RandomFloatOffline()
{
    // [0., 1.)
    return (float)rand() / RAND_MAX;
}

// Populate sample pos array and output the LUT
void GenerateSamplePattern(SamplePos* pSamplePos)
{
    // Used the algorithm from Correlated Multi-Jittered Sampling paper below
    // https://graphics.pixar.com/library/MultiJitteredSampling/paper.pdf

    std::fstream lut;
    if (g_cSaveSamplePosROM)
        lut.open("sample_pos.mem", std::fstream::binary | std::fstream::out);

    struct SamplePattern
    {
        float   x;
        float   y;
    } pattern[g_cRaysPerPixel]; // Temp buffer

    // Generate canonical sample pattern
    const uint32_t N = sqrtf(g_cRaysPerPixel);
    for (size_t j = 0; j < N; j++)
    {
        for (size_t i = 0; i < N; i++)
        {
            pattern[j * N + i].x = (i + (j + RandomFloatOffline()) / N) / N;
            pattern[j * N + i].y = (j + (i + RandomFloatOffline()) / N) / N;
        }
    }
    
    // Shuffle the generated sample pattern first in X, then Y
    for (size_t j = 0; j < N; j++)
    {
        int k = j + RandomFloatOffline() * (N - j);
        for (size_t i = 0; i < N; i++)
        {
            std::swap(pattern[j * N + i].x, pattern[k * N + i].x);
        }
    }

    for (size_t i = 0; i < N; i++)
    {
        int k = i + RandomFloatOffline() * (N - i);
        for (size_t j = 0; j < N; j++)
        {
            std::swap(pattern[j * N + i].y, pattern[j * N + k].y);
        }
    }

    // Convert sample pattern to fixed-point
    for (uint32_t i = 0; i < g_cRaysPerPixel; i++)
    {
        SamplePos s = {};
        s.pos_x = FloatToFixed(pattern[i].x, g_cSamplePosFraction);
        s.pos_y = FloatToFixed(pattern[i].y, g_cSamplePosFraction);

        pSamplePos[i] = s;

        if (g_cSaveSamplePosROM) // Write out binary value
            lut << std::bitset<g_cSamplePosFraction*2>(*(uint64_t*)(&s)) << std::endl;
    }

    if (g_cSaveSamplePosROM)
        lut.close();
}

void GenerateGammaLUT(uint8_t* pGammaLUT)
{
    std::fstream outGammaLUT;
    if (g_cUpdateGammaROM)
        outGammaLUT.open("gamma_lut.mem", std::fstream::binary | std::fstream::out);

    for (size_t i = 0; i < 256; i++)
    {
        float f = sqrtf(i / 256.f);
        uint8_t g = FloatToFixed(f, 8);
        pGammaLUT[i] = g;

        if (g_cUpdateGammaROM)
            outGammaLUT << std::bitset<8>(g) << std::endl;
    }

    if (g_cUpdateGammaROM)
        outGammaLUT.close();
}