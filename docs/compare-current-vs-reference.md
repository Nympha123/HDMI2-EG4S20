# current tree vs reference variant (2026-10-14 18:37)

ours: C:\Users\30685\Desktop\HDMI2\src\user_source\hdl_source   (files: 41)
ref : C:\Users\30685\Desktop\HDMI2\_incoming\src\user_source\hdl_source   (files: 35)

## identical after LF-normalisation: 20
audio_arc_calculate.v, audio_source_mux.v, fat32_find_file.v, fifo_prefetch_2.v, hdmi_phy_warpper.v, I2S_receiver.v, key_remove_shakes.v, lane_lvds_10_1.v, media_hdmi_audio_bridge.v, media_sdram_write_cdc.v, pcm_content_mux.v, reset_sync.v, rotary_brightness.v, startup_pulse.v, sync_2ff.v, sync_fade_gain.v, video_fade_transition.v, video_rgb_to_axis_640x480.v, video_source_test.v, wav_stream_player.v

## only in ours: 6
bilinear_8q8.v, brightness_contrast_adjust.v, colour_fade_adjust.v, font_rom.v, param_menu_controller.v, thumbnail_layout.v

## only in reference (we do not have): 0


## different content: 15
- fast_boot_gate.v: ours 33 lines / ref 36 lines
- hdmi_audio_tone_i2s_64fs.v: ours 129 lines / ref 132 lines
- hdmi_audio_tone_pcm_scale.v: ours 87 lines / ref 89 lines
- main_menu.v: ours 624 lines / ref 558 lines
- media_frame_loader.v: ours 286 lines / ref 306 lines
- media_frame_reader.v: ours 529 lines / ref 529 lines
- media_player_control.v: ours 181 lines / ref 183 lines
- osd_overlay_24.v: ours 75 lines / ref 90 lines
- promax_audio_waveform.v: ours 199 lines / ref 202 lines
- rgb_video_adapter.v: ours 41 lines / ref 57 lines
- status_osd_overlay.v: ours 103 lines / ref 120 lines
- subtitle_frame_commit.v: ours 64 lines / ref 69 lines
- subtitle_overlay.v: ours 679 lines / ref 660 lines
- top_tf_hdmi_audio.v: ours 1327 lines / ref 1328 lines
- video_timing_ctrl.v: ours 50 lines / ref 63 lines
