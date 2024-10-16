using UnityEngine;
using UnityEngine.InputSystem;

namespace Debris
{

    public class ExcitationSim : MonoBehaviour
    {
        [Header("Field")]
        [SerializeField] int resolution = 512;
        [SerializeField] float worldSize = 7f;

        [Header("Beach")]
        [SerializeField, Range(0.1f, 0.9f), Tooltip("Mean waterline position across the field")]
        float shorelineV = 0.50f;
        [SerializeField, Range(-0.5f, 0.5f)] float coastTilt = 0.14f;
        [SerializeField, Range(0.05f, 1.5f), Tooltip("Bed gradient: how fast depth grows seaward")]
        float beachSlope = 0.35f;
        [SerializeField, Range(0f, 0.3f)] float shoreRoughness = 0.15f;
        [SerializeField, Tooltip("Sandbar height. Forces waves to break early and in patches")]
        float barAmplitude = 0.014f;
        [SerializeField] float barPosition = 0.62f;
        [SerializeField] float barWidth = 0.08f;

        [Header("Wave Model")]
        [SerializeField, Range(1, MaxTrains), Tooltip("Number of wave trains")]
        int waveTrains = 6;
        [SerializeField, Tooltip("Range of wave periods in seconds")]
        Vector2 wavePeriod = new Vector2(4f, 9f);
        [SerializeField, Tooltip("Offshore wave height in depth units")]
        Vector2 waveHeight = new Vector2(0.028f, 0.042f);
        [SerializeField, Tooltip("Celerity scale. Lower puts more crests in view")]
        float waveSpeed = 0.22f;
        [SerializeField] float referenceDepth = 0.20f;
        [SerializeField, Range(0.5f, 8f)] float breakSharpness = 2.4f;
        [SerializeField, Range(0f, 6f), Tooltip("How fast the bore weakens after breaking")]
        float boreDecay = 0.45f;
        [SerializeField, Range(0f, 0.4f)] float obliquity = 0.06f;
        [SerializeField, Range(0.05f, 1f), Tooltip("How far behind the crest whitewater survives, in wavelengths")]
        float foamTrail = 0.12f;
        [SerializeField, Range(0f, 0.8f), Tooltip("Minimum aeration between crests inside the surf zone")]
        float foamFloor = 0.15f;
        [SerializeField, Range(0f, 1f), Tooltip("Water speed inside a bore as a fraction of the bore front speed")]
        float boreSpeed = 0.6f;
        [SerializeField, Tooltip("Peak strength of the longshore current")]
        float longshoreCurrent = 0.015f;
        [SerializeField, Range(20f, 600f), Tooltip("Seconds over which the swell direction swings")]
        float windShiftPeriod = 110f;
        [SerializeField, Tooltip("Scales wave theory velocity into field units")]
        float velocityScale = 0.7f;
        [SerializeField, Range(0.2f, 2f), Tooltip("Ceiling on u/c for the open sea")]
        float uOverC = 1f;
        [SerializeField, Range(0.1f, 2f)] float steepnessGain = 0.6f;
        [SerializeField] int waveSeed = 4;

        [Header("Wave Groups")]
        [SerializeField, Range(0f, 1f), Tooltip("Height variation between waves. 0 makes every wave identical")]
        float groupiness = 0.75f;
        [SerializeField, Range(1.5f, 12f), Tooltip("Waves per set")]
        float setLength = 4.5f;

        [Header("Rip Currents")]
        [SerializeField, Range(0f, 0.4f), Tooltip("Speed of the seaward jet through the bar gaps")]
        float ripStrength = 0.10f;
        [SerializeField, Range(1f, 10f), Tooltip("How many rip channels across the field")]
        float ripCount = 3.5f;
        [SerializeField, Range(0.3f, 0.9f), Tooltip("Higher gives fewer, narrower channels")]
        float ripThreshold = 0.60f;
        [SerializeField, Range(0.05f, 0.6f), Tooltip("How far seaward the jet reaches before spreading")]
        float ripReach = 0.28f;
        [SerializeField, Range(0f, 2f), Tooltip("Alongshore feeder current running into the channel")]
        float ripFeed = 0.35f;

        [Header("Turbulence")]
        [SerializeField, Range(0f, 12f), Tooltip("Stokes drift gain. 1 is the physical value")]
        float stokesGain = 1f;
        [SerializeField, Range(0f, 2f), Tooltip("Strength of eddies shed by breaking water")]
        float eddyStrength = 0.5f;
        [SerializeField, Range(2f, 40f), Tooltip("Size of those eddies")]
        float eddyScale = 14f;

        [Header("Swash")]
        [SerializeField, Tooltip("Initial runup speed of the swash sheet")]
        float swashSpeed = 0.12f;
        [SerializeField, Tooltip("Thickness of the runup sheet")]
        float swashDepth = 0.012f;
        [SerializeField] float swashRoughness = 0.035f;
        [SerializeField] float swashTaper = 0.05f;
        [SerializeField] float swashFrontWidth = 0.03f;
        [SerializeField, Range(0.02f, 0.35f), Tooltip("Furthest the wash can climb the beach")]
        float swashLimit = 0.12f;

        [Header("Surface Dye")]
        [SerializeField, Range(0f, 16f), Tooltip("How strongly the flow carries the surface texture")]
        float dyeAdvect = 10f;
        [SerializeField, Range(5f, 80f), Tooltip("Grain of the texture the flow stretches")]
        float dyeScale = 28f;
        [SerializeField, Range(0.2f, 8f), Tooltip("How fast texture regenerates. Short smears less, long stretches further")]
        float dyeRenew = 2.2f;

        [Header("Physical")]
        [SerializeField, Range(0.3f, 1.2f), Tooltip("Depth limited breaking index H/h")]
        float breakThreshold = 0.78f;
        [SerializeField, Tooltip("Water shallower than this counts as swash")]
        float swashDepthMax = 0.020f;
        [SerializeField] float swashSpeedThreshold = 0.05f;
        [SerializeField, Range(0f, 4f)] float shearSensitivity = 1f;
        [SerializeField, Range(0.005f, 0.3f), Tooltip("Velocity contrast that counts as turbulence")]
        float shearThreshold = 0.05f;
        [SerializeField, Range(0f, 4f)] float foamSensitivity = 1.35f;
        [SerializeField, Range(0f, 6f), Tooltip("Turbulence thrown up where backwash meets the next bore")]
        float collisionGain = 2.5f;
        [SerializeField, Range(0.1f, 3f), Tooltip("Activation memory half life")]
        float decayTime = 1.1f;
        [SerializeField, Range(0f, 1f), Tooltip("How much cells tire out after firing")]
        float depletion = 0.6f;
        [SerializeField, Range(0.5f, 12f), Tooltip("Time for spent cells to recharge")]
        float rechargeTime = 3f;
        [SerializeField, Range(0f, 0.5f)] float historyDiffusion = 0.05f;
        [SerializeField, Range(0f, 1f)] float surfaceAttachStrength = 0.9f;

        [Header("Disturbance Weights")]
        [SerializeField, Range(0f, 2f)] float wFoam = 0.85f;
        [SerializeField, Range(0f, 2f)] float wBreak = 0.60f;
        [SerializeField, Range(0f, 2f)] float wSwash = 0.60f;
        [SerializeField, Range(0f, 2f)] float wShear = 0.35f;

        [Header("Tracers")]
        [SerializeField] float foamLife = 0.9f;
        [SerializeField] float foamAdvect = 1f;
        [SerializeField] float wetnessLife = 3f;

        [Header("Broad Glow")]
        [SerializeField, Range(0f, 1f)] float broadGlowIntensity = 0.25f;
        [SerializeField] float broadGlowNoiseScaleLarge = 3.5f;
        [SerializeField] float broadGlowNoiseScaleMedium = 11f;
        [SerializeField, Range(0f, 1f), Tooltip("Higher punches more dark holes in the glow")]
        float broadGlowBreakup = 0.45f;
        [SerializeField, Range(0f, 1f)] float broadGlowMaxOpacity = 0.35f;

        [Header("Water Body")]
        [SerializeField, Range(0f, 1f), Tooltip("How hard the flow carves the water into current filaments")]
        float streakStrength = 0.85f;
        [SerializeField, Range(0f, 0.3f), Tooltip("Sparse flashes in calm water beyond the surf")]
        float ambientDensity = 0.010f;

        [Header("Subsurface")]
        [SerializeField, Tooltip("Turn all bioluminescence off")]
        bool bioluminescenceEnabled = true;

        [Header("Appearance")]
        [SerializeField, ColorUsage(false, true)]
        Color baseEmissionColor = new Color(0.06f, 0.42f, 0.95f);
        [SerializeField, ColorUsage(false, true)]
        Color highlightColor = new Color(0.55f, 0.92f, 1f);
        [SerializeField, Range(0f, 3f)] float bloomContribution = 1f;
        [SerializeField, Range(0f, 1f)] float shoreReflectionStrength = 0.25f;

        [Header("Interaction")]
        [SerializeField] bool pointerStir = true;
        [SerializeField, Tooltip("Radius of the contact that drags water along with it")]
        float stirRadius = 0.05f;
        [SerializeField, Tooltip("Strength of each impact")]
        float stirStrength = 0.7f;
        [SerializeField] float minStirSpeed = 0.02f;
        [SerializeField, Range(0.005f, 0.2f), Tooltip("Distance a drag travels between separate impacts")]
        float splashSpacing = 0.03f;
        [SerializeField, Range(0.05f, 1.5f), Tooltip("Speed of the outward bore, in field widths per second")]
        float splashSpeed = 0.16f;
        [SerializeField, Range(0.01f, 0.35f), Tooltip("How far a splash runs, in field widths")]
        float splashReach = 0.055f;
        [SerializeField, Range(0.005f, 0.15f), Tooltip("Thickness of the expanding front")]
        float splashWidth = 0.014f;
        [SerializeField, Range(0f, 0.6f), Tooltip("Outward velocity the impact pushes into the water")]
        float splashPush = 0.16f;
        [SerializeField, Range(0f, 3f), Tooltip("Turbulence carried by the expanding front")]
        float splashTurbulence = 0.55f;

        RenderTexture _water;
        RenderTexture _mask;
        RenderTexture _persistA;
        RenderTexture _persistB;
        RenderTexture _dyeA;
        RenderTexture _dyeB;
        Material _mat;
        const int MaxTrains = 6;
        readonly Vector4[] _trains = new Vector4[MaxTrains];
        Vector2 _prevUv;
        bool _hadPointer;

        const int MaxSplashes = 8;
        readonly Vector4[] _splashes = new Vector4[MaxSplashes];
        int _splashHead;
        Vector2 _lastSplashUv;

        static readonly int MainTexId = Shader.PropertyToID("_MainTex");
        static readonly int SurfWaterTexId = Shader.PropertyToID("_SurfWaterTex");
        static readonly int SurfMaskTexId = Shader.PropertyToID("_SurfMaskTex");
        static readonly int SurfPersistTexId = Shader.PropertyToID("_SurfPersistTex");
        static readonly int SurfDyeTexId = Shader.PropertyToID("_SurfDyeTex");
        static readonly int SurfAreaId = Shader.PropertyToID("_SurfArea");
        static readonly int SurfTimeId = Shader.PropertyToID("_SurfTime");
        static readonly int DisturbWeightsId = Shader.PropertyToID("_DisturbWeights");
        static readonly int SplashArrayId = Shader.PropertyToID("_Splash");

        void OnEnable()
        {
            _water = MakeRt();
            _mask = MakeRt();
            _persistA = MakeRt();
            _persistB = MakeRt();
            _dyeA = MakeRt();
            _dyeB = MakeRt();
            Clear(_water);
            Clear(_mask);
            Clear(_persistA);
            Clear(_persistB);
            Clear(_dyeA);
            Clear(_dyeB);

            _mat = new Material(Shader.Find("Hidden/Debris/ExcitationSim"));
            BuildTrains();
            PushGlobals();
        }

        void OnDisable()
        {
            if (_water != null) _water.Release();
            if (_mask != null) _mask.Release();
            if (_persistA != null) _persistA.Release();
            if (_persistB != null) _persistB.Release();
            if (_dyeA != null) _dyeA.Release();
            if (_dyeB != null) _dyeB.Release();
            if (_mat != null) DestroyImmediate(_mat);
        }

        void OnValidate()
        {
            if (Application.isPlaying && _mat != null)
            {
                BuildTrains();
                PushGlobals();
            }
        }

        void BuildTrains()
        {
            var rng = new System.Random(waveSeed);
            for (int i = 0; i < MaxTrains; i++)
            {
                float u = (float)rng.NextDouble();
                float v = (float)rng.NextDouble();
                float period = Mathf.Lerp(wavePeriod.x, wavePeriod.y, u);

                float height = Mathf.Lerp(waveHeight.x, waveHeight.y, v)
                             * Mathf.Sqrt(3f / Mathf.Max(waveTrains, 1));
                float phase = (float)rng.NextDouble() * Mathf.PI * 2f;
                float along = ((float)rng.NextDouble() - 0.5f) * 2.4f;
                _trains[i] = new Vector4(period, height, phase, along);
            }
        }

        void Update()
        {
            float dt = Mathf.Clamp(Time.deltaTime, 1e-4f, 0.1f);

            PushGlobals();
            UpdateStir(dt);

            _mat.SetFloat("_Dt", dt);

            Graphics.Blit(Texture2D.blackTexture, _water, _mat, 0);
            Shader.SetGlobalTexture(SurfWaterTexId, _water);

            Graphics.Blit(_water, _mask, _mat, 1);
            Shader.SetGlobalTexture(SurfMaskTexId, _mask);

            Graphics.Blit(_persistA, _persistB, _mat, 2);
            (_persistA, _persistB) = (_persistB, _persistA);
            Shader.SetGlobalTexture(SurfPersistTexId, _persistA);

            Graphics.Blit(_dyeA, _dyeB, _mat, 3);
            (_dyeA, _dyeB) = (_dyeB, _dyeA);
            Shader.SetGlobalTexture(SurfDyeTexId, _dyeA);
        }

        public void SplashAtWorld(Vector3 world, float strength)
        {
            Vector2 uv = new Vector2(
                (world.x - transform.position.x) / worldSize + 0.5f,
                (world.z - transform.position.z) / worldSize + 0.5f);
            if (uv.x < 0f || uv.x > 1f || uv.y < 0f || uv.y > 1f)
                return;
            Emit(uv, strength);
        }

        void Emit(Vector2 uv, float strength)
        {
            if (strength <= 0f)
                return;
            _splashes[_splashHead] = new Vector4(uv.x, uv.y, Time.time, strength);
            _splashHead = (_splashHead + 1) % MaxSplashes;
        }

        void UpdateStir(float dt)
        {
            _mat.SetVectorArray(SplashArrayId, _splashes);

            if (!pointerStir || !TryGetPointer(out Vector2 uv, out float speed))
            {
                _mat.SetVector("_StirDir", Vector4.zero);
                _hadPointer = false;
                return;
            }

            if (_hadPointer && speed > minStirSpeed)
            {
                Vector2 delta = uv - _prevUv;
                _mat.SetVector("_StirSeg", new Vector4(_prevUv.x, _prevUv.y, uv.x, uv.y));
                _mat.SetFloat("_StirRadius", stirRadius);
                _mat.SetVector("_StirDir", delta.normalized * Mathf.Clamp(speed, 0f, 2f) * 0.05f);

                if ((uv - _lastSplashUv).magnitude > splashSpacing)
                {
                    Emit(uv, stirStrength * Mathf.Clamp01(speed * 0.6f));
                    _lastSplashUv = uv;
                }
            }
            else
            {
                _mat.SetVector("_StirDir", Vector4.zero);
                if (!_hadPointer)
                    _lastSplashUv = uv;
            }

            _prevUv = uv;
            _hadPointer = true;
        }

        bool TryGetPointer(out Vector2 uv, out float speed)
        {
            uv = _prevUv;
            speed = 0f;

            var mouse = Mouse.current;
            var cam = Camera.main;
            if (mouse == null || cam == null)
                return false;

            var ray = cam.ScreenPointToRay(mouse.position.ReadValue());
            var plane = new Plane(Vector3.up, transform.position);
            if (!plane.Raycast(ray, out float dist))
                return false;

            Vector3 world = ray.GetPoint(dist);
            uv = new Vector2(
                (world.x - transform.position.x) / worldSize + 0.5f,
                (world.z - transform.position.z) / worldSize + 0.5f);

            if (_hadPointer)
                speed = (uv - _prevUv).magnitude / Mathf.Max(Time.deltaTime, 1e-4f);

            return uv.x >= 0f && uv.x <= 1f && uv.y >= 0f && uv.y <= 1f;
        }

        void PushGlobals()
        {
            Shader.SetGlobalVector(SurfAreaId,
                new Vector4(worldSize, worldSize, transform.position.x, transform.position.z));
            Shader.SetGlobalFloat(SurfTimeId, Time.time);
            Shader.SetGlobalVector(DisturbWeightsId, new Vector4(wFoam, wBreak, wSwash, wShear));

            Shader.SetGlobalFloat("_ShoreV", shorelineV);
            Shader.SetGlobalFloat("_CoastTilt", coastTilt);
            Shader.SetGlobalFloat("_BeachSlope", beachSlope);
            Shader.SetGlobalFloat("_ShoreRough", shoreRoughness);
            Shader.SetGlobalFloat("_BarAmp", barAmplitude);
            Shader.SetGlobalFloat("_BarV", barPosition);
            Shader.SetGlobalFloat("_BarWidth", barWidth);

            Shader.SetGlobalColor("_BaseEmissionColor", baseEmissionColor);
            Shader.SetGlobalColor("_HighlightColor", highlightColor);
            Shader.SetGlobalFloat("_BloomContribution", bloomContribution);
            Shader.SetGlobalFloat("_ShoreReflectionStrength", shoreReflectionStrength);
            Shader.SetGlobalFloat("_SurfaceAttachStrength", surfaceAttachStrength);

            Shader.SetGlobalFloat("_BroadGlowIntensity", broadGlowIntensity);
            Shader.SetGlobalFloat("_BroadGlowNoiseLarge", broadGlowNoiseScaleLarge);
            Shader.SetGlobalFloat("_BroadGlowNoiseMedium", broadGlowNoiseScaleMedium);
            Shader.SetGlobalFloat("_BroadGlowBreakup", broadGlowBreakup);
            Shader.SetGlobalFloat("_BroadGlowMaxOpacity", broadGlowMaxOpacity);
            Shader.SetGlobalFloat("_StreakStrength", streakStrength);
            Shader.SetGlobalFloat("_AmbientDensity", ambientDensity);
            Shader.SetGlobalVector("_SurfDyeTexel", new Vector4(1f / resolution, 1f / resolution, 0f, 0f));
            Shader.SetGlobalFloat("_BioEnabled", bioluminescenceEnabled ? 1f : 0f);

            if (_mat == null)
                return;

            _mat.SetVectorArray("_TrainA", _trains);
            _mat.SetInt("_TrainCount", waveTrains);
            _mat.SetFloat("_WaveSpeed", waveSpeed);
            _mat.SetFloat("_RefDepth", referenceDepth);
            _mat.SetFloat("_BreakIndex", breakThreshold);
            _mat.SetFloat("_BreakSharp", breakSharpness);
            _mat.SetFloat("_BoreDecay", boreDecay);
            _mat.SetFloat("_FoamTrail", foamTrail);
            _mat.SetFloat("_FoamFloor", foamFloor);
            _mat.SetFloat("_VelScale", velocityScale);
            _mat.SetFloat("_UOverC", uOverC);
            _mat.SetFloat("_BoreSpeed", boreSpeed);
            _mat.SetFloat("_LongshoreCurrent", longshoreCurrent);
            _mat.SetFloat("_WindPeriod", windShiftPeriod);
            _mat.SetFloat("_Obliquity", obliquity);
            _mat.SetFloat("_SurfFade", 0.012f);

            _mat.SetFloat("_Groupiness", groupiness);
            _mat.SetFloat("_SetLength", setLength);
            _mat.SetFloat("_CollisionGain", collisionGain);

            _mat.SetFloat("_RipStrength", ripStrength);
            _mat.SetFloat("_RipCount", ripCount);
            _mat.SetFloat("_RipThreshold", ripThreshold);
            _mat.SetFloat("_RipReach", ripReach);
            _mat.SetFloat("_RipFeed", ripFeed);
            _mat.SetFloat("_StokesGain", stokesGain);
            _mat.SetFloat("_EddyStrength", eddyStrength);
            _mat.SetFloat("_EddyScale", eddyScale);

            _mat.SetFloat("_SplashSpeed", splashSpeed);
            _mat.SetFloat("_SplashReach", splashReach);
            _mat.SetFloat("_SplashWidth", splashWidth);
            _mat.SetFloat("_SplashPush", splashPush);
            _mat.SetFloat("_SplashTurb", splashTurbulence);

            _mat.SetFloat("_SwashSpeed", swashSpeed);
            _mat.SetFloat("_SwashDepth", swashDepth);
            _mat.SetFloat("_SwashRough", swashRoughness);
            _mat.SetFloat("_SwashTaper", swashTaper);
            _mat.SetFloat("_SwashFront", swashFrontWidth);
            _mat.SetFloat("_SwashLimit", swashLimit);
            _mat.SetFloat("_DyeAdvect", dyeAdvect);
            _mat.SetFloat("_DyeScale", dyeScale);
            _mat.SetFloat("_DyeRenew", dyeRenew);

            _mat.SetFloat("_BreakThreshold", breakThreshold);
            _mat.SetFloat("_BreakRollerGain", 1.4f);
            _mat.SetFloat("_SteepGain", steepnessGain);
            _mat.SetFloat("_SwashDepthMax", swashDepthMax);
            _mat.SetFloat("_SwashSpeedThreshold", swashSpeedThreshold);
            _mat.SetFloat("_ShearSensitivity", shearSensitivity);
            _mat.SetFloat("_ShearThreshold", shearThreshold);
            _mat.SetFloat("_FoamSensitivity", foamSensitivity);

            _mat.SetFloat("_DecayTime", decayTime);
            _mat.SetFloat("_HistoryDiffusion", historyDiffusion);
            _mat.SetFloat("_FoamLife", foamLife);
            _mat.SetFloat("_FoamAdvect", foamAdvect);
            _mat.SetFloat("_WetLife", wetnessLife);
            _mat.SetFloat("_Depletion", depletion);
            _mat.SetFloat("_RechargeTime", rechargeTime);
        }

        RenderTexture MakeRt()
        {
            var rt = new RenderTexture(resolution, resolution, 0, RenderTextureFormat.ARGBHalf)
            {
                wrapMode = TextureWrapMode.Clamp,
                filterMode = FilterMode.Bilinear
            };
            rt.Create();
            return rt;
        }

        static void Clear(RenderTexture rt)
        {
            var prev = RenderTexture.active;
            RenderTexture.active = rt;
            GL.Clear(false, true, Color.clear);
            RenderTexture.active = prev;
        }
    }
}
