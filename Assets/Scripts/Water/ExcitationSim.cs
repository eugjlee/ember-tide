using UnityEngine;

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

        [Header("Turbulence")]
        [SerializeField, Range(0f, 12f), Tooltip("Stokes drift gain. 1 is the physical value")]
        float stokesGain = 1f;

        [Header("Physical")]
        [SerializeField, Range(0.3f, 1.2f), Tooltip("Depth limited breaking index H/h")]
        float breakThreshold = 0.78f;
        [SerializeField, Tooltip("Water shallower than this counts as swash")]
        float swashDepthMax = 0.020f;
        [SerializeField] float swashSpeedThreshold = 0.05f;
        [SerializeField, Range(0f, 4f)] float shearSensitivity = 1f;
        [SerializeField, Range(0.005f, 0.3f), Tooltip("Velocity contrast that counts as turbulence")]
        float shearThreshold = 0.05f;

        [Header("Disturbance Weights")]
        [SerializeField, Range(0f, 2f)] float wFoam = 0.85f;
        [SerializeField, Range(0f, 2f)] float wBreak = 0.60f;
        [SerializeField, Range(0f, 2f)] float wSwash = 0.60f;
        [SerializeField, Range(0f, 2f)] float wShear = 0.35f;

        RenderTexture _water;
        RenderTexture _mask;
        Material _mat;
        const int MaxTrains = 6;
        readonly Vector4[] _trains = new Vector4[MaxTrains];

        static readonly int MainTexId = Shader.PropertyToID("_MainTex");
        static readonly int SurfWaterTexId = Shader.PropertyToID("_SurfWaterTex");
        static readonly int SurfMaskTexId = Shader.PropertyToID("_SurfMaskTex");
        static readonly int SurfAreaId = Shader.PropertyToID("_SurfArea");
        static readonly int SurfTimeId = Shader.PropertyToID("_SurfTime");
        static readonly int DisturbWeightsId = Shader.PropertyToID("_DisturbWeights");

        void OnEnable()
        {
            _water = MakeRt();
            _mask = MakeRt();
            Clear(_water);
            Clear(_mask);

            _mat = new Material(Shader.Find("Hidden/Debris/ExcitationSim"));
            BuildTrains();
            PushGlobals();
        }

        void OnDisable()
        {
            if (_water != null) _water.Release();
            if (_mask != null) _mask.Release();
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

            Graphics.Blit(Texture2D.blackTexture, _water, _mat, 0);
            Shader.SetGlobalTexture(SurfWaterTexId, _water);

            Graphics.Blit(_water, _mask, _mat, 1);
            Shader.SetGlobalTexture(SurfMaskTexId, _mask);
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

            _mat.SetFloat("_StokesGain", stokesGain);

            _mat.SetFloat("_BreakThreshold", breakThreshold);
            _mat.SetFloat("_BreakRollerGain", 1.4f);
            _mat.SetFloat("_SteepGain", steepnessGain);
            _mat.SetFloat("_SwashDepthMax", swashDepthMax);
            _mat.SetFloat("_SwashSpeedThreshold", swashSpeedThreshold);
            _mat.SetFloat("_ShearSensitivity", shearSensitivity);
            _mat.SetFloat("_ShearThreshold", shearThreshold);
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
