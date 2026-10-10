# Starfield

A macOS screensaver that shows every known star and brown dwarf within 20 light-years of the Sun as a slowly rotating 3D map, drawn in pixel art.

There are 133 objects in 95 star systems, each placed at its real position in space, centred on the Sun.

## What it does

- **Rotating 3D map:** the neighbourhood turns once every four minutes, with perspective, and stars on the far side are drawn darker.
- **Pixel-art stars:** stars are sized and coloured by type, from blue-white A stars like Sirius down to tiny purple Y dwarfs. Each star always gets the same variant of its sprite.
- **Highlights:** every 20 seconds a star is boxed and its name types itself out along a line.
- **Flare stars:** the 32 objects marked as flare stars in the data now and then play a flare animation.
- **Atmosphere:**
  - Stars flicker slightly.
  - A band of tiny background stars twinkles and drifts behind everything.
  - Shooting stars streak across now and then.
- **Easter egg:** occasionally a small spaceship flies from one star to another.

## Requirements

- A Mac.
- Apple's Command Line Tools, which include the Swift compiler. Install them with `xcode-select --install` if you don't have them. Xcode itself isn't needed.

## Install the screensaver

From this folder:

```
bash build-saver.sh
```

This builds `build/Starfield.saver` and installs it into `~/Library/Screen Savers`. Quit and reopen System Settings, go to **Screen Saver**, and choose **Starfield** from the **Other** section.

To update it after changing anything, run the script again. If macOS keeps showing the old version, log out and back in.

## Run it as a normal program

Handy for testing changes quickly:

```
swiftc -O -parse-as-library source/Starfield.swift -o starfield
./starfield
```

It fills the main screen. Any key, click or mouse movement quits. Run it from a Terminal window to see its log, which lists what loaded, each highlighted star and each spaceship trip.

## Project layout

```
source/Starfield.swift   all the code (builds as the program or, with -D SCREENSAVER, the screensaver)
build-saver.sh           builds and installs Starfield.saver
Art/                     sprite sheets, boxes, lines and the System Settings thumbnail
data/                    nearest_stars_within_20ly.csv, the star data
```

## Changing things

All the settings are near the top of `source/Starfield.swift`, with a comment on each. Some useful ones:

| Setting | What it controls |
|---|---|
| `rotationPeriod` | Seconds per full turn |
| `maxStarMM` | How big stars are drawn on screen |
| `highlightEvery`, `highlightDuration` | How often a star is boxed and named, and for how long |
| `flareChance` | How often flare stars flare (higher = rarer) |
| `shootingWait` | Seconds between shooting stars |
| `shipWait` | Seconds between spaceship trips |

The star data is read from the CSV when it starts. To make another star flare, set its "Flare star" cell to `Yes`.

## Art

The sprite sheets in `Art/` are read like this:

- `8x8stars.png`, `16x16stars.png`, `32x32stars.png`: one colour per column, one variant per row.
- `16x16starsFlared.png`, `32x32starsFlared.png`: one row per star variant, frames left to right. Each frame is 1 pixel bigger on every side than the star.
- `8x8box.png`, `16x16box.png`, `32x32box.png`: the highlight box for each star size.
- `line64.png`, `line128.png`, `line256.png`: the line the name sits on. The shortest one that fits the name is used.
- `star.png`: background stars, 3 frames per row, one variant per row.
- `spaceships.png`: 19 × 8 frames, one ship per row.
- `thumbnail.png`, `thumbnail2x.png`: the picture shown in System Settings.

If any image is missing, a simple placeholder is drawn instead.

## Credits

- **Code:** I wrote the code together with Claude, Anthropic's AI assistant.
- **Art:** all the pixel art is mine.
- **Star data:** Wikipedia, as described below.

## Data

The star data comes from the Wikipedia article ["List of nearest stars"](https://en.wikipedia.org/wiki/List_of_nearest_stars), taken in October 2026. It is licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).

The CSV is a cleaned-up version of the article's main table with these changes:
- Wiki markup and citations removed.
- One row per star.
- RA/Dec added in decimal degrees.
- A "Flare star" column added. Its values come from the article's notes, with system-wide notes assigned to the right star.

`data/nearest_stars_within_20ly.csv` is shared under the same CC BY-SA 4.0 licence, and the screensaver shows the credit on screen.

## Licence

The code and art are © 2026 the owner of this repository, all rights reserved. The star data is CC BY-SA 4.0, as above. See [LICENSE](LICENSE).