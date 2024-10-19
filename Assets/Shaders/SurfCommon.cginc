#ifndef SURF_COMMON_INCLUDED
#define SURF_COMMON_INCLUDED

float SurfHash21(float2 p)
{
    float3 q = frac(float3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return frac((q.x + q.y) * q.z);
}

float2 SurfHash22(float2 p)
{
    float3 q = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return frac((q.xx + q.yz) * q.zy);
}

float SurfVNoise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);

    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return lerp(
        lerp(SurfHash21(i), SurfHash21(i + float2(1, 0)), f.x),
        lerp(SurfHash21(i + float2(0, 1)), SurfHash21(i + float2(1, 1)), f.x), f.y);
}

float SurfFbm(float2 p)
{
    return 0.533 * SurfVNoise(p)
         + 0.300 * SurfVNoise(p * 2.13 + 7.7)
         + 0.167 * SurfVNoise(p * 4.71 + 13.1);
}

float SurfCells(float2 p)
{
    float2 ip = floor(p);
    float2 fr = frac(p);
    float f1 = 8.0;
    [unroll]
    for (int cy = -1; cy <= 1; cy++)
    [unroll]
    for (int cx = -1; cx <= 1; cx++)
    {
        float2 g = float2(cx, cy);
        float2 o = SurfHash22(ip + g);
        float2 r = g + o - fr;
        f1 = min(f1, dot(r, r));
    }
    return saturate(1.0 - sqrt(f1));
}

float SurfRipple(float2 uv, float t, float scale, float amp, float speed)
{
    float2 sq = float2(0.32, 1.0);
    float h;
    h  = 0.600 * (SurfVNoise(uv * scale * sq
                + float2(0.09, -0.31) * t * speed) - 0.5);
    h += 0.200 * (SurfVNoise(uv * scale * sq * 2.17 + 7.3
                + float2(-0.17, 0.23) * t * speed * 1.6) - 0.5);
    h += 0.070 * (SurfVNoise(uv * scale * sq * 4.63 + 19.1
                + float2(0.27, 0.11) * t * speed * 2.4) - 0.5);
    h += 0.025 * (SurfVNoise(uv * scale * sq * 9.11 + 41.7
                + float2(-0.07, -0.19) * t * speed * 3.1) - 0.5);
    return h * amp;
}

float2 SurfLimit(float2 v, float vmax)
{
    float s = length(v);
    if (s < 1e-6 || vmax < 1e-6)
        return v;
    return v * (vmax * tanh(s / vmax) / s);
}

float SurfCapsule(float2 uv, float4 seg, float radius)
{
    float2 pa = uv - seg.xy;
    float2 ba = seg.zw - seg.xy;
    float k = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    float d = length(pa - ba * k);
    float m = saturate(1.0 - d / max(radius, 1e-4));
    return m * m;
}

float _SurfTime;
float _ShoreV;
float _CoastTilt;
float _BeachSlope;
float _ShoreRough;
float _BarAmp;
float _BarV;
float _BarWidth;

float SurfShoreV(float u)
{
    return _ShoreV
         + _CoastTilt * (u - 0.5)
         + (SurfFbm(float2(u * 2.1, 5.3)) - 0.5) * _ShoreRough
         + (SurfFbm(float2(u * 5.7, 19.1)) - 0.5) * _ShoreRough * 0.55
         + (SurfFbm(float2(u * 13.3, 31.7)) - 0.5) * _ShoreRough * 0.22;
}

float SurfBed(float2 uv)
{
    float vs = SurfShoreV(uv.x);
    float bed = -(uv.y - vs) * _BeachSlope;

    float bv = vs + (_BarV - _ShoreV)
             + (SurfFbm(float2(uv.x * 3.3, 11.7 + _SurfTime * 0.006)) - 0.5) * 0.12;
    float q = (uv.y - bv) / max(_BarWidth, 1e-3);
    bed += _BarAmp * exp(-q * q);
    return bed;
}

float SurfStillDepth(float2 uv)
{
    return max(-SurfBed(uv), 0.0);
}

float SurfLinDepth(float2 uv)
{
    return max(uv.y - SurfShoreV(uv.x), 0.0) * _BeachSlope;
}

float SurfRefract(float depth, float refDepth)
{
    return sqrt(saturate(depth / max(refDepth, 1e-4)));
}

float SurfFoamDetail(float2 p)
{
    float2 w = float2(SurfFbm(p * 1.6 + 3.1), SurfFbm(p * 1.6 + 11.7)) - 0.5;
    p += w * 0.95;

    float m = 1.0;
    m *= 1.0 - 0.88 * smoothstep(0.43, 0.63, SurfFbm(p));
    m *= 1.0 - 0.72 * smoothstep(0.45, 0.65, SurfFbm(p * 2.6 + 19.3));
    m *= 1.0 - 0.55 * smoothstep(0.47, 0.67, SurfFbm(p * 6.4 + 41.1));

    m *= 0.50 + 0.80 * SurfFbm(p * 21.0 + 7.7);
    return saturate(m);
}

sampler2D _SurfWaterTex;
sampler2D _SurfMaskTex;
sampler2D _SurfPersistTex;
sampler2D _SurfDyeTex;
float4 _SurfArea;
float4 _DisturbWeights;
float _AmbientDensity;
float2 _SurfDyeTexel;

float SurfDisturbance(float4 mask)
{
    return saturate(dot(mask, _DisturbWeights));
}

float SurfSpawnDensity(float2 uv)
{
    float hist = tex2Dlod(_SurfPersistTex, float4(uv, 0, 0)).g;
    float4 mask = tex2Dlod(_SurfMaskTex, float4(uv, 0, 0));
    float depth = tex2Dlod(_SurfWaterTex, float4(uv, 0, 0)).r;
    float wet = smoothstep(0.0, 0.004, depth);

    float drive = saturate(mask.r * 1.25 + mask.a * 0.85 + mask.g * 0.30);
    drive = max(drive, hist * 0.5);

    float dens = pow(drive, 1.6) * 2.60;

    dens += _AmbientDensity * wet * (1.0 - saturate(drive * 2.5));

    float patch = SurfCells(uv * 55.0 + float2(0.0, -_SurfTime * 0.25));
    patch *= 0.55 + 0.45 * SurfCells(uv * 17.0 + float2(0.0, -_SurfTime * 0.05));
    return saturate(dens * (0.62 + 0.60 * patch) * wet);
}

float SurfElevation(float2 uv, float depth)
{
    return SurfBed(uv) + depth;
}

#endif
