catch {list_cable} e0
catch {download -bit {E:/AnLU_QianSai/HDMI2-EG4S20_New/HDMI2-EG4S20/bitstream/HDMI2_HDMI14_Player_v79d.bit} -mode program_spi -v -spd 8 -sec 64 -cable 0 -flashsize 128} e1
puts "FLASH_RC=$e1"
exit 0
