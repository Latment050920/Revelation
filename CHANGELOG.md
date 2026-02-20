# Changelog

## Unreleased

### Added
- New quality preset system: `QUALITY_PRESET` (`LITE`, `BALANCED`, `ULTRA`) with matching shader profiles.
- New shadow tuning options:
  - `SHADOW_FILTER_SCALE`
  - `SHADOW_SOFTNESS`
  - `SHADOW_BIAS_PRESET`
  - `SHADOW_TEMPORAL_STABILITY`
- New AO stability option: `AO_TEMPORAL_STABILITY`.
- New post options:
  - `BLOOM_THRESHOLD`
  - `BLOOM_CLAMP`
  - `TONEMAP_CONTRAST`
  - `EXPOSURE_STABILITY`
- Added upgrade documentation: `docs/lighting-shadow-upgrade.md`.

### Changed
- Improved PCSS stability using stable sample rotation blending to reduce shadow shimmering.
- Added adaptive shadow bias logic (slope + sun-angle aware) to reduce acne and Peter-panning.
- Exposure adaptation now limits per-frame jumps and smooths transitions.
- Bloom composition now includes threshold and clamp safeguards.
- AO/Shadow/Volumetric sampling now scale with quality preset defaults.

### Default updates (BALANCED)
- `QUALITY_PRESET = BALANCED`
- `PCSS_SEARCH_SAMPLES = 8`
- `PCSS_FILTER_SAMPLES = 16`
- `SCREEN_SPACE_SHADOWS_SAMPLES = 16`
- `SSAO_SAMPLES = 12`
- `GTAO_SLICES = 2`
- `GTAO_DIRECTION_SAMPLES = 4`
- `VF_MAX_SAMPLES = 16`
- `UW_VF_MAX_SAMPLES = 16`
