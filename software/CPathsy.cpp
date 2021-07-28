#include "MathLib.h"
#include "Utils.h"

// Screen resolution
constexpr uint32_t  g_cImageWidth  = 640u;
constexpr uint32_t  g_cImageHeight = 480u;

struct Pixel
{
    uint8_t r;
    uint8_t g;
    uint8_t b;
}                   g_FrameBuffer[g_cImageWidth * g_cImageHeight];

constexpr uint32_t  g_cMaxBounces  = 4;

constexpr uint32_t  g_cNumSpheres = 7;
Sphere              g_Spheres[g_cNumSpheres];

enum MaterialType
{
    DIFFUSE = 0,
    SPECULAR = 1
};

struct MaterialInfo
{
    MaterialType    type;
    Vec3            albedo;
    Vec3            emission;
}                   g_Materials[g_cNumSpheres];

struct HitInfo
{
    bool        hit;
    uint8_t     sphereID;
    float       t;
    Vec3        sphereCenter;
    Ray         ray;
};

// Output pathsy_c.ppm file
void OutputFrame();

// Given (x, y) pixel coordinates and sample offset s,
// generate a ray to shoot through the sample s
Ray GeneratePrimaryRay(uint32_t x, uint32_t y, SamplePos samplePos);

// Compute ray-sphere intersection
void RaySphereIntersect(const Ray& ray, const Vec3& center, float radius2, float& t0, float& t1);

// Shading routines
Vec3 ShadeDiffuse(float r1, float r2);
Vec3 ShadeSpecular(const Vec3& n, float ndotd);

int main(int argc, char *pArgv[])
{
    SamplePos samplePos[g_cRaysPerPixel];

    uint8_t gammaLUT[256];

    srand(0xbeef);

    // Populate sample pos LUT
    GenerateSamplePattern(samplePos);

    // Populate Gamma LUT
    GenerateGammaLUT(gammaLUT);

    // Initialize scene objects (only spheres)
    {
        g_Spheres[0] = Sphere{Vec3{0, 100.5, -1}, 10000 /*radius_squared*/};     // Bottom
        g_Spheres[1] = Sphere{Vec3{0, 0, -2.5}, .25 /*radius_squared*/};          // cs
        g_Spheres[2] = Sphere{Vec3{-.75, .20, -1}, .09 /*radius_squared*/};      // ls
        g_Spheres[3] = Sphere{Vec3{0, -125.5, -1}, 100 /*radius_squared*/};        // Light
        g_Spheres[4] = Sphere{Vec3{-6.25, -2, -7.25}, 56.25 /*radius_squared*/};   // Left
        g_Spheres[5] = Sphere{Vec3{6.25, -2, -7.25}, 56.25 /*radius_squared*/};    // Right
        g_Spheres[6] = Sphere{Vec3{.6, .15, -1}, 0.1225 /*radius_squared*/};     // rs

        // Print sphere geometry data matching RTL layout
        // for (int i = 0; i < g_cNumSpheres; i++)
        // {
        //     const auto& s = g_Spheres[i];
        //     std::cout << "Sphere #" << i << std::endl;
        //     std::cout << FloatToBinaryStr(s.center.x)
        //               << FloatToBinaryStr(s.center.y)
        //               << FloatToBinaryStr(s.center.z)
        //               << FloatToBinaryStr(s.radiusSquared) << std::endl;
        // }

        g_Materials[0] = MaterialInfo{DIFFUSE, Vec3{.5, .5, .25}, Vec3{0, 0, 0}};
        g_Materials[1] = MaterialInfo{DIFFUSE, Vec3{1, 1, 0}, Vec3{0, 0, 0}};
        g_Materials[2] = MaterialInfo{SPECULAR, Vec3{.5, .5, .5}, Vec3{0, 0, 0}};
        g_Materials[3] = MaterialInfo{DIFFUSE, Vec3{0, 0, 0}, Vec3{12, 12, 12}};
        g_Materials[4] = MaterialInfo{DIFFUSE, Vec3{.25, .75, .5}, Vec3{0, 0, 0}};
        g_Materials[5] = MaterialInfo{DIFFUSE, Vec3{.125, .5, .75}, Vec3{0, 0, 0}};
        g_Materials[6] = MaterialInfo{DIFFUSE, Vec3{.85, 0.225, .7}, Vec3{0, 0, 0}};

        // Print materials data matching RTL layout
        // for (int i = 0; i < g_cNumSpheres; i++)
        // {
        //     const auto& material = g_Materials[i];
        //     std::cout << FloatToBinaryStr(material.emission.x)
        //               << FloatToBinaryStr(material.emission.y)
        //               << FloatToBinaryStr(material.emission.z)
        //               << FloatToBinaryStr(material.albedo.x)
        //               << FloatToBinaryStr(material.albedo.y)
        //               << FloatToBinaryStr(material.albedo.z) << std::endl;
        // }
    }

    // Compute a radiance value for each pixel of the screen
    for (uint32_t y = 0; y < g_cImageHeight; ++y)
    {
        for (uint32_t x = 0; x < g_cImageWidth; ++x)
        {
            Vec3 F[g_cRaysPerPixel];
            Vec3 L[g_cRaysPerPixel];

            Ray primaryRayBuffer[g_cRaysPerPixel];
            Ray secondaryRayBuffer[g_cRaysPerPixel];

            bool noHit = false;

            for (uint32_t bounceIdx = 0; (bounceIdx < g_cMaxBounces) && (!noHit); bounceIdx++)
            {
                HitInfo hitInfoBuffer[g_cRaysPerPixel]; // Implicit reset per bounce

                bool anyHit = false; // If there was any hits in this bounce

                bool firstBounce = (bounceIdx == 0); // One bounce w/ primary rays mandatory

                // Ray generation stage: Generate primary rays for the first bounce
                if (firstBounce)
                {
                    for (uint32_t rayIdx = 0; rayIdx < g_cRaysPerPixel; rayIdx++)
                    {
                        Ray primRay = GeneratePrimaryRay(x, y, samplePos[rayIdx]);
                        primaryRayBuffer[rayIdx] = primRay;

                        //std::cout << "rayNdx " << rayIdx << std::endl;
                        //std::cout << std::hex << "ray.dir.x: " << FloatAsUint(primRay.dir.x) << std::endl;
                        //std::cout << std::hex << "ray.dir.y: " << FloatAsUint(primRay.dir.y) << std::endl;
                        //std::cout << std::hex << "ray.dir.z: " << FloatAsUint(primRay.dir.z) << std::endl;
                    }
                }

                // Tracing stage: Find the closest intersection, if any
                for (uint32_t rayIdx = 0; rayIdx < g_cRaysPerPixel; rayIdx++)
                {
                    HitInfo hitInfo;

                    // Fetch computed ray
                    const Ray& nextRay = firstBounce ? primaryRayBuffer[rayIdx]
                                                     : secondaryRayBuffer[rayIdx];

                    for (uint32_t objIdx = 0; objIdx < g_cNumSpheres; objIdx++)
                    {
                        // Fetch sphere geometry
                        const Sphere& sphere = g_Spheres[objIdx];

                        // Check ray-sphere intersection
                        float t0, t1;
                        RaySphereIntersect(nextRay, sphere.center, sphere.radiusSquared, t0, t1);

                        if (objIdx == 0)
                        {
                            // First object, invalidate the entry
                            hitInfo.hit = false;
                            hitInfo.t = MAX_FLOAT;
                        }

                        constexpr float HIT_EPSILON = 1e-4;

                        // Check if the intersection is valid & nearest hit so far
                        bool t0Vld = (t0 > HIT_EPSILON) && (t0 < hitInfo.t);
                        bool t1Vld = (t1 > HIT_EPSILON) && (t1 < hitInfo.t);
                        bool hit = t0Vld || t1Vld;

                        anyHit = hit ? true : anyHit;

                        hitInfo.t = hit ? (t0Vld ? t0 : t1) : hitInfo.t;
                        hitInfo.hit = hit ? true : hitInfo.hit;
                        hitInfo.sphereID = hit ? objIdx : hitInfo.sphereID;
                        hitInfo.sphereCenter = hit ? sphere.center : hitInfo.sphereCenter;
                        hitInfo.ray = nextRay;
                    }

                    // Update ray hit info
                    hitInfoBuffer[rayIdx] = hitInfo;
                }

                // Shading stage: Shade object and compute next ray to trace
                for (uint32_t rayIdx = 0; rayIdx < g_cRaysPerPixel; rayIdx++)
                {
                    const HitInfo& hitInfo = hitInfoBuffer[rayIdx];
                    const MaterialInfo& material = g_Materials[hitInfo.sphereID];

                    Vec3 p = ComputeHitPoint(hitInfo.ray, hitInfo.t);
                    Vec3 nRaw = ComputeSphereNormal(p, hitInfo.sphereCenter);

                    // Surface normal pointing inward or outward
                    float ndotd = Vec3Dot(nRaw, hitInfo.ray.dir);
                    Vec3 n = (ndotd < 0.f) ? nRaw : Vec3Mul(nRaw, -1.f);

                    // [0, 1] -> [-1, 1]
                    float r1 = ((float)rand() / (0.5f * RAND_MAX)) - 1.f;
                    // [0, 1] -> [0, 2pi]
                    float r2 = ((float)rand() / (0.5f * M_1_PI * RAND_MAX));

                    // Compute next ray to be traced
                    Vec3 rayDirDiffuse = ShadeDiffuse(r1, r2);
                    Vec3 rayDirSpecular = ShadeSpecular(n, ndotd);
                    Vec3 newRayDir = Vec3Add(/*Mux Vec3Add inputs based on the shading type*/
                        (material.type == DIFFUSE) ? n : hitInfo.ray.dir,
                        (material.type == DIFFUSE) ? rayDirDiffuse : rayDirSpecular);

                    Ray newRay;
                    newRay.origin = Vec3Add(p, Vec3Mul(n, 1e-3)); // Fix for self-intersecting geometry
                    newRay.dir = Vec3Normalize(newRayDir);

                    // Set the ray for the next bounce
                    secondaryRayBuffer[rayIdx] = hitInfo.hit ? newRay : Ray{/*non-hittable ray*/};

                    Vec3 albedo = hitInfo.hit ? material.albedo : Vec3{0, 0, 0};
                    Vec3 emission = hitInfo.hit ? material.emission : Vec3 {.5, .7, 1.};

                    // Fetch current radiance/color values
                    Vec3 Lp = firstBounce ? Vec3{0, 0, 0} : L[rayIdx];
                    Vec3 Fp = firstBounce ? Vec3{1, 1, 1} : F[rayIdx];

                    // Compute ray color with emissive lighting
                    Vec3 LpNew = Vec3Add(Lp, Vec3Mul(Fp, emission));
                    Vec3 FpNew = Vec3Mul(Fp, albedo);

                    // Update ray color
                    L[rayIdx] = LpNew;
                    F[rayIdx] = FpNew;
                }

                // No hit, no extra bounces
                noHit = !anyHit;
            }

            // Sum up per-ray contributions for current pixel in fixed-point
            uint32_t pr = 0;
            uint32_t pg = 0;
            uint32_t pb = 0;
            for (uint32_t rayIdx = 0; rayIdx < g_cRaysPerPixel; rayIdx++)
            {
                // fp32 -> Q4.9
                uint32_t lr = FloatToFixed(L[rayIdx].x, 9);
                uint32_t lg = FloatToFixed(L[rayIdx].y, 9);
                uint32_t lb = FloatToFixed(L[rayIdx].z, 9);

                // Q9.9 + Q9.9
                pr += lr;
                pg += lg;
                pb += lb;
            }

            // Q9.9 x Q0.6
            constexpr auto f = FloatToFixed(1.f / g_cRaysPerPixel, 6); // Watch out for RPP precision!
            pr *= f;
            pg *= f;
            pb *= f;

            // Q9.15 -> Q0.8 w/ clamping
            pr >>= 7; pr = (pr > 255) ? 255 : pr;
            pg >>= 7; pg = (pg > 255) ? 255 : pg;
            pb >>= 7; pb = (pb > 255) ? 255 : pb;

            // Store gamma-corrected RGB8 pixel
            Pixel p = {
                gammaLUT[(uint8_t)pr],
                gammaLUT[(uint8_t)pg],
                gammaLUT[(uint8_t)pb]
            };
            
            g_FrameBuffer[x + y * g_cImageWidth] = p;
        }
    }

    OutputFrame();

    return 0;
}

void OutputFrame()
{
    FILE *pFile = fopen("pathsy_c.ppm", "w");
    fprintf(pFile, "P3\n%d %d\n%d\n ", g_cImageWidth, g_cImageHeight, 255);
    for (uint32_t y = 0; y < g_cImageHeight; y++)
    {
        for (uint32_t x = 0; x < g_cImageWidth; ++x)
        {
            Pixel p = g_FrameBuffer[x + y * g_cImageWidth];
            fprintf(pFile, "%d %d %d ", p.r, p.g, p.b);
        }
    }

    fclose(pFile);
}

Ray GeneratePrimaryRay(uint32_t x, uint32_t y, SamplePos samplePos)
{
    constexpr float aspectRatio = (float)(g_cImageWidth) / g_cImageHeight;

    constexpr float viewportHeight = 2.f;
    constexpr float viewportWidth = aspectRatio * viewportHeight;

    constexpr Vec3 origin = {0, 0, 0};

    constexpr float cx = -viewportWidth / 2.f;
    constexpr float cy = -viewportHeight / 2.f;
    constexpr float cz = -1.f;

    constexpr float xFactor = viewportWidth / (g_cImageWidth - 1);
    constexpr float yFactor = viewportHeight / (g_cImageHeight - 1);

    // Pixel coordinates
    float px = (float)(x);
    float py = (float)(y);

    // Sample position [0.0, 1.0)
    float sx = FixedToFloat(samplePos.pos_x, g_cSamplePosFraction);
    float sy = FixedToFloat(samplePos.pos_y, g_cSamplePosFraction);

#if 1 // Use fixed-point for intermediate math

    // SQ3.19 + Q10.11 * Q0.24
    // SQ2.19 + Q2.19
    // Q2.19

    int64_t cx21 = FloatToFixed(cx, 19);
    int64_t cy21 = FloatToFixed(cy, 19);
    int64_t cz21 = FloatToFixed(cz, 19);
    int64_t px12 = FloatToFixed(px + sx, g_cSamplePosFraction);
    int64_t py12 = FloatToFixed(py + sy, g_cSamplePosFraction);
    int64_t xfact12 = FloatToFixed(xFactor, 24);
    int64_t yfact12 = FloatToFixed(yFactor, 24);

    float dx = FixedToFloat(cx21 + ((px12 * xfact12) >> 16), 19); 
    float dy = FixedToFloat(cy21 + ((py12 * yfact12) >> 16), 19);
    float dz = FixedToFloat(cz21, 19);
#else
    float dx = cx + (px + sx) * xFactor;
    float dy = cy + (py + sy) * yFactor;
    float dz = cz;
#endif

    // ray direction always normalized
    Vec3 dir = Vec3Normalize({dx, dy, dz});

    Ray ray = {origin, dir};

    return ray;
}

void RaySphereIntersect(
    const Ray& ray,
    const Vec3& center,
    float radius2,
    float& t0,
    float& t1)
{
    Vec3 oc = Vec3Sub(center, ray.origin);
    float b = Vec3Dot(oc, ray.dir);
    float c = radius2 - Vec3Dot(oc, oc);
    float discriminant = b * b + c; // c -> -c for add(b, c)

    float disc = sqrtf(discriminant);
    t0 = b - disc;
    t1 = b + disc;
}

Vec3 ShadeDiffuse(float r1, float r2)
{
    // Compute a vector randomized uniformly around hit point
    float r = sqrtf(1.0f - r1 * r1);
    float x = r * cosf(r2);
    float y = r * sinf(r2);
    Vec3 res = Vec3{x, y, r1};

    return res;
}

Vec3 ShadeSpecular(const Vec3& n, float ndotd)
{
    // Compute ideal mirror reflection
    Vec3 t1 = Vec3Mul(n, ndotd);
    Vec3 t2 = Vec3Mul(t1, -2.f);

    return t2;
}