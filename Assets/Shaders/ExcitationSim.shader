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
            float _SwashSpeed;
            float _SwashDepth;
            float _SwashRough;
            float _SwashTaper;
            float _SwashFront;
            float _SwashLimit;
            float _SurfFade;
            float _Groupiness;
            float _SetLength;
            float _CollisionGain;
            float _RipStrength;
            float _RipCount;
            float _RipThreshold;
            float _RipReach;
            float _RipFeed;
            float _EddyStrength;
            float _EddyScale;
            float _StokesGain;
            float4 _StirSeg;
            float2 _StirDir;
            float _StirRadius;
            float _StirStrength;
            float4 _Splash[8];
            float _SplashSpeed;
            float _SplashReach;
            float _SplashWidth;
            float _SplashPush;
            float _SplashTurb;

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

            float2 EddyVel(float2 uv, float t, float amp)
            {
                float e = 0.35;
                float2 q = uv * _EddyScale + float2(0.0, -t * 0.05);
                float dy = SurfFbm(q + float2(0.0, e)) - SurfFbm(q - float2(0.0, e));
                float dx = SurfFbm(q + float2(e, 0.0)) - SurfFbm(q - float2(e, 0.0));
                return float2(dy, -dx) * amp;
            }

            float RipChannel(float u, float widen)
            {

                float n = SurfFbm(float2(u * _RipCount, 3.7 + _SurfTime * 0.005));
                float thr = _RipThreshold - widen;
                return smoothstep(thr, thr + 0.24, n);
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

                float sheet = 0.0;
                float2 sheetVel = 0.0;
                float sheetRoll = 0.0;
                float uprush = 0.0;
                float backwash = 0.0;

                [unroll]
                for (int si = 0; si < 6; si++)
                {
                    if (si >= _TrainCount)
                        break;

                    float4 P = _TrainA[si];
                    float period = max(P.x, 0.05);

                    float cycRaw = t / period + P.z / TAU
                                 + P.w * _Obliquity * SurfRefract(_SurfFade, _RefDepth) * uv.x / TAU;
                    float cyc = frac(cycRaw);
                    float base = floor(cycRaw);

                    [unroll]
                    for (int k = 0; k < 2; k++)
                    {
                        float setA = SetAmp(base - k, si);

                        float u0 = _SwashSpeed
                                 * (0.35 + 1.30 * SurfFbm(float2(uv.x * 2.3 + si * 9.1, t * 0.04)))
                                 * setA;
                        float dur = period * 1.35;
                        float ge = 2.0 * u0 / dur;
                        float age = (cyc + k) * period;
                        if (age > dur)
                            continue;

                        float disp = max(u0 * age - 0.5 * ge * age * age, 0.0);
                        float edgeSpeed = u0 - ge * age;

                        float limit = max(_SwashLimit * (0.6 + 0.4 * setA), 1e-4);
                        float comp = exp(-disp / limit);
                        disp = limit * (1.0 - comp);
                        edgeSpeed *= comp;

                        float edgeV = vs - disp
                                    + (SurfFbm(float2(uv.x * 9.0 + si * 4.4, t * 0.12)) - 0.5) * _SwashRough
                                    + (SurfFbm(float2(uv.x * 23.0 + si * 7.7, t * 0.25)) - 0.5) * _SwashRough * 0.6;

                        float behind = uv.y - edgeV;
                        float body = saturate(behind / max(_SwashTaper, 1e-3));
                        float onBeach = smoothstep(vs + 0.05, vs - 0.01, uv.y);
                        float alive = saturate(1.0 - age / dur);
                        float lens = body * onBeach * smoothstep(0.0, 0.004, behind);
                        float th = _SwashDepth * setA * lens * (0.35 + 0.65 * alive);

                        float edgeBand = saturate(1.0 - abs(behind) / max(_SwashFront, 1e-3));
                        float frontFrag = 0.15 + 0.85 * smoothstep(0.30, 0.72,
                            SurfFbm(float2(uv.x * 26.0 + si * 3.3, t * 0.4)));
                        float turb = (0.55 + 0.45 * edgeBand * frontFrag)
                                   * saturate(abs(edgeSpeed) / max(_SwashSpeed, 1e-3))
                                   * body * onBeach;

                        float rel = edgeSpeed / max(_SwashSpeed, 1e-3);
                        uprush = max(uprush, lens * saturate(rel));
                        backwash = max(backwash, lens * saturate(-rel));

                        if (th > sheet)
                        {
                            sheet = th;

                            sheetVel = float2(0.0, -edgeSpeed) * body;
                        }
                        sheetRoll = max(sheetRoll, turb);
                    }
                }

                sheetRoll = max(sheetRoll, saturate(uprush * backwash * _CollisionGain));

                float depth = max(h + eta, 0.0);
                float2 water = vel;

                float pump = 0.0;
                [unroll]
                for (int pi = 0; pi < 6; pi++)
                {
                    if (pi >= _TrainCount)
                        break;
                    float4 Pp = _TrainA[pi];
                    float pper = max(Pp.x, 0.05);
                    pump += SetAmp(floor((t - pper * 1.5) / pper + Pp.z / TAU), pi);
                }
                pump /= max((float)_TrainCount, 1.0);

                float head = (uv.y - vs) / max(_RipReach, 1e-3);
                float widen = 0.16 * saturate(head - 0.55);
                float chan = RipChannel(uv.x, widen);

                float du = 0.006;
                float feed = clamp((RipChannel(uv.x + du, widen) - RipChannel(uv.x - du, widen)) * 3.0, -1.0, 1.0);

                float jet = saturate(head * 1.6) * exp(-max(head - 1.0, 0.0) * 4.0);

                float surfZone = 1.0 - smoothstep(_RefDepth * 0.25, _RefDepth * 0.5, hs);
                float ripV = chan * jet * _RipStrength * pump * fade * surfZone;

                water.y += ripV;
                water.x += feed * _RipFeed * _RipStrength * pump
                         * saturate(1.0 - head) * fade * surfZone;

                float sheetW = smoothstep(0.0, max(_SwashDepth * 0.9, 1e-3), sheet)
                             * smoothstep(vs + 0.07, vs - 0.03, uv.y);
                depth = max(depth, sheet);
                water = lerp(water, sheetVel, sheetW);

                float rollOut = saturate(roller + sheetRoll * 1.15 + ripV * 1.5);

                float wetHere = step(0.0002, depth);

                float drag = SurfCapsule(uv, _StirSeg, _StirRadius) * wetHere;
                water += drag * _StirDir;

                float2 splashVel = 0.0;
                float splashRoll = 0.0;
                float splashEta = 0.0;

                [unroll]
                for (int k = 0; k < 8; k++)
                {
                    float4 S = _Splash[k];

                    float life = _SplashReach / max(_SplashSpeed, 1e-3);
                    float age = t - S.z;
                    if (S.w <= 0.0 || age < 0.0 || age > life)
                        continue;

                    float2 dvec = uv - (S.xy + water * age * 1.5);
                    float r = length(dvec);
                    float2 rdir = r > 1e-5 ? dvec / r : float2(0.0, 1.0);

                    float2 acirc = float2(rdir.x, rdir.y);
                    float lobe = 0.75 + 0.50 * SurfFbm(acirc * 2.3 + S.z * 3.1);
                    float patch = 0.45 + 0.80 * SurfFbm(acirc * 6.1 + S.z * 7.7);

                    float rf = _SplashSpeed * age * lobe;
                    float q = (r - rf) / max(_SplashWidth, 1e-3);
                    float band = exp(-q * q);

                    float left = saturate(1.0 - rf / max(_SplashReach, 1e-4));
                    float atten = S.w * patch * left * left
                                / sqrt(max(rf / 0.02, 1.0));

                    float interior = smoothstep(0.0, max(rf, 1e-3), r)
                                   * (1.0 - smoothstep(rf, rf + _SplashWidth * 2.0, r));
                    splashVel += rdir * max(band, interior * 0.6) * atten * _SplashPush;
                    splashRoll = max(splashRoll, band * atten * _SplashTurb);
                    splashEta += band * atten * 0.004;
                }

                water += splashVel * wetHere;
                rollOut = saturate(rollOut + splashRoll * wetHere);
                depth += splashEta * wetHere;

                water += EddyVel(uv, t, _EddyStrength * rollOut) * fade * surfZone;

                water *= _VelScale;

                float vmax = lerp(_UOverC * celLocal, _SwashSpeed * 1.5, sheetW) * _VelScale;
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
            float _FoamSensitivity;

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

                float foamRaw = tex2D(_SurfPersistTex, uv).r;
                float foamGrain = 0.30 + 0.90 * SurfCells(uv * float2(90.0, 55.0) + float2(0.0, -t * 0.25));
                foamGrain *= 0.45 + 0.55 * SurfFbm(uv * float2(26.0, 18.0) - float2(0.0, t * 0.15));
                float foamMask = saturate(foamRaw * _FoamSensitivity * foamGrain);

                return float4(saturate(breakMask), foamMask, saturate(swashMask), shearMask);
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

            float _Dt;
            float _DecayTime;
            float _HistoryDiffusion;
            float _FoamLife;
            float _FoamAdvect;
            float _WetLife;
            float _RechargeTime;
            float _Depletion;

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

                float4 water = tex2D(_SurfWaterTex, uv);
                float4 mask = tex2D(_SurfMaskTex, uv);
                float2 vel = water.gb;

                float2 back = uv - vel * _Dt * _FoamAdvect;
                back = clamp(back, 0.001, 0.999);
                float4 prevAdv = tex2D(_MainTex, back);
                float4 prev = tex2D(_MainTex, uv);

                float foam = prevAdv.r * exp(-_Dt / max(_FoamLife, 0.01));
                foam = max(foam, saturate(water.a * 1.15 + mask.r * 0.35));
                foam = saturate(foam);

                float disturbance = SurfDisturbance(mask);

                float rec = _Dt / max(_RechargeTime, 0.05);
                float fuel = saturate(prevAdv.a + rec * (1.0 - prevAdv.a) - disturbance * rec * 1.2);
                float emitted = disturbance * lerp(1.0, fuel, _Depletion);

                float hist = max(emitted, prevAdv.g * exp(-_Dt / max(_DecayTime, 0.01)));

                if (_HistoryDiffusion > 0.0001)
                {
                    float nb = tex2D(_MainTex, back + float2(tx.x, 0)).g
                             + tex2D(_MainTex, back - float2(tx.x, 0)).g
                             + tex2D(_MainTex, back + float2(0, tx.y)).g
                             + tex2D(_MainTex, back - float2(0, tx.y)).g;
                    hist = lerp(hist, max(hist, nb * 0.25), _HistoryDiffusion);
                }

                float wetNow = smoothstep(0.0, 0.006, water.r);
                float wet = max(wetNow, prev.b * exp(-_Dt / max(_WetLife, 0.01)));

                return float4(foam, saturate(hist), saturate(wet), fuel);
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
            float _Dt;
            float _DyeAdvect;
            float _DyeScale;
            float _DyeRenew;

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
                float2 vel = tex2D(_SurfWaterTex, uv).gb;

                float2 back = uv - vel * _Dt * _DyeAdvect;
                float2 d = tex2D(_MainTex, clamp(back, 0.0015, 0.9985)).rg;

                d = saturate(0.5 + (d - 0.5) * 1.04);

                float2 seed = float2(
                    smoothstep(0.34, 0.66, SurfFbm(uv * _DyeScale)),
                    smoothstep(0.34, 0.66, SurfFbm(uv * _DyeScale * 1.7 + 13.7)));
                d = lerp(d, seed, saturate(_Dt / max(_DyeRenew, 0.05)));

                return float4(d, 0.0, 1.0);
            }
            ENDCG
        }
    }
}
