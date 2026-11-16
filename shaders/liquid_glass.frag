#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uBend;
uniform float uChromatic;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 position = FlutterFragCoord().xy;
  vec2 uv = position / uSize;

#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif

  vec2 centered = uv - vec2(0.5);
  float edgeDistance = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  float edgeLens = 1.0 - smoothstep(0.015, 0.22, edgeDistance);
  float lensBody = smoothstep(0.12, 0.68, length(centered));
  vec2 direction = normalize(centered + vec2(0.0001, 0.0001));

  // A small radial displacement bends the sampled scene at the glass rim.
  // The secondary channel offset gives the edge a faint, restrained dispersion.
  vec2 bend = direction * (edgeLens * (0.70 + lensBody * 0.30) * uBend) / uSize;
  vec2 split = direction * (edgeLens * uChromatic) / uSize;
  vec2 warped = clamp(uv + bend, vec2(0.001), vec2(0.999));

  vec4 base = texture(uTexture, warped);
  float red = texture(uTexture, clamp(warped + split, vec2(0.001), vec2(0.999))).r;
  float blue = texture(uTexture, clamp(warped - split, vec2(0.001), vec2(0.999))).b;

  float fresnel = pow(edgeLens, 2.1);
  float upperSheen = exp(-pow((uv.y - 0.045) / 0.055, 2.0)) * (1.0 - smoothstep(0.0, 0.28, uv.x));
  vec3 refracted = vec3(red, base.g, blue);
  refracted = mix(refracted, vec3(0.91, 0.95, 1.0), fresnel * 0.10 + upperSheen * 0.035);

  fragColor = vec4(refracted, base.a);
}
