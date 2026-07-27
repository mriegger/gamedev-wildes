# Task 003 - Torches and Casted Shadows

## Updating the games renderer
We are going to add torches to the game that are able to cast soft visible shadows from players and blocks.

Before we do this we need to update the shadow renderer that we currently have, it is set to `gl_compatibility` however since player's can place down multiple torches we need to update it to `forward_plus` (GL only supports a limited amount of light emissive objects).

This change is going to desaturate the game so we will need to saturate and do color grading to bring it back to what it looked like when rendered in `gl_compatibility`.

Use these values:
- Default Environment:
    - Tonemap Mode = 0 (Linear)
    - Tonemap Exposure = 1.0
    - Adjustment Enabled = True
    - Contrast = 1.3
    - Saturation = 1.2
- Terrain Shader:
    - Uniform terrain saturation at 1.1
    - Terrain contrast at 1.3
    - IMPORTANT: We will need to clamp the values for the terrain to prevent blown out colors. These values are given, look at the code snippet below.

    ```
    float luminance = dot(albedo, vec3(0.21, 0.72, 0.072));
    albedo = mix(vec3(luminance), albedo, terrain_saturation);
    albedo = clamp(albedo, 0, 1);
    albedo = (albedo - 0.5) * terrain_contrast + 0.5; clamp;
    ```
This change also updated the way the sun/moon shadows are rendered from the camera. We will need to change the `SHADOW_MODE` to `SHADOW_ORTHOGONAL` mode.

Once this section is implemented, open the game headless and check for any warnings or errors. Once this section is good to go, follow the next set of requirements.

## Implement the torches and casted shadows
We will add a new type of block called "Torch" which is in similar style to Minecraft's torch. The Torch should be a walk throughable block.

The torch will be a light emissive block that will light up a 9 block radius. The torch is able to cast shadows on blocks and players.

A user can theoretically have an infinite amount of torches in the viewable play area so we need to make sure that torch visuals and storage are cheap and not resource intensive.

## Technical Constraints
- Godot 4.7
- No External Assets

## Acceptance Criteria
- The game is able to run headless
- No additional features have been added besides the ones stated here.
