Shader "Hidden/Debris/ExcitationSim"
{
    Properties
    {
        _MainTex ("Previous State", 2D) = "black" {}
    }
    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"
            #include "SurfCommon.cginc"

            #define TAU 6.28318530718

            float4 _TrainA[6];
            int _TrainCount;
            float _WaveSpeed;
            float _RefDepth;
            float _BreakIndex;
            float _BreakSharp;
            float _BoreDecay;
            float _FoamTrail;
            float _FoamFloor;
            float _VelScale;
            float _UOverC;
            float _BoreSpeed;
            float _LongshoreCurrent;
            float _WindPeriod;
            float _Obliquity;
            float _SurfFade;
            float _Groupiness;
            float _SetLength;
            float _StokesGain;

            struct appdata { float4 vertex : POSITION; float2 uv : TEXCOORD0; };
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            float SetAmp(float index, float train)
            {
                float n = SurfFbm(float2(index / max(_SetLength, 0.5), train * 9.3));
                return lerp(1.0, 0.25 + 1.60 * n, _Groupiness);
            }

            float4 frag(v2f i) : SV_Target
            {
                float2 uv = i.uv;
                float t = _SurfTime;

                float bed = SurfBed(uv);
                float h = max(-bed, 0.0);
                float hl = SurfLinDepth(uv);
                float vs = SurfShoreV(uv.x);
                float hs = max(h, 0.004);

                float eta = 0.0;
                float2 vel = 0.0;
                float roller = 0.0;

                float fade = smoothstep(0.0, _SurfFade, h);

                float celLocal = _WaveSpeed * sqrt(hs);

                float stokes = 0.0;

                float swell = clamp((SurfFbm(float2(t / max(_WindPeriod, 1.0), 3.1)) - 0.5) * 3.0,
                                    -1.0, 1.0);

                [unroll]
                for (int wi = 0; wi < 6; wi++)
                {
                    if (wi >= _TrainCount)
                        break;

                    float4 P = _TrainA[wi];
                    float period = max(P.x, 0.05);
                    float w = TAU / period;

                    float tau = 2.0 * sqrt(max(hl, 0.0)) / max(_WaveSpeed * _BeachSlope, 1e-3);

                    float along = P.w * _Obliquity * SurfRefract(hs, _RefDepth);
                    float phi = w * (t + tau) + along * uv.x + P.z;
                    float fr = frac(phi / TAU);

                    float H0 = P.y * SetAmp(floor(phi / TAU + 0.5), wi);

                    float shoal = pow(max(_RefDepth / hs, 1.0), 0.25);
                    float Hu = H0 * shoal;
                    float Hb = _BreakIndex * hs;
                    float ratio = Hu / max(Hb, 1e-4);
                    float broken = saturate((ratio - 1.0) * _BreakSharp);
                    float amp = 0.5 * min(Hu, Hb);

                    float c01 = 0.5 + 0.5 * cos(phi);
                    float peak = pow(max(c01, 0.0), lerp(1.0, 3.5, saturate(ratio)));
                    float rise = smoothstep(0.90, 1.00, fr);
                    float saw = max(1.0 - fr, rise);
                    float shape = lerp(peak, saw, broken);
                    float wave = amp * (2.0 * shape - 1.0) * fade;

                    eta += wave;

                    float cel = celLocal;
                    float uorb = wave / hs * cel;
                    vel.y -= uorb;

                    float aoh = amp / hs;
                    stokes += _StokesGain * aoh * aoh * cel * fade;
                    vel.x += uorb * P.w * _Obliquity;

                    float behind = fr;
                    float ahead = (1.0 - fr) * 6.0;

                    float trail = max(exp(-min(behind, ahead) / max(_FoamTrail, 1e-3)), _FoamFloor);

                    float fresh = exp(-max(ratio - 1.0, 0.0) * _BoreDecay);

                    float shallow = saturate(_RefDepth * 0.3 / max(hs, 1e-4));
                    float roll = broken * fresh * trail * fade * shallow;

                    roller = roller + roll - roller * roll;

                    vel.y -= roll * _BoreSpeed * cel;
                    vel.x += broken * _LongshoreCurrent * swell * fade;
                }

                vel.y -= min(stokes, 0.15 * celLocal);

                float etaMax = max(_BreakIndex * hs, 1e-4);
                eta = etaMax * tanh(eta / etaMax);

                float depth = max(h + eta, 0.0);
                float2 water = vel;

                float rollOut = saturate(roller);

                water *= _VelScale;

                float vmax = _UOverC * celLocal * _VelScale;
                water = SurfLimit(water, vmax);

                return float4(depth, water.x, water.y, rollOut);
            }
            ENDCG
        }
    }
}
