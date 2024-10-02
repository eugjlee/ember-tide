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

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"
            #include "SurfCommon.cginc"

            sampler2D _MainTex;
            float4 _MainTex_TexelSize;

            float _BreakThreshold;
            float _BreakRollerGain;
            float _SteepGain;
            float _SwashDepthMax;
            float _SwashSpeedThreshold;
            float _ShearSensitivity;
            float _ShearThreshold;

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
                float2 tx = _MainTex_TexelSize.xy;
                float t = _SurfTime;

                float4 c = tex2D(_MainTex, uv);
                float4 xp = tex2D(_MainTex, uv + float2(tx.x, 0));
                float4 xm = tex2D(_MainTex, uv - float2(tx.x, 0));
                float4 yp = tex2D(_MainTex, uv + float2(0, tx.y));
                float4 ym = tex2D(_MainTex, uv - float2(0, tx.y));

                float depth = c.r;
                float2 vel = c.gb;
                float roller = c.a;

                float bed = SurfBed(uv);
                float eta = bed + depth;
                float etaXp = SurfBed(uv + float2(tx.x, 0)) + xp.r;
                float etaXm = SurfBed(uv - float2(tx.x, 0)) + xm.r;
                float etaYp = SurfBed(uv + float2(0, tx.y)) + yp.r;
                float etaYm = SurfBed(uv - float2(0, tx.y)) + ym.r;

                float2 grad = float2(etaXp - etaXm, etaYp - etaYm) / (2.0 * tx.y);
                float steep = length(grad);
                float curv = abs(etaXp + etaXm + etaYp + etaYm - 4.0 * eta) / (tx.y * tx.y);

                float steepMask = smoothstep(_BreakThreshold, _BreakThreshold * 2.2, steep * _SteepGain)
                                * saturate(0.45 + curv * 0.006);

                float f1 = SurfFbm(float2(uv.x * 18.0, uv.y * 9.0 - t * 0.35));
                float f2 = SurfFbm(float2(uv.x * 47.0 + 13.0, uv.y * 20.0 - t * 0.6));
                float frag = smoothstep(0.38, 0.64, f1)
                           * (0.25 + 0.75 * smoothstep(0.30, 0.68, f2));

                float breakMask = saturate(roller * _BreakRollerGain + steepMask * 0.6) * frag;

                float shallow = smoothstep(0.0, _SwashDepthMax * 0.30, depth)
                              * (1.0 - smoothstep(_SwashDepthMax * 0.45, _SwashDepthMax, depth));
                float moving = smoothstep(_SwashSpeedThreshold, _SwashSpeedThreshold * 2.6, length(vel));
                float wet = smoothstep(0.0, 0.004, depth);
                float onBeach = smoothstep(-0.02, 0.006, bed);
                float grain = 0.20 + 0.80 * SurfCells(uv * float2(70.0, 42.0) + float2(0.0, -t * 0.15));

                grain *= smoothstep(0.30, 0.62, SurfFbm(uv * float2(9.0, 6.0) + float2(0.0, -t * 0.05)));
                grain *= 0.45 + 0.55 * SurfFbm(uv * float2(16.0, 11.0) + float2(0.0, -t * 0.09));
                float swashMask = wet * shallow * moving * onBeach * grain;

                float shear = length(xp.gb - xm.gb) + length(yp.gb - ym.gb);

                float shearMask = smoothstep(_ShearThreshold, _ShearThreshold * 3.0,
                                            shear * _ShearSensitivity) * wet;

                shearMask *= 0.05 + 0.95 * smoothstep(0.28, 0.70,
                    SurfFbm(float2(uv.x * 30.0, uv.y * 15.0 - t * 0.5)));

                return float4(saturate(breakMask), 0.0, saturate(swashMask), shearMask);
            }
            ENDCG
        }
    }
}
