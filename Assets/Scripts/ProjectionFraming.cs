using UnityEngine;

namespace Debris
{

    [ExecuteAlways]
    [RequireComponent(typeof(Camera))]
    public class ProjectionFraming : MonoBehaviour
    {
        [SerializeField, Tooltip("World width to fill the frame. Match the sim's World Size.")]
        float fitWidth = 7f;

        Camera _cam;
        float _lastAspect = -1f;
        float _lastWidth = -1f;

        void OnEnable() => Apply();
        void OnValidate() => Apply();

        void Update()
        {
            if (_cam == null || !Mathf.Approximately(_cam.aspect, _lastAspect)
                || !Mathf.Approximately(fitWidth, _lastWidth))
                Apply();
        }

        void Apply()
        {
            if (_cam == null)
                _cam = GetComponent<Camera>();
            if (_cam == null)
                return;

            _cam.orthographic = true;
            _lastAspect = Mathf.Max(_cam.aspect, 1e-3f);
            _lastWidth = fitWidth;

            _cam.orthographicSize = fitWidth / (2f * _lastAspect);
        }
    }
}
