{
  lib,
  stdenvNoCC,
  libretro-shaders-slang,
}:
import ./mk_shader_pack.nix { inherit lib stdenvNoCC libretro-shaders-slang; } {
  name = "shader_pack";
  description = "A collection of RetroArch slang shaders for various platforms";
  shaders = {
    crt = {
      reference = "crt/newpixie-crt.slangp";
      overrides = {
        blur_x = "0.750000";
        blur_y = "0.750000";
        curvature = "0.000100";
      };
    };
    psp = {
      reference = "presets/handheld-plus-color-mod/lcd-grid-v2-psp-color.slangp";
    };
    ds = {
      reference = "presets/handheld-plus-color-mod/lcd-grid-v2-dslite-color.slangp";
    };
    gba = {
      passes = [
        { shader = "handheld/shaders/color/lut/GBA-LUT.slang"; }
        {
          shader = "handheld/shaders/lcd3x.slang";
          scaleTypeX = "viewport";
          scaleTypeY = "viewport";
        }
        { shader = "handheld/shaders/color/gba-color.slang"; }
        {
          shader = "handheld/shaders/pixel_transparency/pixel_transparency.slang";
          scaleTypeX = "viewport";
          scaleTypeY = "viewport";
        }
      ];
      textures = {
        SamplerLUT1.path = "handheld/shaders/color/lut/gba-grey1.png";
        SamplerLUT2.path = "handheld/shaders/color/lut/gba-grey2.png";
      };
      params = {
        # pixel_transparency
        PT_ACCEL_ENABLE = "0.000000";
      };
    };
    gbc = {
      passes = [
        { shader = "handheld/shaders/color/lut/GBC-LUT.slang"; }
        {
          shader = "handheld/shaders/lcd3x.slang";
          scaleTypeX = "viewport";
          scaleTypeY = "viewport";
        }
        { shader = "handheld/shaders/color/gbc-color.slang"; }
        {
          shader = "handheld/shaders/pixel_transparency/pixel_transparency.slang";
          scaleTypeX = "viewport";
          scaleTypeY = "viewport";
        }
      ];
      textures = {
        SamplerLUT1.path = "handheld/shaders/color/lut/gbc-grey1.png";
        SamplerLUT2.path = "handheld/shaders/color/lut/gbc-grey2.png";
      };
      params = {
        LUT_selector_param = "2.000000";
        # pixel_transparency
        PT_ACCEL_ENABLE = "0.000000";
      };
    };
  };
}
