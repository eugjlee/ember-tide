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

                float3 col = 0.0;

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

                total *= _BioEnabled;

                float3 bio = lerp(_BaseEmissionColor.rgb, _HighlightColor.rgb, saturate(total * 1.6));
                col += bio * total * _BloomContribution;

                return float4(col * _Exposure, 1.0);
            }
            ENDCG
        }
    }
}
