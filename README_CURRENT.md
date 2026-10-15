# HDMI / FPGA lecture merge - current snapshot

## What this snapshot is
A working FPGA HDMI project (Anlogic EG4S20BG256 / TD 6.2) that merges the lecture
series into one design, plus a "page view" feature added on top of the official
single-buffer image-read architecture.

## Current state (this snapshot)
* Image read path = the OFFICIAL single-buffer architecture (top + reader restored to
  the pre-4-bank state). The three extra image banks are no longer displayed.
* Page view: one image per page, shown as a 480x360 crop on the left and vertically
  centred, with the right side reserved for the fixed title ????.
* Entry: EC11 push-button long press (~0.8 s). The counter only arms after the pin has
  been seen released, so it cannot trigger at power-up.
* Inside the page view the info bands / scrolling subtitles are hidden.
* Everything else is unchanged: menu, rotary brightness/contrast, info bands, three
  rotating sentences, audio waveform, I2S audio, 7-segment diagnostics.

## Known open issue
Background (not displayed) image banks slowly develop noise on the board. The mechanism
identified so far: an SDRAM row that is never read slowly loses its charge, so the images
that are not being displayed degrade; re-reading the card clears it. The current snapshot
still has the multi-image SD controller (SD/sd_card_bmp.v), which loads four images, so
three of them stay idle - this is the next thing to fix (revert that controller too).

## Verified bitstreams (in _bits_good)
* G_17730B9F - lesson 14 complete, single-buffer era, board verified.
* G_DCCA3BC8 - this snapshot (single-buffer base + page view), board verified:
  switching, page view and everything else normal; residual noise on idle images only.

## Build numbers
* gate: 7042 registers / 8419 lut   (single-buffer base alone: 7012 / 8243)
* place & route: Setup +207 ps, Hold +25 ps, TNS 0, 0 failing endpoints

## 2026-10-15 update: the SD-chain revert had NO effect (recorded honestly)
The whole SD image-read chain (19 files under hdl_source/SD) was reverted to the
pre-4-bank commit e8f2ee6. The gate came out BIT-IDENTICAL to the previous build
(7042 registers / 8419 lut) and the board behaves the same, so that revert did not
change the synthesised design. Conclusion: the four-image loading is NOT driven by the
files that were reverted; the top still instantiates the newer loader path, i.e. the
state kept as "lesson 14 complete" (e8f2ee6) already contains the multi-bank loader and
is therefore NOT a single-buffer design. The official single-buffer reference lives in
  ????/???.../?1?_????  (SD/sd_card_bmp.v 14.6 KB there vs 51.9 KB in ours)

## Known open issue (parked by request)
Noise grows ONLY on the image banks that are not currently displayed; a card re-read
clears it. Confirmed facts: it appeared with the 4-bank port, the displayed bank never
degrades, and with the newest builds it is much slower and sparser (fewer idle banks
being displayed). Hypotheses still open: idle SDRAM rows losing charge (reads act as
refresh, idle rows do not, and the auto-refresh apparently does not cover them), or a
weak read-path/contention effect. Next time: start from the OFFICIAL single-buffer
example rather than from e8f2ee6.

## Board verdicts so far
* DCCA3BC8 - switching, page view, everything else fully normal; slow sparse noise on
  idle image banks only.
* 6F07FDC1 - identical behaviour to DCCA3BC8 (the SD revert changed nothing).
