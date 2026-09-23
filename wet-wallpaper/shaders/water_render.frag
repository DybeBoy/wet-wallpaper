#version 440

// ---------------------------------------------------------------------------
// Water render — fragment shader
//
// Reads the water surface height field and composites a realistic water
// effect over the background image (or a dark blue fallback if no image
// is loaded).
//
// Steps per fragment:
//   1. Sample the wave height field and compute the surface gradient (∇h).
//   2. Add the ambient wind-chop overlay (analytic, independent of ∇h).
//   3. Derive an approximate surface normal from the combined gradient.
//   4. Offset the background UV by the gradient (refraction/distortion).
//   5. Sample the background at the distorted UV.
//   6. Compute a Phong specular highlight for a fixed overhead light.
//   7. Composite and output the final colour.
//
// Uniform block layout — must be identical to water_render.vert:
//   offset   0 : mat4  qt_Matrix
//   offset  64 : float qt_Opacity
//   offset  68 : float distortionStrength  — UV offset scale  (0.0 – 0.05)
//   offset  72 : float specularIntensity   — specular strength (0.0 – 1.0)
//   offset  76 : float texelSize           — 1.0 / simulationResolution
//   offset  80 : float aspectRatio         — screenWidth / screenHeight
//   offset  84 : float ambientAmplitude    — ambient wave height scale (0 = off)
//   offset  88 : float ambientScale        — ambient wave spatial frequency
//   offset  92 : float ambientSpeed        — ambient wave animation speed
//   offset  96 : float ambientDirection    — wind angle, radians
//   offset 100 : float ambientComplexity   — number of stacked octaves (1–4)
//   offset 104 : float time                — elapsed simulated seconds
// ---------------------------------------------------------------------------

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float distortionStrength;
    float specularIntensity;
    float texelSize;
    float aspectRatio;
    float ambientAmplitude;
    float ambientScale;
    float ambientSpeed;
    float ambientDirection;
    float ambientComplexity;
    float time;
};

// Wave height field: R = current height, G = previous height
layout(binding = 1) uniform sampler2D waterState;

// Background: either the user image or a dark-blue rectangle captured by
// a ShaderEffectSource in QML, so this sampler is always valid.
layout(binding = 2) uniform sampler2D bgSource;

// ---------------------------------------------------------------------------
// Continuous low-amplitude "wind chop" layer, independent of the interactive
// ripple simulation. A fixed-4-octave sine stack (pseudo-FBM; no noise
// texture needed) — irrational per-octave angle/frequency offsets keep it
// from visibly tiling or repeating. Manually unrolled (no arrays, no loop):
// some qsb --glsl targets (desktop GLSL 100/OpenGL ES) reject const arrays
// and non-constant loop bounds, so octave count instead fades in/out via a
// per-octave weight. Returns (gradient.xy, height), gradient already
// rescaled to match the finite-difference convention used by the
// interactive ripple gradient below (hR - hL over a texelSize step, not
// divided down).
// ---------------------------------------------------------------------------
vec3 ambientWave(vec2 uv) {
    vec2  p      = vec2(uv.x * aspectRatio, uv.y);
    float height = 0.0;
    vec2  slope  = vec2(0.0);
    float amp    = 1.0;

    float weight, ang, freq, phase;
    vec2  dir;

    weight = clamp(ambientComplexity - 0.0, 0.0, 1.0);
    ang    = ambientDirection + 0.0;
    dir    = vec2(cos(ang), sin(ang));
    freq   = ambientScale * 1.0;
    phase  = dot(dir, p) * freq + time * ambientSpeed * 1.0;
    height += amp * weight * sin(phase);
    slope  += amp * weight * freq * cos(phase) * dir;
    amp    *= 0.55;

    weight = clamp(ambientComplexity - 1.0, 0.0, 1.0);
    ang    = ambientDirection + 0.7;
    dir    = vec2(cos(ang), sin(ang));
    freq   = ambientScale * 2.13;
    phase  = dot(dir, p) * freq + time * ambientSpeed * 2.13;
    height += amp * weight * sin(phase);
    slope  += amp * weight * freq * cos(phase) * dir;
    amp    *= 0.55;

    weight = clamp(ambientComplexity - 2.0, 0.0, 1.0);
    ang    = ambientDirection - 1.3;
    dir    = vec2(cos(ang), sin(ang));
    freq   = ambientScale * 3.72;
    phase  = dot(dir, p) * freq + time * ambientSpeed * 3.72;
    height += amp * weight * sin(phase);
    slope  += amp * weight * freq * cos(phase) * dir;
    amp    *= 0.55;

    weight = clamp(ambientComplexity - 3.0, 0.0, 1.0);
    ang    = ambientDirection + 2.1;
    dir    = vec2(cos(ang), sin(ang));
    freq   = ambientScale * 5.31;
    phase  = dot(dir, p) * freq + time * ambientSpeed * 5.31;
    height += amp * weight * sin(phase);
    slope  += amp * weight * freq * cos(phase) * dir;

    height *= ambientAmplitude;
    slope  *= ambientAmplitude * 2.0 * texelSize;
    return vec3(slope, height);
}

void main() {
    vec2 uv = texCoord;

    // ------------------------------------------------------------------
    // 1.  Compute the surface gradient via central differences.
    //     We sample from the simulation-resolution texture, so the step
    //     size is 1/simRes = texelSize.
    // ------------------------------------------------------------------
    float hL = texture(waterState, uv + vec2(-texelSize,  0.0      )).r;
    float hR = texture(waterState, uv + vec2( texelSize,  0.0      )).r;
    float hU = texture(waterState, uv + vec2( 0.0,       -texelSize)).r;
    float hD = texture(waterState, uv + vec2( 0.0,        texelSize)).r;
    float h  = texture(waterState, uv).r;   // centre height for colour effects

    vec3 ambient = ambientWave(uv);
    h += ambient.z;

    vec2 gradient = vec2(hR - hL, hD - hU) + ambient.xy;

    // Clamp gradient magnitude before using it for UV distortion.
    // Without this, the sharp zero-crossing of the ring impulse creates
    // extreme offsets that visibly tear the background image.
    float gradLen = length(gradient);
    if (gradLen > 0.25) gradient = gradient * (0.25 / gradLen);

    // ------------------------------------------------------------------
    // 3.  Surface normal (water surface tilted by the gradient).
    //     The z-component of 1.0 gives a flat surface at rest.
    //
    //     Uses its own, much tighter clamp than the distortion gradient
    //     above: a freshly injected droplet/click ripple has a very steep
    //     momentary slope, and feeding that straight into the normal makes
    //     the specular highlight below fire across the whole ring at once
    //     (a white flash). Restricting the tilt angle keeps the highlight a
    //     small, crisp glint instead.
    // ------------------------------------------------------------------
    vec2 specGradient = vec2(hR - hL, hD - hU) + ambient.xy;
    float specGradLen = length(specGradient);
    if (specGradLen > 0.08) specGradient = specGradient * (0.08 / specGradLen);
    vec3 normal = normalize(vec3(-specGradient.x, -specGradient.y, 1.0));

    // ------------------------------------------------------------------
    // 4.  Refraction: offset the background UV proportionally to ∇h.
    // ------------------------------------------------------------------
    vec2 distortedUV = clamp(uv + gradient * distortionStrength, 0.0, 1.0);

    // ------------------------------------------------------------------
    // 5.  Sample background at distorted UV.
    // ------------------------------------------------------------------
    vec3 colour = texture(bgSource, distortedUV).rgb;

    // ------------------------------------------------------------------
    // 6a. Wave crest brightening + trough darkening.
    //     Lower threshold (0.03) keeps waves visible at small amplitudes;
    //     reduced multiplier (0.07) avoids the bright white flash on impact.
    // ------------------------------------------------------------------
    colour += vec3(0.85, 0.92, 1.0) * smoothstep(0.03, 0.2, h) * 0.07;
    colour *= 1.0 - smoothstep(-0.4, 0.0, -h) * 0.2;

    // ------------------------------------------------------------------
    // 6b. Phong specular — fixed overhead light from upper-right.
    //     High shininess (96) gives crisp sun-glint points, not a smear.
    // ------------------------------------------------------------------
    vec3 lightDir   = normalize(vec3(0.4, 1.0, 1.2));
    vec3 viewDir    = vec3(0.0, 0.0, 1.0);
    vec3 reflDir    = reflect(-lightDir, normal);
    float spec      = pow(max(dot(reflDir, viewDir), 0.0), 96.0);
    vec3  specColor = vec3(0.75, 0.88, 1.0) * spec * specularIntensity;

    // ------------------------------------------------------------------
    // 7.  Output.  Premultiply alpha as required by Qt Quick.
    // ------------------------------------------------------------------
    vec3 finalColor = colour + specColor;
    fragColor = vec4(finalColor * qt_Opacity, qt_Opacity);
}
