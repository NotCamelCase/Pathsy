#pragma once

#include <cstdint>
#include <cmath>

#define MAX_FLOAT           3.40282347e+38F
#define ONE_MINUS_EPSILON   (1.f-1.19209290e-7f)

// Vec3 fp32
struct Vec3
{
    float   x;
    float   y;
    float   z;
};

// Ray fp32
struct Ray
{
    Vec3    origin;
    Vec3    dir;
};

// Sphere fp32
struct Sphere
{
    Vec3    center;
    float   radiusSquared;
};

// fp32 a + b
Vec3 Vec3Add(const Vec3& a, const Vec3& b)
{
    Vec3 res;
    res.x = a.x + b.x;
    res.y = a.y + b.y;
    res.z = a.z + b.z;

    return res;
}

// fp32 a - b
Vec3 Vec3Sub(const Vec3& a, const Vec3& b)
{
    Vec3 res;
    res.x = a.x - b.x;
    res.y = a.y - b.y;
    res.z = a.z - b.z;

    return res;
}

// fp32 a * b
Vec3 Vec3Mul(const Vec3& a, const Vec3& b)
{
    Vec3 res;
    res.x = a.x * b.x;
    res.y = a.y * b.y;
    res.z = a.z * b.z;

    return res;
}

// fp32 a * t
Vec3 Vec3Mul(const Vec3& a, float t)
{
    Vec3 res;
    res.x = a.x * t;
    res.y = a.y * t;
    res.z = a.z * t;

    return res;
}

// fp32 dot(a, b)
float Vec3Dot(const Vec3& a, const Vec3& b)
{
    float x = a.x * b.x;
    float y = a.y * b.y;
    float z = a.z * b.z;

    return x + y + z;
}

// fp32 length squared
float Vec3LengthSquared(const Vec3& a)
{
    return Vec3Dot(a, a);
}

// fp32 length
float Vec3Length(const Vec3& a)
{
    const float l2 = Vec3LengthSquared(a);

    return sqrtf(l2);
}

// fp32 normalize
Vec3 Vec3Normalize(const Vec3& a)
{
    const float l = 1.f / Vec3Length(a);

    return Vec3Mul(a, l);
}

Vec3 ComputeHitPoint(const Ray& ray, float t)
{
    Vec3 rt = Vec3Mul(ray.dir, t);
    Vec3 res = Vec3Add(ray.origin, rt);

    return res;
}

Vec3 ComputeSphereNormal(const Vec3& p, const Vec3& c)
{
    Vec3 v = Vec3Sub(p, c);
    Vec3 res = Vec3Normalize(v);

    return res;
}