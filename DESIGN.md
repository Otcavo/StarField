# Design

How Starfield works, and why it's built the way it is. For installing and running it, see [README.md](README.md).

The numbers below are the defaults when this was written. The current values live in the settings at the top of `source/Starfield.swift`.

## Overview

Everything is in one file, `source/Starfield.swift`. It builds two ways from the same code:

- **As a normal program,** compiled without flags. It opens a borderless full-screen window and quits on any input. Used for quick testing.
- **As the screensaver,** compiled with `-D SCREENSAVER`. A `ScreenSaverView` subclass hosts the same view, and macOS handles starting and stopping it.

The main pieces are:

| Piece | Job |
|---|---|
| `loadStars` | Reads the CSV into `Star` values |
| `SpriteLibrary` | Loads sprite sheets and cuts them into images, with placeholders for anything missing |
| `StarfieldView` | Builds all the layers once, then updates them every frame in `step()` |
| `StarfieldSaverView` | Screensaver wrapper: finds resources in the bundle and calls `step()` each frame |
| `StarWindow`, `AppDelegate`, `StarfieldApp` | Standalone program only: the window, input handling and start-up |

## Star data

The data comes from `data/nearest_stars_within_20ly.csv`, adapted from Wikipedia's "List of nearest stars". It holds 133 objects in 95 systems.

- **One row per object:** every star, white dwarf and brown dwarf gets its own row, with its system named in a column. Values the article gives once per system, like distance, are repeated on each member's row.
- **Columns read by name:** the code only looks up the columns it needs (Object, System, Type, Spectral class, RA, Dec, Distance and Flare star), so extra columns and column order don't matter.
- **Hand-written CSV reader:** it handles quoted fields, escaped quotes, a byte-order mark and Windows line endings. That last one matters because Swift treats `\r\n` as a single character.
- **Choosing a sprite:** each star's sprite comes from its type and the first letter of its spectral class:

| Type | Sprite |
|---|---|
| Stars (A, F, G, K) | 32×32, one colour per letter |
| Red dwarfs | 16×16 red |
| White dwarfs | 8×8 blue-white |
| Brown dwarfs | 8×8, by class: L, T or Y |

LSR J1835+3259 is the one oddity. The source counts it as a brown dwarf but gives it a red-dwarf class, so it gets its own small red sprite.

## Placing stars in 3D

- **Position:** right ascension, declination and distance become x, y, z in light-years, with the Sun at the origin. x points towards RA 0h, y towards RA 6h, and z towards the celestial north pole.
- **Rotation:** each frame the scene spins around the celestial pole, one turn every 240 seconds. The pole is tilted 20° towards the viewer, nodding ±8° over 97 seconds so the view never feels static.
- **Perspective:** the camera sits 2.8 times the farthest star's distance from the Sun. Only positions use perspective. Sprites stay the same size, because scaling pixel art by non-whole amounts ruins it.
- **Filling the screen:** the scale is worked out once, so that the farthest star at its worst-case angle lands 96% of the way to the edge of the screen's shorter side.
- **Depth:** stars nearer the viewer draw on top. Stars on the far side are darkened, down to 50% brightness at the very back.
- **Companions:** at this scale, stars in the same system land on the same pixel. Companions are nudged out around the biggest member, using golden-angle spacing so several of them don't line up. This is a deliberate cheat, so binaries stay visible.

## Pixel-perfect drawing

- **One layer per sprite:** every star is its own `CALayer`, and Core Animation composites them on the GPU. Nothing is redrawn by hand each frame.
- **Sizing:** sprite size is based on real millimetres. The display's physical size gives screen pixels per millimetre, and each sprite pixel gets a whole number of screen pixels, chosen so a 16×16 star is at most about 2 mm across. At least one screen pixel per sprite pixel is enforced, so on a non-Retina screen stars come out a bit bigger than 2 mm.
- **No blurring:** all sprite layers use nearest-neighbour scaling, and every position is rounded to the screen's pixel grid. Edges never land between pixels.
- **No animation lag:** each frame's updates happen in one Core Animation transaction with implicit animations turned off, so layers jump straight to their new place instead of easing.

## Darkening without transparency

Lowering a layer's opacity would let stars behind it show through. Instead, every star has a solid black overlay, masked to the star's own sprite shape. Raising the overlay's opacity darkens the star while it stays solid.

The far-side darkening and the flicker both use this overlay. During a flare, the overlay's mask switches to the flare frame, so it always matches the shape on screen.

## Sprite sheets and variants

- **Layout:** star sheets have one column per colour and one row per variant. The number of rows is read from the image height, so adding variants needs no code change.
- **Choosing a variant:** each star's row comes from an FNV-1a hash of its name, so a given star looks the same every run. Swift's own `hashValue` can't be used here, because it changes every launch.
- **Flare sheets:** these have one row per variant, so a flare always matches the star's normal look. Their frames are 1 pixel bigger on every side, so the flare can glow past the star's edge. While a star is flaring, its layer grows by that border.
- **Missing art:** any missing image, row or column falls back to a generated placeholder, and the program prints what it couldn't find. Running without finished art is a supported state.

## Animation and events

`step()` runs once per frame: from a 60 fps timer in the standalone program, or from `animateOneFrame()` in the screensaver. Every event is checked against the elapsed time, so nothing drifts if a frame is late.

| Feature | How it works |
|---|---|
| Flicker | Every 0.5 s each star rolls a d12. On a 1 it darkens by 10% for 0.5 s |
| Flares | Every 0.5 s each flare star has a 1 in 200 chance. Its frames play forwards then back (0 1 2 3 2 1 0) over 1 s |
| Highlight | Every 20 s a random star (never the same twice in a row) is boxed for 15 s. A line comes off the box's top-right corner and the name types along it, one letter every 0.1 s |
| Background band | 800 tiny stars on a strip 3 screens long that wraps around. It scrolls at a quarter of the rotation speed, which reads as distance. Every 0.1 s each one has a 1 in 150 chance to twinkle |
| Shooting stars | Every 1–3 s a backdrop pixel steps 32–48 pixels in a random direction, chosen to stay on screen. Each trail pixel is 15 percentage points dimmer than the one ahead. The whole thing lasts 3 s |
| Spaceship | Every 5–15 s a ship flies between two random stars at least 3 ly apart, at 1.5 ly/s, with an eased start and stop. It moves through the 3D scene, passing in front of and behind stars, and flips to face its direction of travel |

**Highlight details:**
- **Name text:** names are drawn as smooth text at the screen's full resolution, unlike the sprites. They're measured in sprite pixels so they scale with the art.
- **Colour:** the text colour comes from the line art, by averaging its pixels and brightening the result. Recolouring the line recolours the text.
- **Line length:** the shortest line image with room for the name is used.
- **Centring:** the name is centred on its full width before typing starts, so letters fill in left to right and finish centred.

**Layer order, back to front:** background band, then shooting stars, then stars and the spaceship (sorted by depth), then the box, line and name, then the credit text.

## Two builds from one file

- **Entry point:** the standalone start-up code sits in an `@main` struct inside `#if !SCREENSAVER`. It can't be loose top-level code. Swift still parses switched-off `#if` branches, and in library mode it rejects statements at the top level of the file, even inside a branch that's turned off.
- **`-parse-as-library` is required in both builds.** For the screensaver, it also makes global settings start up lazily. Without it, a dynamic library's globals would never be initialised.
- **Finding resources:** the screensaver uses `Bundle(for:)`, because inside a screensaver, `Bundle.main` is the macOS host process. The standalone program instead looks around the source file's location, the current folder and the program's folder.
- **Late start-up:** the screensaver builds its view on the first frame rather than when it's created, since the view can start out at zero size.
- **Quitting cleanly:** recent macOS keeps the screensaver host process alive after the screensaver is dismissed. The view listens for `com.apple.screensaver.willstop` and exits then, so it doesn't keep animating in the background.
- **Packaging:** `build-saver.sh` compiles the code as a dynamic library inside the `.saver` bundle. It also copies `Art` and `data` into Resources, writes the `Info.plist` (`NSPrincipalClass` is `StarfieldSaverView`), signs the bundle and installs it.

## Known limitations

- **Preview thumbnail:** the System Settings preview draws everything at full-screen size inside a tiny box, so it looks crowded. The full-screen screensaver is unaffected.
- **Multiple displays:** each display gets its own starfield. Sprite size is based on whichever screen is available when it starts, which may not match every display.
- **One architecture per build:** the build is for the Mac it's compiled on (Apple Silicon or Intel), not a universal binary.
- **Data quirks inherited from the source:**
  - The article marks Gliese 570 as the nearest system in Libra, although WISE 1541−2250 is closer.
  - GJ 1005's distance is uncertain.
