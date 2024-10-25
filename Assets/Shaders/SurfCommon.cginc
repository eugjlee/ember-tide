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

float2 SurfCellF1F2(float2 p)
{
    float2 ip = floor(p);
    float2 fr = frac(p);
    float f1 = 8.0;
    float f2 = 8.0;
    [unroll]
    for (int cy = -1; cy <= 1; cy++)
    [unroll]
    for (int cx = -1; cx <= 1; cx++)
    {
        float2 g = float2(cx, cy);
        float2 o = SurfHash22(ip + g);
        float d = length(g + o - fr);
        if (d < f1) { f2 = f1; f1 = d; }
        else if (d < f2) { f2 = d; }
    }
    return float2(f1, f2);
}

float SurfFoamWalls(float2 p, float thickness)
{
    float2 f = SurfCellF1F2(p);
    return 1.0 - smoothstep(0.0, max(thickness, 1e-3), f.y - f.x);
}

float SurfFoamRaft(float2 uv, float2 fl, float adv, float scale)
{
    float2 p = uv - fl * adv;

    float sv = 0.62 + 0.76 * SurfFbm(p * 9.0);

    float w = SurfFoamWalls(p * scale * sv * float2(0.85, 1.0), 0.16);
    w = max(w, SurfFoamWalls(p * scale * sv * 2.7 + 17.3, 0.13) * 0.80);
    w = max(w, SurfFoamWalls(p * scale * sv * 6.3 + 41.7, 0.10) * 0.55);

    w *= 0.35 + 0.85 * SurfFbm(p * scale * 0.55 + 71.3);

    float cover = smoothstep(0.28, 0.74, SurfFbm(p * 14.0 + 5.5));
    return saturate(w * (0.20 + 1.20 * cover));
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

#define MAX_SHORE_WAVES 16
float4 _ShoreWaveA[MAX_SHORE_WAVES];
float4 _ShoreWaveB[MAX_SHORE_WAVES];
int _ShoreWaveCount;

float3 SurfShoreWave(float2 uv, int i)
{
    float4 A = _ShoreWaveA[i];
    float4 B = _ShoreWaveB[i];

    float sd = B.y;
    float halfW = max(A.z, 1e-3);
    float du = abs(uv.x - A.x) / halfW;

    float ragged = 0.70 + 0.62 * SurfFbm(float2(uv.x * 4.0 + sd * 13.7, sd * 5.1));
    float along = 1.0 - smoothstep(0.30 * ragged, 1.10 * ragged, du);
    if (along <= 0.001)
        return float3(0, 0, 0);

    along *= 0.45 + 0.85 * SurfFbm(float2(uv.x * 7.5 + sd * 23.1, sd * 2.7));

    float wob = (SurfFbm(float2(uv.x * 3.2 + sd * 31.7, sd * 7.3)) - 0.5) * 0.085
              + (SurfFbm(float2(uv.x * 9.5 + sd * 11.3, sd * 3.1)) - 0.5) * 0.034
              + (SurfFbm(float2(uv.x * 26.0 + sd * 5.9, sd * 1.7)) - 0.5) * 0.012;
    float v = A.y + wob;

    float d = uv.y - v;

    float frontW = max(B.w, 1e-4);
    float tail = max(B.z, 1e-3);

    float ahead = smoothstep(-frontW, frontW * 0.35, d);
    float body = ahead * exp(-max(d, 0.0) / tail);
    float front = exp(-(d * d) / (frontW * frontW));

    float env = smoothstep(0.0, 0.18, saturate(B.x));

    float amp = A.w * along * env;

    return float3(body * amp,
                  saturate(front * 0.9 + body * 0.42) * amp,
                  front * amp);
}

float3 SurfShoreWaves(float2 uv)
{
    float3 acc = float3(0, 0, 0);
    [loop]
    for (int i = 0; i < _ShoreWaveCount; i++)
    {
        float3 w = SurfShoreWave(uv, i);

        acc.x += w.x;
        acc.y = acc.y + w.y - acc.y * w.y;
        acc.z = max(acc.z, w.z);
    }
    return float3(acc.x, saturate(acc.y), saturate(acc.z));
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
sampler2D _SurfGlowTex;
float4 _SurfArea;
float4 _DisturbWeights;
float _AmbientDensity;
float2 _SurfDyeTexel;
float _SurfFilamentGain;

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

    float aer = saturate(max(tex2Dlod(_SurfWaterTex, float4(uv, 0, 0)).a,
                             tex2Dlod(_SurfPersistTex, float4(uv, 0, 0)).r));
    float dye = tex2Dlod(_SurfDyeTex, float4(uv, 0, 0)).r;

    float erode = SurfFbm(uv * 150.0 * float2(0.45, 1.0)) * 0.42
                + SurfFbm(uv * 430.0 * float2(0.55, 1.0) + 31.7) * 0.28
                + dye * 0.30;
    float fs = aer * 0.88 - erode;
    float w = 0.55 / max(_SurfFilamentGain, 0.5);
    float ridge = exp(-(fs * fs) / max(w * w, 1e-6));

    float dens = pow(drive, 1.6) * (0.035 + 2.60 * ridge);

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
