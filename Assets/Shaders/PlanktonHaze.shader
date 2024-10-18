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

            float _TurbSteepness;
            float _TurbVelocity;
            float _TurbShearWeight;
            float _TurbFoamWeight;
            float _TurbBreakWeight;
            float4 _SurfDyeTex_TexelSize;
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

                float rough = lerp(_CalmRoughness, _TurbRoughness, turb);
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

                total *= _BioEnabled;

                float3 bio = lerp(_BaseEmissionColor.rgb, _HighlightColor.rgb, saturate(total * 1.6));
                col += bio * total * _BloomContribution;

                return float4(col * _Exposure, 1.0);
            }
            ENDCG
        }
    }
}
