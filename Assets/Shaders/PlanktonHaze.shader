Shader "Debris/PlanktonHaze"
{
    Properties
    {
        _Exposure ("Exposure", Range(0, 4)) = 1
    }
    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" }

        Pass
        {
            Blend One One
            ZWrite Off
            Cull Off

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"
            #include "SurfCommon.cginc"

            float _Exposure;
            float _BroadGlowIntensity;
            float _BroadGlowNoiseLarge;
            float _BroadGlowNoiseMedium;
            float _BroadGlowBreakup;
            float _BroadGlowMaxOpacity;
            float4 _BaseEmissionColor;
            float4 _HighlightColor;
            float _BloomContribution;
            float _StreakStrength;

            float4 _DeepWaterColor;
            float4 _SurfaceWaterColor;
            float4 _FoamColor;
            float4 _MoonDir;
            float _MoonDiffuse;
            float _MoonSpecular;
            float _WaterAmbient;
            float _AbsorptionStrength;
            float _ReliefMacro;
            float _ReliefGain;
            float _ReliefEps;
            float _RippleScaleB;
            float _RippleAmpB;
            float _RippleSpeedB;
            float _RippleScaleC;
            float _RippleAmpC;
            float _RippleSpeedC;
            float _CalmRoughness;
            float _TurbRoughness;
            float _FoamRoughness;

            float _FoamCoverage;
            float _FoamContrast;
            float _FoamRenderThreshold;
            float _FoamSoftness;
            float _FoamLargeScale;
            float _FoamMediumScale;
            float _FoamSmallScale;
            float _FoamBrightness;
            float _FoamAdvection;
            float _FoamDyeWeight;

            float _TurbSteepness;
            float _TurbVelocity;
            float _TurbShearWeight;
            float _TurbFoamWeight;
            float _TurbBreakWeight;

            float _BioFoamStrength;
            float _BioFoamInterior;
            float _FoamRimWidth;
            float4 _SurfDyeTex_TexelSize;
            float _FoamCellScale;
            float _BioEnabled;

            struct appdata { float4 vertex : POSITION; float2 uv : TEXCOORD0; };
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            float2 SurfShadeH(float2 uv, float t)
            {
                float d = tex2Dlod(_SurfWaterTex, float4(uv, 0, 0)).r;
                float macro = SurfElevation(uv, d) * _ReliefMacro;

                float detail = SurfRipple(uv, t, _RippleScaleB, _RippleAmpB, _RippleSpeedB);
                detail += SurfRipple(uv + 5.1, t, _RippleScaleC, _RippleAmpC, _RippleSpeedC);
                return float2(macro, macro + detail);
            }

            float SurfFroth(float2 uv, float2 fl, float adv, float small, float med)
            {
                float2 st = fl * adv * 0.28;
                float acc = 0.0;
                float wsum = 0.0;
                [unroll]
                for (int k = 0; k < 4; k++)
                {
                    float w = 1.0 - k * 0.19;
                    float2 p = uv - st * k;
                    float v = 0.45 + 0.55 * SurfCells(p * small * float2(1.25, 1.15) + 5.9);
                    v *= 0.60 + 0.40 * SurfFbm(p * med * 2.3 + 19.7);
                    acc += v * w;
                    wsum += w;
                }

                return saturate((acc / wsum - 0.16) * 1.75);
            }

            float4 frag(v2f i) : SV_Target
            {
                float2 uv = i.uv;
                float t = _SurfTime;

                float4 mask = tex2D(_SurfMaskTex, uv);
                float4 persist = tex2D(_SurfPersistTex, uv);
                float4 water = tex2D(_SurfWaterTex, uv);
                float hist = persist.g;
                float2 fl = water.gb;

                float wet = smoothstep(0.0, 0.004, water.r);

                float inv = 0.5 / max(_ReliefEps, 1e-5);
                float2 e = float2(_ReliefEps, 0.0);
                float2 hxp = SurfShadeH(uv + e.xy, t), hxn = SurfShadeH(uv - e.xy, t);
                float2 hyp = SurfShadeH(uv + e.yx, t), hyn = SurfShadeH(uv - e.yx, t);
                float sx = (hxp.y - hxn.y) * inv;
                float sy = (hyp.y - hyn.y) * inv;
                float3 nrm = normalize(float3(-sx * _ReliefGain, 1.0, -sy * _ReliefGain));

                float macroSteep = length(float2(hxp.x - hxn.x, hyp.x - hyn.x)) * inv;
                float steepAct = saturate(macroSteep * _TurbSteepness);
                float velAct = saturate(length(fl) * _TurbVelocity);
                float turb = saturate(steepAct + velAct
                                    + mask.a * _TurbShearWeight
                                    + mask.g * _TurbFoamWeight
                                    + mask.r * _TurbBreakWeight);

                float2 dt = _SurfDyeTex_TexelSize.xy * 0.75;
                float2 dye = 0.25 * (tex2D(_SurfDyeTex, uv + float2( dt.x,  dt.y)).rg
                                   + tex2D(_SurfDyeTex, uv + float2(-dt.x,  dt.y)).rg
                                   + tex2D(_SurfDyeTex, uv + float2( dt.x, -dt.y)).rg
                                   + tex2D(_SurfDyeTex, uv + float2(-dt.x, -dt.y)).rg);

                float2 fadv = uv - fl * _FoamAdvection;
                float frothTex = SurfFoamRaft(uv, fl, _FoamAdvection, _FoamCellScale);
                float fL = SurfFbm(fadv * _FoamLargeScale);

                float fM = SurfFbm(fadv * _FoamMediumScale * float2(0.55, 1.0) + 11.3);
                float fS = SurfCells(fadv * _FoamSmallScale * float2(0.70, 1.0) + 27.1);

                float fVF = SurfFbm(fadv * _FoamSmallScale * 2.7 + 63.1);

                float dyeE = saturate(dye.r * 0.62 + dye.g * 0.38);
                float statE = fL * 0.30 + fM * 0.42 + fS * 0.18 + fVF * 0.10;
                float erosion = lerp(statE, dyeE, saturate(_FoamDyeWeight));

                float aer = pow(saturate(max(water.a, persist.r)), _FoamContrast);

                float fs = aer * _FoamCoverage - erosion + _FoamRenderThreshold;

                float foam = smoothstep(0.0, max(_FoamSoftness, 1e-3), fs);
                foam *= 0.28 + 0.72 * frothTex;
                foam *= wet;

                float grad = max(fwidth(fs), 1e-6);
                float dpx = fs / grad;
                float rim = exp(-(dpx * dpx) / max(_FoamRimWidth * _FoamRimWidth, 1e-6));

                rim *= wet * smoothstep(0.04, 0.30, aer);

                float2 ag = float2(
                    tex2D(_SurfWaterTex, uv + float2(_SurfDyeTex_TexelSize.x, 0.0)).a
                  - tex2D(_SurfWaterTex, uv - float2(_SurfDyeTex_TexelSize.x, 0.0)).a,
                    tex2D(_SurfWaterTex, uv + float2(0.0, _SurfDyeTex_TexelSize.y)).a
                  - tex2D(_SurfWaterTex, uv - float2(0.0, _SurfDyeTex_TexelSize.y)).a);
                float agl = length(ag);
                float fll = length(fl);
                float lead = 0.35;
                if (agl > 1e-5 && fll > 1e-4)
                    lead = saturate(-dot(ag / agl, fl / fll)) * 0.9 + 0.18;
                rim *= lead;

                float rough = lerp(_CalmRoughness, _TurbRoughness, turb);
                rough = lerp(rough, _FoamRoughness, foam);
                float power = exp2(lerp(8.0, 2.0, saturate(rough)));

                float3 L = normalize(_MoonDir.xyz);
                float3 V = float3(0.0, 1.0, 0.0);
                float3 Hv = normalize(L + V);
                float spec = pow(saturate(dot(nrm, Hv)), power) * _MoonSpecular;
                float diff = saturate(dot(nrm, L)) * _MoonDiffuse;

                float depthF = saturate(water.r * _AbsorptionStrength);
                float3 wcol = lerp(_SurfaceWaterColor.rgb, _DeepWaterColor.rgb, depthF);

                float3 col = wet * (wcol * (_WaterAmbient + diff) + spec);

                float2 drift = float2(0.0, -t * 0.02);
                float n1 = SurfFbm(uv * _BroadGlowNoiseLarge + drift);
                float n2 = SurfFbm(uv * _BroadGlowNoiseMedium * float2(1.0, 0.7) - drift * 2.3);

                float n3 = SurfCells(uv * _BroadGlowNoiseMedium * float2(4.3, 2.6) + drift * 4.0);
                float n4 = SurfCells(uv * _BroadGlowNoiseMedium * float2(9.7, 6.1) + 31.7 - drift * 7.0);

                float patch = n1 * (0.45 + 0.55 * n2);
                patch = smoothstep(_BroadGlowBreakup, _BroadGlowBreakup + 0.30, patch);
                patch *= 0.25 + 0.75 * n3 * (0.4 + 0.6 * n4);

                float glow = hist * mask.g * patch;

                float washGrain = 0.25 + 0.75 * SurfCells(uv * float2(60.0, 36.0) + float2(0.0, -t * 0.2));
                washGrain *= 0.40 + 0.60 * SurfFbm(uv * float2(14.0, 9.0) + drift * 3.0);
                float wash = mask.b * hist * washGrain * 0.8;

                float total = (glow + wash) * _BroadGlowIntensity;
                total = min(total, _BroadGlowMaxOpacity);

                float streak = smoothstep(0.36, 0.72, dye.r);
                streak *= 0.35 + 0.65 * smoothstep(0.28, 0.76, dye.g);

                float coherence = smoothstep(0.03, 0.20, length(fl));

                col *= lerp(1.0, 0.45 + 1.20 * streak, saturate(_StreakStrength) * coherence);

                col += _FoamColor.rgb * foam * frothTex * _FoamBrightness;

                total *= _BioEnabled;

                float work = saturate(0.35 + hist * 0.55 + turb * 0.40);
                float foamBio = (rim + foam * _BioFoamInterior) * frothTex * work;
                col += _HighlightColor.rgb * foamBio * _BioFoamStrength * _BioEnabled;

                float3 bio = lerp(_BaseEmissionColor.rgb, _HighlightColor.rgb, saturate(total * 1.6));
                col += bio * total * _BloomContribution;

                return float4(col * _Exposure, 1.0);
            }
            ENDCG
        }
    }
}
