# SCons options for Ashfen's size-optimised Godot 4.7.2 export template.
# Usage (from a godot 4.7.2-stable source checkout, after
#   python misc/scripts/install_swappy_android.py):
#   scons platform=android target=template_release arch=arm64 profile=<this file>
# Ashfen is a 2D, offline, English-only GDScript game: no 3D, no physics, no
# navigation, no networking, no XR, no complex-script text shaping.
# NOTE: SCons exec()s this file with separate locals, so every option must be
# a plain top-level assignment (no loops writing to globals()).
optimize = "size_extra"
lto = "full"
debug_symbols = False
swappy = True

disable_3d = True
disable_physics_2d = True
disable_physics_3d = True
disable_navigation_2d = True
disable_navigation_3d = True
disable_xr = True

# Fallback text server (no HarfBuzz/ICU). Fine for Latin text and pixel fonts.
module_text_server_adv_enabled = False
module_text_server_fb_enabled = True

# Modules Ashfen doesn't use
module_astcenc_enabled = False
module_basis_universal_enabled = False
module_betsy_enabled = False
module_bmp_enabled = False
module_camera_enabled = False
module_csg_enabled = False
module_cvtt_enabled = False
module_dds_enabled = False
module_enet_enabled = False
module_etcpak_enabled = False
module_fbx_enabled = False
module_glslang_enabled = False
module_gltf_enabled = False
module_godot_physics_2d_enabled = False
module_godot_physics_3d_enabled = False
module_gridmap_enabled = False
module_hdr_enabled = False
module_interactive_music_enabled = False
module_jolt_physics_enabled = False
module_jpg_enabled = False
module_jsonrpc_enabled = False
module_ktx_enabled = False
module_lightmapper_rd_enabled = False
module_meshoptimizer_enabled = False
module_mobile_vr_enabled = False
module_mono_enabled = False
module_mp3_enabled = False
module_msdfgen_enabled = False
module_multiplayer_enabled = False
module_navigation_2d_enabled = False
module_navigation_3d_enabled = False
module_objectdb_profiler_enabled = False
module_openxr_enabled = False
module_raycast_enabled = False
module_tga_enabled = False
module_theora_enabled = True   # 0.3.9.6 title video (res://assets/ui/title_loop.ogv)
module_tinyexr_enabled = False
module_upnp_enabled = False
module_vhacd_enabled = False
module_visual_shader_enabled = False
module_webrtc_enabled = False
module_websocket_enabled = False
module_webxr_enabled = False
module_xatlas_unwrap_enabled = False

# Kept: freetype, gdscript, noise (FastNoiseLite world gen), regex, svg (default
# theme icons), zip, ogg/vorbis (future music), theora (0.3.9.6 title video), webp, bcdec, mbedtls, text_server_fb.
