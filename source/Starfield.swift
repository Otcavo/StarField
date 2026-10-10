// Starfield.swift
// A slowly rotating 3D map of every known star and brown dwarf within 20 light-years,
// centred on the Sun and drawn with pixel-art sprites.
//
// Project layout:
//     source/Starfield.swift
//     Art/8x8stars.png, Art/16x16stars.png, Art/32x32stars.png
//     data/nearest_stars_within_20ly.csv
//
// Run it as a normal program, from the project folder (the one holding source, Art and data):
//     swiftc -O -parse-as-library source/Starfield.swift -o starfield
//     ./starfield
// Any key, click or mouse movement quits.
//
// Or build the real screen saver (Starfield.saver) with:
//     ./build-saver.sh
// That compiles this same file with -D SCREENSAVER and packs the Art and data folders inside the bundle.

import AppKit
import ImageIO
#if SCREENSAVER
import ScreenSaver
#endif

// MARK: - Settings

let artFolder = "Art"
let dataFolder = "data"
let csvFile = "nearest_stars_within_20ly.csv"
let creditText = "Data: Wikipedia, \u{201C}List of nearest stars\u{201D} (CC BY-SA 4.0)"

/// Which column of which sprite sheet each kind of star uses (columns counted from 0, left to right).
/// Each row of a sheet is another variant of the same colours. The number of rows is read from the
/// image height, so you can add rows any time. Each star keeps the same variant every run, picked from its name.
/// If a sheet or column is missing, a placeholder pixel disc in the right colour is drawn instead,
/// so the screensaver still runs while you're working on the art.
let spriteConfig: [String: (file: String, size: Int, column: Int)] = [
    "K": ("32x32stars.png", 32, 0),   // orange: Toliman, Epsilon Eridani, 61 Cygni...
    "G": ("32x32stars.png", 32, 1),   // yellow-white: the Sun, Rigil Kentaurus, Tau Ceti...
    "F": ("32x32stars.png", 32, 2),   // white: Procyon A
    "A": ("32x32stars.png", 32, 3),   // blue-white: Sirius A, Altair
    "M": ("16x16stars.png", 16, 0),   // red: all 78 red dwarfs
    "Y": ("8x8stars.png",    8, 0),   // purple: Y dwarfs
    "T": ("8x8stars.png",    8, 1),   // magenta: T dwarfs
    "Msmall": ("8x8stars.png", 8, 2), // red: LSR J1835+3259, an M8.5 the page counts as a brown dwarf
    "L": ("8x8stars.png",    8, 3),   // dark red: L dwarfs
    "D": ("8x8stars.png",    8, 4),   // blue-white: white dwarfs
]

/// Colours for the placeholder sprites (only used when a sprite can't be loaded).
let placeholderRGB: [String: (Double, Double, Double)] = [
    "A": (0.75, 0.85, 1.00), "F": (1.00, 1.00, 0.95), "G": (1.00, 0.93, 0.70), "K": (1.00, 0.68, 0.38),
    "M": (1.00, 0.38, 0.28), "D": (0.80, 0.90, 1.00), "L": (0.70, 0.20, 0.15), "T": (0.78, 0.25, 0.62),
    "Y": (0.42, 0.16, 0.42), "Msmall": (1.00, 0.38, 0.28),
]

let randomVariantsEachRun = false    // true = stars pick a new random variant row every time it starts
let maxStarMM: Double = 2.0         // a 16x16 star is drawn no bigger than this; 8x8 is half, 32x32 double
let rotationPeriod: Double = 240     // seconds per full turn
let tiltDegrees: Double = 20         // how far above the celestial equator we look from
let tiltWobbleDegrees: Double = 8    // gentle nodding of that tilt
let wobblePeriod: Double = 97        // seconds per nod
let cameraDistance: Double = 2.8     // in units of the farthest star's distance; smaller = stronger perspective
let edgeFill: Double = 0.96          // how close the farthest stars get to the screen edge (1 = touching)
let separateCompanions = true        // nudge stars in the same system apart so binaries don't hide each other
let farSideBrightness: Double = 0.5  // stars on the far side of the Sun darken to this (they stay solid)

// Flicker: every `flickerRollInterval` seconds each star rolls a d`flickerDieSides`;
// on a 1 it darkens by `flickerDarkness` for `flickerDuration` seconds.
let flickerRollInterval: Double = 0.5
let flickerDieSides = 12
let flickerDarkness: Double = 0.10
let flickerDuration: Double = 0.5

// Flares: stars marked "Yes" in the CSV's "Flare star" column now and then play a flare animation,
// frames forwards then back. Each flare sheet has one row per variant (the same rows as the star sheet)
// and the frames left to right. Until a sheet exists, a simple brightening is used as a placeholder.
let flareFiles: [String: String] = ["M": "16x16starsFlared.png", "K": "32x32starsFlared.png"]   // keyed like spriteConfig
let flarePadding = 1                 // flared frames are this many pixels bigger on every side (16x16 -> 18x18)
let flareDuration: Double = 1.0      // seconds for the whole animation, forwards and back
let flareRollInterval: Double = 0.5  // every this many seconds...
let flareChance = 200                // ...each flare star has a 1 in this chance of flaring (about one flare every 3 s overall)

// Highlight box: every `highlightEvery` seconds a random star gets a box for `highlightDuration` seconds.
// The box image is centred on the star and drawn at the same pixel scale as the stars.
let highlightEvery: Double = 20
let highlightDuration: Double = 15
let boxFiles: [Int: String] = [8: "8x8box.png", 16: "16x16box.png", 32: "32x32box.png"]   // keyed by star sprite size

// The line comes out of the box's top-right corner: line.png's bottom-left corner sits on the box's
// top-right corner. Nudge it with `lineOffset`, in sprite pixels (+x = right, +y = up).
let lineFiles = ["line64.png", "line128.png", "line256.png"]   // the shortest one that fits the name is used
let lineMargin = 8                   // sprite pixels of line to spare beyond the name (split between both ends)
let lineOffset: (x: Int, y: Int) = (0, 0)

// Background stars: a band of tiny stars that wraps all the way around behind everything and scrolls
// slowly as the scene turns. star.png has one frame per column (3 across) and one variant per row.
let backgroundFile = "star.png"
let backgroundFrames = 3
let backgroundStarCount = 800         // around the whole band; about a third are on screen at once
let backgroundCircumference = 3.0     // length of the band, in screen widths
let backgroundSpeed = 0.25            // scroll speed as a fraction of the main rotation (less = feels farther away)
let backgroundPixelScale = 3          // draw each backdrop pixel this many star pixels across
let twinkleTick: Double = 0.1         // every this many seconds...
let twinkleChance = 150               // ...each background star has a 1 in this chance of starting a twinkle
let twinkleSequence = [0, 1, 2]       // frames a twinkle plays through; frame 0 is the resting frame
let twinkleFrameTime: Double = 0.1    // seconds per twinkle frame

// Shooting stars: now and then a star.png pixel darts across the screen in a random direction,
// one pixel step at a time, leaving a trail where each pixel is dimmer than the one ahead of it.
let shootingWait: ClosedRange<Double> = 1...3   // seconds between shooting stars (about one every 2)
let shootingSteps: ClosedRange<Int> = 32...48   // pixel steps it travels, picked at random each time
let shootingDuration: Double = 3.0              // seconds from appearing until the last of the trail is gone
let shootingTrailDim: Double = 0.15             // each trail pixel is this much dimmer than the one ahead
let shootingFrame = 0                           // which star.png frame (column) to use for it

// Spaceship easter egg: now and then a ship flies from one random star to another, through the 3D scene.
// The art should face right; it's flipped automatically when flying left.
let shipFile = "spaceships.png"
let shipFrameWidth = 19
let shipFrameHeight = 8
let shipFramesAreDifferentShips = false     // false: each row is one ship, its columns are animation frames
                                            // true: every frame on the sheet is a different ship (no animation)
let shipFrameTime: Double = 0.15            // seconds per animation frame
let shipWait: ClosedRange<Double> = 5...15  // seconds between trips; for a rare easter egg try 900...3600
let shipSpeed: Double = 1.5                 // light-years per second
let shipMinTrip: Double = 3                 // light-years; destinations closer than this are skipped

// Star name: typed onto the line one letter at a time, centred along it, in smooth (not pixel) text.
// Uses the system monospaced font, unless you drop a .ttf or .otf file into the Art folder.
let letterInterval: Double = 0.1     // seconds per letter
let nameFontPixelSize: CGFloat = 10  // text size, measured in sprite pixels so it scales with the art
let nameGap = 1                      // sprite pixels between the bottom of the text and the top of the line
let nameBrighten: CGFloat = 0.15     // how much brighter than the line's own green the text is

// MARK: - Star data (read from the CSV)

struct Star {
    let name: String
    let ra: Double       // right ascension, degrees (J2000)
    let dec: Double      // declination, degrees (J2000)
    let dist: Double     // light-years from the Sun
    let sprite: String   // key into spriteConfig
    let system: String
    let flare: Bool      // "Yes" in the CSV's "Flare star" column
}

enum StarDataError: Error, CustomStringConvertible {
    case notFound(String)
    case missingColumn(String)
    case noRows

    var description: String {
        switch self {
        case .notFound(let file): return "Couldn't find \(file). It should be in the \(dataFolder) folder."
        case .missingColumn(let name): return "The CSV has no \"\(name)\" column."
        case .noRows: return "The CSV has no star rows."
        }
    }
}

/// Splits CSV text into rows of fields. Handles quoted fields containing commas, quotes and line breaks.
func parseCSV(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    let chars = Array(text)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        if inQuotes {
            if c == "\"" {
                if i + 1 < chars.count && chars[i + 1] == "\"" {
                    field.append("\"")
                    i += 1
                } else {
                    inQuotes = false
                }
            } else {
                field.append(c)
            }
        } else if c == "\"" {
            inQuotes = true
        } else if c == "," {
            row.append(field)
            field = ""
        } else if c == "\n" || c == "\r\n" || c == "\r" {   // "\r\n" is a single Character in Swift
            row.append(field)
            rows.append(row)
            row = []
            field = ""
        } else {
            field.append(c)
        }
        i += 1
    }
    if !field.isEmpty || !row.isEmpty {
        row.append(field)
        rows.append(row)
    }
    return rows
}

/// Picks the sprite for a star from its type and spectral class.
func spriteKey(type: String, spectralClass: String) -> String {
    let letter = spectralClass.first.map { String($0) } ?? ""
    switch type {
    case "Red dwarf":
        return "M"
    case "White dwarf":
        return "D"
    case "Brown dwarf", "Sub-brown dwarf / rogue planet":
        return ["L", "T", "Y"].contains(letter) ? letter : "Msmall"   // LSR J1835+3259 (class M8.5)
    default:
        return ["A", "F", "G", "K"].contains(letter) ? letter : "G"
    }
}

func loadStars(searchDirs: [URL]) throws -> [Star] {
    guard let url = searchDirs.map({ $0.appendingPathComponent(csvFile) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
        throw StarDataError.notFound(csvFile)
    }
    var text = try String(contentsOf: url, encoding: .utf8)
    if text.unicodeScalars.first == "\u{FEFF}" { text.unicodeScalars.removeFirst() }   // byte-order mark

    let rows = parseCSV(text)
    guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces) }) else {
        throw StarDataError.noRows
    }
    func column(_ name: String) throws -> Int {
        guard let index = header.firstIndex(of: name) else { throw StarDataError.missingColumn(name) }
        return index
    }
    let cName = try column("Object"), cSystem = try column("System"), cType = try column("Type")
    let cClass = try column("Spectral class"), cRA = try column("RA (deg)"), cDec = try column("Dec (deg)")
    let cDist = try column("Distance (ly)")
    let cFlare = header.firstIndex(of: "Flare star")   // optional: without it, nothing flares

    var stars: [Star] = []
    for row in rows.dropFirst() where row.count == header.count {
        guard let dist = Double(row[cDist]) else { continue }
        stars.append(Star(name: row[cName],
                          ra: Double(row[cRA]) ?? 0,      // the Sun has no RA/Dec; it sits at the centre anyway
                          dec: Double(row[cDec]) ?? 0,
                          dist: dist,
                          sprite: spriteKey(type: row[cType], spectralClass: row[cClass]),
                          system: row[cSystem],
                          flare: cFlare.map { row[$0].trimmingCharacters(in: .whitespaces).lowercased() == "yes" } ?? false))
    }
    if stars.isEmpty { throw StarDataError.noRows }
    print("Loaded \(stars.count) stars from \(url.path)")
    return stars
}

// MARK: - Sprites

func loadSheet(named file: String, searchDirs: [URL]) -> CGImage? {
    for dir in searchDirs {
        let url = dir.appendingPathComponent(file)
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
    }
    return nil
}

func placeholderSprite(size: Int, rgb: (Double, Double, Double)) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let centre = Double(size) / 2
    let radius = Double(size) * 0.42
    for y in 0..<size {
        for x in 0..<size {
            let d = hypot(Double(x) + 0.5 - centre, Double(y) + 0.5 - centre)
            if d > radius { continue }
            let white = d < radius * 0.4 ? 0.6 : 0.0   // brighter core
            let r = rgb.0 + (1 - rgb.0) * white
            let g = rgb.1 + (1 - rgb.1) * white
            let b = rgb.2 + (1 - rgb.2) * white
            ctx.setFillColor(CGColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1))
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    return ctx.makeImage()
}

final class SpriteLibrary {
    private let searchDirs: [URL]
    private var sheets: [String: CGImage] = [:]
    private var triedSheets: Set<String> = []
    private var cache: [String: CGImage] = [:]
    private var warnings: Set<String> = []

    init(searchDirs: [URL]) { self.searchDirs = searchDirs }

    /// Flare animation frames for a star: the row of its flare sheet that matches the row its normal sprite
    /// came from. Empty if this kind of star has no flare sheet entry or the sheet lacks that row.
    func flareFrames(for key: String, variantSeed: UInt64, base: CGImage) -> [CGImage] {
        guard let file = flareFiles[key], let cfg = spriteConfig[key] else { return [] }
        let starRows = sheets[cfg.file].map { max(1, $0.height / cfg.size) } ?? 1
        let row = Int(variantSeed % UInt64(starRows))   // same row as the star's normal sprite

        let frameSize = cfg.size + 2 * flarePadding   // e.g. 18x18 frames for 16x16 stars

        if !triedSheets.contains(file) {
            triedSheets.insert(file)
            if let sheet = loadSheet(named: file, searchDirs: searchDirs) {
                sheets[file] = sheet
                print("Loaded \(file) (\(sheet.width / frameSize) frame(s) x \(sheet.height / frameSize) row(s) of \(frameSize)x\(frameSize))")
            } else {
                print("Couldn't find \(file) in the \(artFolder) folder; using a placeholder brightening for flares")
            }
        }
        guard let sheet = sheets[file] else {
            return [0.15, 0.3, 0.45, 0.6].compactMap { lightened(base, amount: $0) }
        }
        let count = sheet.width / frameSize
        guard count > 0, (row + 1) * frameSize <= sheet.height else {
            let warning = "\(file) has no row \(row); stars using that row won't flare"
            if !warnings.contains(warning) { warnings.insert(warning); print(warning) }
            return []
        }
        return (0..<count).compactMap { column in
            sheet.cropping(to: CGRect(x: column * frameSize, y: row * frameSize, width: frameSize, height: frameSize))
        }
    }

    /// The sprite for `key`. `variantSeed` picks the row: row = seed % (number of rows in the sheet).
    func image(for key: String, variantSeed: UInt64) -> CGImage? {
        guard let cfg = spriteConfig[key] else { return nil }

        if !triedSheets.contains(cfg.file) {
            triedSheets.insert(cfg.file)
            if let sheet = loadSheet(named: cfg.file, searchDirs: searchDirs) {
                sheets[cfg.file] = sheet
                print("Loaded \(cfg.file) (\(sheet.width)x\(sheet.height) px)")
            } else {
                print("Couldn't find \(cfg.file) in the \(artFolder) folder; using placeholder sprites for it")
            }
        }

        let rows = sheets[cfg.file].map { max(1, $0.height / cfg.size) } ?? 1
        let row = Int(variantSeed % UInt64(rows))
        let cacheKey = "\(key)#\(row)"
        if let cached = cache[cacheKey] { return cached }

        var result: CGImage? = nil
        if let sheet = sheets[cfg.file] {
            let rect = CGRect(x: cfg.column * cfg.size, y: row * cfg.size, width: cfg.size, height: cfg.size)
            if rect.maxX <= CGFloat(sheet.width) && rect.maxY <= CGFloat(sheet.height) {
                result = sheet.cropping(to: rect)
            } else {
                print("\(cfg.file) has no column \(cfg.column) for '\(key)'; using a placeholder")
            }
        }
        if result == nil, let rgb = placeholderRGB[key] {
            result = placeholderSprite(size: cfg.size, rgb: rgb)
        }
        if let image = result { cache[cacheKey] = image }
        return result
    }
}

extension SpriteLibrary {
    /// The folders this library looks in (the Art folder first).
    var folders: [URL] { searchDirs }

    /// The highlight box for stars of the given sprite size (8, 16 or 32), or a plain green placeholder box.
    func box(forStarSize size: Int) -> CGImage? {
        var image: CGImage? = nil
        if let file = boxFiles[size] {
            image = loadSheet(named: file, searchDirs: searchDirs)
            if let image {
                print("Loaded \(file) (\(image.width)x\(image.height) px)")
            } else {
                print("Couldn't find \(file) in the \(artFolder) folder; using a placeholder box")
            }
        }
        return image ?? placeholderBox(side: size + 4)
    }

    /// Background star frames: one array of `backgroundFrames` images per row (variant) of star.png.
    func backgroundStarFrames() -> [[CGImage]] {
        if let sheet = loadSheet(named: backgroundFile, searchDirs: searchDirs) {
            let side = max(1, sheet.width / backgroundFrames)
            let rows = max(1, sheet.height / side)
            var result: [[CGImage]] = []
            for row in 0..<rows {
                let frames = (0..<backgroundFrames).compactMap { column in
                    sheet.cropping(to: CGRect(x: column * side, y: row * side, width: side, height: side))
                }
                if frames.count == backgroundFrames { result.append(frames) }
            }
            if !result.isEmpty {
                print("Loaded \(backgroundFile) (\(result.count) variant row(s))")
                return result
            }
        }
        print("Couldn't find \(backgroundFile) in the \(artFolder) folder; using placeholder background stars")
        let placeholder = [0.45, 0.7, 1.0].compactMap { (gray: Double) -> CGImage? in
            guard let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.setFillColor(CGColor(red: CGFloat(gray), green: CGFloat(gray), blue: CGFloat(gray), alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            return ctx.makeImage()
        }
        return [placeholder]
    }

    /// Spaceship frames from spaceships.png: one array of animation frames per row (ship).
    func spaceships() -> [[CGImage]] {
        if let sheet = loadSheet(named: shipFile, searchDirs: searchDirs) {
            let columns = sheet.width / shipFrameWidth
            let rows = sheet.height / shipFrameHeight
            var result: [[CGImage]] = []
            for row in 0..<max(0, rows) {
                let frames = (0..<max(0, columns)).compactMap { column in
                    sheet.cropping(to: CGRect(x: column * shipFrameWidth, y: row * shipFrameHeight,
                                              width: shipFrameWidth, height: shipFrameHeight))
                }
                if !frames.isEmpty { result.append(frames) }
            }
            if !result.isEmpty {
                print("Loaded \(shipFile) (\(result.count) row(s) of \(columns) frame(s))")
                return result
            }
        }
        print("Couldn't find \(shipFile) in the \(artFolder) folder; using a placeholder spaceship")
        guard let ctx = CGContext(data: nil, width: shipFrameWidth, height: shipFrameHeight, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.setFillColor(CGColor(red: 0.75, green: 0.78, blue: 0.82, alpha: 1))
        ctx.fill(CGRect(x: 3, y: 3, width: 13, height: 2))    // hull
        ctx.fill(CGRect(x: 6, y: 2, width: 6, height: 4))     // middle
        ctx.fill(CGRect(x: 4, y: 1, width: 3, height: 6))     // fins
        ctx.fill(CGRect(x: 16, y: 3, width: 2, height: 2))    // nose
        ctx.setFillColor(CGColor(red: 1.0, green: 0.55, blue: 0.15, alpha: 1))
        ctx.fill(CGRect(x: 1, y: 3, width: 2, height: 2))     // engine glow
        return ctx.makeImage().map { [[$0]] } ?? []
    }

    /// The lines that come off the box, shortest first, or a plain green placeholder line.
    func lines() -> [CGImage] {
        var found: [CGImage] = []
        for file in lineFiles {
            if let image = loadSheet(named: file, searchDirs: searchDirs) {
                print("Loaded \(file) (\(image.width)x\(image.height) px)")
                found.append(image)
            } else {
                print("Couldn't find \(file) in the \(artFolder) folder")
            }
        }
        if !found.isEmpty { return found.sorted { $0.width < $1.width } }
        print("No line images found; using a placeholder line")
        guard let ctx = CGContext(data: nil, width: 48, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.setFillColor(CGColor(red: 0.1, green: 0.8, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 2))
        return ctx.makeImage().map { [$0] } ?? []
    }
}

/// A copy of the image darkened to `brightness` (1 = unchanged). It stays solid; only the colour gets darker.
func darkened(_ image: CGImage, brightness: Double) -> CGImage? {
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(image, in: rect)
    ctx.setBlendMode(.sourceAtop)   // only paint over the image's own pixels
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: CGFloat(1 - brightness)))
    ctx.fill(rect)
    return ctx.makeImage()
}

/// A copy of the image blended `amount` of the way towards white (0 = unchanged). Used for placeholder flares.
func lightened(_ image: CGImage, amount: Double) -> CGImage? {
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(image, in: rect)
    ctx.setBlendMode(.sourceAtop)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: CGFloat(amount)))
    ctx.fill(rect)
    return ctx.makeImage()
}

func placeholderBox(side: Int) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setFillColor(CGColor(red: 0.1, green: 0.8, blue: 0.1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
    ctx.clear(CGRect(x: 1, y: 1, width: side - 2, height: side - 2))
    return ctx.makeImage()
}

/// The first .ttf/.otf font in the search folders, or the system monospaced font.
func loadNameFont(searchDirs: [URL]) -> NSFont {
    for dir in searchDirs {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
        let fonts = files.filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in fonts {
            if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
               let descriptor = descriptors.first {
                print("Using font \(url.lastPathComponent) for star names")
                return CTFontCreateWithFontDescriptor(descriptor, nameFontPixelSize, nil) as NSFont
            }
        }
    }
    print("Using the system monospaced font for star names")
    return NSFont.monospacedSystemFont(ofSize: nameFontPixelSize, weight: .regular)
}

/// The average colour of an image's solid pixels, made a little brighter. Used to colour the names from line.png.
func brighterAverageColor(of image: CGImage) -> CGColor? {
    let w = image.width, h = image.height
    guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let drawn = pixels.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Bool in
        guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    guard drawn else { return nil }
    var r = 0.0, g = 0.0, b = 0.0, n = 0.0
    for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 200 {
        r += Double(pixels[i]); g += Double(pixels[i + 1]); b += Double(pixels[i + 2]); n += 1
    }
    guard n > 0 else { return nil }
    let average = NSColor(srgbRed: r / n / 255, green: g / n / 255, blue: b / n / 255, alpha: 1)
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
    average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    // If it's already near full brightness, lighten by easing off the saturation instead.
    let newBrightness = min(1, brightness + nameBrighten)
    let newSaturation = brightness + nameBrighten > 1 ? saturation * (1 - nameBrighten) : saturation
    return NSColor(hue: hue, saturation: newSaturation, brightness: newBrightness, alpha: 1).cgColor
}

/// A hash of the star's name that's the same on every run (Swift's own hashValue changes each launch).
func stableSeed(_ name: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325          // FNV-1a
    for byte in name.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return hash
}

// MARK: - The view

final class StarfieldView: NSView {
    private struct Node {
        let name: String
        let position: SIMD3<Double>   // light-years; x towards RA 0h, y towards RA 6h, z towards celestial north
        let layer: CALayer
        let shade: CALayer            // black overlay cut to the sprite's shape; its opacity darkens the star
        let texels: Int               // sprite size in sprite pixels (8, 16 or 32)
        var offset = CGPoint.zero     // screen nudge for companions
        var flickerUntil = 0.0        // time when the current flicker ends
        let baseImage: CGImage        // the star's normal sprite
        let flareFrames: [CGImage]    // empty if it doesn't flare
        let flarePad: Int             // how many sprite pixels bigger each side the flare frames are
        var flareStart = -1.0         // when the current flare began; negative = not flaring
        var flareShown = -1           // flare frame on screen; -1 = the normal sprite
    }
    private var lastFlareRoll = -1

    private let stars: [Star]
    private var nodes: [Node] = []

    private struct BackgroundStar {
        let layer: CALayer
        let frames: [CGImage]
        let x: Double                 // position along the band, in points
        let y: Double                 // height on screen, in points
        var twinkleStart = -1.0       // when the current twinkle began; negative = resting
        var shownFrame = 0
    }
    private var backdrop: [BackgroundStar] = []

    private struct Trip {
        let from: Int                 // index into nodes
        let to: Int
        let start: Double
        let duration: Double
        let frames: [CGImage]
    }
    private struct ShootingStar {
        let start: Double
        let tick: Double              // seconds per step
        let levels: [CGImage]         // the pixel at full brightness, then each dimmer trail step
        let layers: [CALayer]         // one per position along its path
    }
    private var shootingLevels: [[CGImage]] = []   // per star.png variant
    private var shooting: [ShootingStar] = []
    private var nextShootingTime = 0.0

    private var shipKinds: [[CGImage]] = []
    private let shipLayer = CALayer()
    private var trip: Trip?
    private var nextShipTime = 0.0
    private var shipFrameShown = -1
    private var backdropLength: Double = 1   // band length in points
    private var lastTwinkleTick = -1
    private var backingScale: Double = 2
    private var texelPoints: Double = 1      // screen points per sprite pixel
    private var pixelsPerTexel = 1           // screen pixels per sprite pixel
    private var radius: Double = 20          // distance of the farthest star
    private var camDist: Double = 56
    private var focal: Double = 1
    private let startTime = CACurrentMediaTime()
    private var lastRoll = -1
    private let boxLayer = CALayer()
    private var boxImages: [Int: CGImage] = [:]   // keyed by star sprite size
    private let lineLayer = CALayer()
    private var lineImages: [CGImage] = []   // shortest first
    private var lineImage: CGImage?          // the one in use for the current name
    private let nameLayer = CALayer()
    private var nameFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
    private var nameColor = CGColor(red: 0.2, green: 0.9, blue: 0.2, alpha: 1)
    private var nameSize = (width: 0, height: 0, descent: 0)   // full name, in sprite pixels
    private var typedCount = -1
    private var highlighted: Int? = nil           // index into nodes
    private var lastHighlightCycle = -1
    private var timer: Timer?
    private let drivesItself: Bool   // false when a screen saver calls step() for each frame

    init(frame: NSRect, screen: NSScreen, stars: [Star], sprites: SpriteLibrary, drivesItself: Bool = true) {
        self.stars = stars
        self.drivesItself = drivesItself
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        configure(screen: screen, sprites: sprites)
        addCredit()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func snap(_ v: Double) -> CGFloat {
        // Line sprites up with the screen's pixel grid so the pixel art stays crisp.
        CGFloat((v * backingScale).rounded() / backingScale)
    }

    private func configure(screen: NSScreen, sprites: SpriteLibrary) {
        backingScale = Double(screen.backingScaleFactor)

        // Work out how many screen pixels each sprite pixel gets, from the display's physical size.
        var pointsPerMM = 110.0 / 25.4   // fallback if the display doesn't report its size
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let physical = CGDisplayScreenSize(CGDirectDisplayID(number.uint32Value))
            if physical.width > 0 { pointsPerMM = Double(screen.frame.width) / Double(physical.width) }
        }
        let pixelsPerMM = pointsPerMM * backingScale
        pixelsPerTexel = max(1, Int(maxStarMM * pixelsPerMM / 16))
        texelPoints = Double(pixelsPerTexel) / backingScale
        let perTexel = pixelsPerTexel
        let sizeMM = { (texels: Int) in String(format: "%.1f", Double(texels * perTexel) / pixelsPerMM) }
        print("Each sprite pixel = \(perTexel) screen pixel(s):8x8 = \(sizeMM(8)) mm, 16x16 = \(sizeMM(16)) mm, 32x32 = \(sizeMM(32)) mm")

        // Fit the farthest stars just inside the screen edge, allowing for perspective.
        radius = stars.map { $0.dist }.max() ?? 20
        camDist = radius * cameraDistance
        let halfScreen = Double(min(bounds.width, bounds.height)) / 2
        let available = halfScreen * edgeFill - 32 * texelPoints / 2
        focal = available * (camDist * camDist - radius * radius).squareRoot() / radius

        // Background band: random spots along a strip that wraps around, behind everything else.
        let variants = sprites.backgroundStarFrames()
        backdropLength = max(1, Double(bounds.width) * backgroundCircumference)
        for _ in 0..<backgroundStarCount {
            guard let frames = variants.randomElement(), let first = frames.first else { break }
            let dot = CALayer()
            dot.contents = first
            dot.contentsGravity = .resize
            dot.magnificationFilter = .nearest
            dot.minificationFilter = .nearest
            dot.zPosition = -1_000
            let scale = texelPoints * Double(backgroundPixelScale)
            dot.frame = CGRect(x: 0, y: 0, width: CGFloat(Double(first.width) * scale),
                               height: CGFloat(Double(first.height) * scale))
            layer?.addSublayer(dot)
            backdrop.append(BackgroundStar(layer: dot, frames: frames,
                                           x: Double.random(in: 0..<max(1, backdropLength)),
                                           y: Double.random(in: 0..<max(1, Double(bounds.height)))))
        }

        // Shooting stars: precompute each variant's pixel at full brightness and at each trail step.
        shootingLevels = variants.compactMap { frames -> [CGImage]? in
            guard !frames.isEmpty else { return nil }
            let source = frames[min(shootingFrame, frames.count - 1)]
            var levels: [CGImage] = []
            var brightness = 1.0
            while brightness > 0.0001 {
                if let image = darkened(source, brightness: brightness) { levels.append(image) }
                brightness -= shootingTrailDim
            }
            return levels.isEmpty ? nil : levels
        }
        nextShootingTime = Double.random(in: shootingWait)

        // One layer per star.
        var systems: [String: [Int]] = [:]
        for star in stars {
            let seed = randomVariantsEachRun ? UInt64.random(in: 0...UInt64.max) : stableSeed(star.name)
            guard let image = sprites.image(for: star.sprite, variantSeed: seed),
                  let cfg = spriteConfig[star.sprite] else { continue }
            let ra = star.ra * .pi / 180
            let dec = star.dec * .pi / 180
            let position = SIMD3(star.dist * cos(dec) * cos(ra),
                                 star.dist * cos(dec) * sin(ra),
                                 star.dist * sin(dec))
            let sprite = CALayer()
            sprite.contents = image
            sprite.contentsGravity = .resize
            sprite.magnificationFilter = .nearest
            sprite.minificationFilter = .nearest
            layer?.addSublayer(sprite)

            // Darkening overlay: solid black, masked to the sprite's own pixels, so dimming a star
            // never makes it see-through.
            let side = CGFloat(Double(cfg.size) * texelPoints)
            let mask = CALayer()
            mask.contents = image
            mask.contentsGravity = .resize
            mask.magnificationFilter = .nearest
            mask.minificationFilter = .nearest
            mask.frame = CGRect(x: 0, y: 0, width: side, height: side)
            let shade = CALayer()
            shade.backgroundColor = NSColor.black.cgColor
            shade.frame = mask.frame
            shade.mask = mask
            shade.opacity = 0
            sprite.addSublayer(shade)

            let flares = star.flare ? sprites.flareFrames(for: star.sprite, variantSeed: seed, base: image) : []
            let flarePad = flares.first.map { max(0, ($0.width - cfg.size) / 2) } ?? 0
            nodes.append(Node(name: star.name, position: position, layer: sprite, shade: shade, texels: cfg.size,
                              baseImage: image, flareFrames: flares, flarePad: flarePad))
            systems[star.system, default: []].append(nodes.count - 1)
        }

        print("\(nodes.filter { !$0.flareFrames.isEmpty }.count) flare star(s) ready to flare")

        // Stars in the same system sit within a pixel of each other at this scale,
        // so fan the companions out around the biggest member.
        if separateCompanions {
            for (_, members) in systems where members.count > 1 {
                guard let primary = members.max(by: { nodes[$0].texels < nodes[$1].texels }) else { continue }
                var slot = 0
                for m in members where m != primary {
                    slot += 1
                    let angle = Double(slot) * 2.399963 + 0.7
                    let distance = Double(nodes[primary].texels + nodes[m].texels) / 2 * texelPoints * 0.9
                    nodes[m].offset = CGPoint(x: snap(cos(angle) * distance), y: snap(sin(angle) * distance))
                }
            }
        }

        // Highlight box: one layer that moves to whichever star is selected.
        for size in Set(nodes.map { $0.texels }) {
            if let image = sprites.box(forStarSize: size) { boxImages[size] = image }
        }
        boxLayer.contentsGravity = .resize
        boxLayer.magnificationFilter = .nearest
        boxLayer.minificationFilter = .nearest
        boxLayer.zPosition = 999   // above the stars, below the credit
        boxLayer.isHidden = true
        layer?.addSublayer(boxLayer)

        lineImages = sprites.lines()
        lineImage = lineImages.last
        lineLayer.contents = lineImage
        lineLayer.contentsGravity = .resize
        lineLayer.magnificationFilter = .nearest
        lineLayer.minificationFilter = .nearest
        lineLayer.zPosition = 999
        lineLayer.isHidden = true
        layer?.addSublayer(lineLayer)

        // Spaceship: one layer, shown only during a trip.
        shipKinds = sprites.spaceships()
        if shipFramesAreDifferentShips { shipKinds = shipKinds.flatMap { $0.map { [$0] } } }
        shipLayer.contentsGravity = .resize
        shipLayer.magnificationFilter = .nearest
        shipLayer.minificationFilter = .nearest
        shipLayer.bounds = CGRect(x: 0, y: 0, width: CGFloat(Double(shipFrameWidth) * texelPoints),
                                  height: CGFloat(Double(shipFrameHeight) * texelPoints))
        shipLayer.isHidden = true
        layer?.addSublayer(shipLayer)
        nextShipTime = Double.random(in: shipWait)

        nameFont = loadNameFont(searchDirs: sprites.folders)
        if let line = lineImage, let color = brighterAverageColor(of: line) { nameColor = color }
        nameLayer.contentsGravity = .resize
        nameLayer.zPosition = 999
        nameLayer.isHidden = true
        layer?.addSublayer(nameLayer)

        step()
        if drivesItself {
            let t = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(step), userInfo: nil, repeats: true)
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    /// Small source credit in the bottom-right corner.
    private func addCredit() {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let textSize = (creditText as NSString).size(withAttributes: [.font: font])
        let width = ceil(textSize.width) + 4
        let height = ceil(textSize.height)
        let margin: CGFloat = 14

        let credit = CATextLayer()
        credit.string = creditText
        credit.font = font
        credit.fontSize = 11
        credit.foregroundColor = NSColor(white: 0.5, alpha: 1).cgColor
        credit.alignmentMode = .right
        credit.contentsScale = CGFloat(backingScale)
        credit.frame = CGRect(x: bounds.maxX - width - margin, y: margin, width: width, height: height)
        credit.zPosition = 1_000   // always above the stars
        layer?.addSublayer(credit)
    }

    // MARK: Star names

    private func attributedName(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: nameFont,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
    }

    /// Measures the full name so the text can be centred before it's finished typing.
    private func measureName(_ name: String) {
        let line = CTLineCreateWithAttributedString(attributedName(name))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let down = Int(ceil(descent))
        nameSize = (width: Int(ceil(width)), height: Int(ceil(ascent)) + down, descent: down)
    }

    /// Draws the first letters of the name into a full-name-sized image at the screen's real resolution,
    /// with normal smooth text.
    private func renderName(_ text: String) -> CGImage? {
        let scale = pixelsPerTexel
        guard nameSize.width > 0, nameSize.height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: nameSize.width * scale, height: nameSize.height * scale,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.setFillColor(nameColor)
        ctx.textPosition = CGPoint(x: 0, y: CGFloat(nameSize.descent))
        CTLineDraw(CTLineCreateWithAttributedString(attributedName(text)), ctx)
        return ctx.makeImage()
    }

    /// Starts a shooting star somewhere on screen, heading in a random direction that keeps it on screen.
    private func spawnShootingStar(levels: [CGImage], at t: Double) {
        let px = Double(levels[0].width) * texelPoints * Double(backgroundPixelScale)   // one pixel step
        let w = Double(bounds.width), h = Double(bounds.height)
        let steps = Int.random(in: shootingSteps)
        let travel = Double(steps - 1) * px
        var start = (x: 0.0, y: 0.0)
        var direction = (x: 1.0, y: 0.0)
        for _ in 0..<20 {
            let angle = Double.random(in: 0..<(2 * .pi))
            let major = max(abs(cos(angle)), abs(sin(angle)))
            direction = (cos(angle) / major, sin(angle) / major)   // one whole pixel per step along the main axis
            start = (Double.random(in: 0..<max(1, w - px)), Double.random(in: 0..<max(1, h - px)))
            let endX = start.x + direction.x * travel, endY = start.y + direction.y * travel
            if endX >= 0 && endX <= w - px && endY >= 0 && endY <= h - px { break }
        }
        var layers: [CALayer] = []
        for i in 0..<steps {
            let dot = CALayer()
            dot.contentsGravity = .resize
            dot.magnificationFilter = .nearest
            dot.minificationFilter = .nearest
            dot.zPosition = -500   // in front of the background band, behind the real stars
            dot.isHidden = true
            let x = start.x + (Double(i) * direction.x).rounded() * px
            let y = start.y + (Double(i) * direction.y).rounded() * px
            dot.frame = CGRect(x: snap(x), y: snap(y), width: CGFloat(px), height: CGFloat(px))
            layer?.addSublayer(dot)
            layers.append(dot)
        }
        let tick = shootingDuration / Double(steps + levels.count - 1)
        shooting.append(ShootingStar(start: t, tick: tick, levels: levels, layers: layers))
    }

    @objc func step() {
        let t = CACurrentMediaTime() - startTime
        let theta = t * 2 * .pi / rotationPeriod
        let phi = (tiltDegrees + tiltWobbleDegrees * sin(t * 2 * .pi / wobblePeriod)) * .pi / 180
        let cosT = cos(theta), sinT = sin(theta), cosP = cos(phi), sinP = sin(phi)
        let cx = Double(bounds.midX), cy = Double(bounds.midY)

        // Every half second, each star rolls a d12; a 1 starts a flicker.
        let roll = Int(t / flickerRollInterval)
        if roll != lastRoll {
            lastRoll = roll
            for i in nodes.indices where Int.random(in: 1...flickerDieSides) == 1 {
                nodes[i].flickerUntil = t + flickerDuration
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Background band: scroll it (leftwards, with the far side of the scene) and run the twinkles.
        let scroll = theta / (2 * .pi) * backgroundSpeed * backdropLength
        let twinkleTickNow = Int(t / twinkleTick)
        let newTwinkleTick = twinkleTickNow != lastTwinkleTick
        lastTwinkleTick = twinkleTickNow
        for i in backdrop.indices {
            var star = backdrop[i]
            if newTwinkleTick && star.twinkleStart < 0 && Int.random(in: 1...twinkleChance) == 1 {
                star.twinkleStart = t
            }
            var frame = 0
            if star.twinkleStart >= 0 {
                let stepIndex = Int((t - star.twinkleStart) / twinkleFrameTime)
                if stepIndex < twinkleSequence.count {
                    frame = min(twinkleSequence[stepIndex], star.frames.count - 1)
                } else {
                    star.twinkleStart = -1
                }
            }
            if frame != star.shownFrame {
                star.shownFrame = frame
                star.layer.contents = star.frames[frame]
            }
            var x = (star.x - scroll).truncatingRemainder(dividingBy: backdropLength)
            if x < 0 { x += backdropLength }
            star.layer.isHidden = x > Double(bounds.width)
            if !star.layer.isHidden {
                star.layer.frame.origin = CGPoint(x: snap(x), y: snap(star.y))
            }
            backdrop[i] = star
        }

        // Shooting stars: each position along the path lights up when the head reaches it,
        // then gets one trail step dimmer every tick until it's gone.
        if t >= nextShootingTime, let levels = shootingLevels.randomElement() {
            nextShootingTime = t + Double.random(in: shootingWait)
            spawnShootingStar(levels: levels, at: t)
        }
        var stillGoing: [ShootingStar] = []
        for streak in shooting {
            let ticks = Int((t - streak.start) / streak.tick)
            for (i, dot) in streak.layers.enumerated() {
                let age = ticks - i
                if age >= 0 && age < streak.levels.count {
                    dot.contents = streak.levels[age]
                    dot.isHidden = false
                } else {
                    dot.isHidden = true
                }
            }
            if ticks - (streak.layers.count - 1) >= streak.levels.count {
                streak.layers.forEach { $0.removeFromSuperlayer() }
            } else {
                stillGoing.append(streak)
            }
        }
        shooting = stillGoing

        // Flares: every half second each flare star may start one; it plays its frames forwards then back
        // (e.g. 0 1 2 3 2 1 0) over `flareDuration`, then returns to its normal sprite.
        let flareRoll = Int(t / flareRollInterval)
        let newFlareRoll = flareRoll != lastFlareRoll
        lastFlareRoll = flareRoll
        for i in nodes.indices where !nodes[i].flareFrames.isEmpty {
            if newFlareRoll && nodes[i].flareStart < 0 && Int.random(in: 1...flareChance) == 1 {
                nodes[i].flareStart = t
            }
            var wanted = -1
            if nodes[i].flareStart >= 0 {
                let count = nodes[i].flareFrames.count
                let sequence = Array(0..<count) + Array((0..<max(0, count - 1)).reversed())
                let stepIndex = Int((t - nodes[i].flareStart) / (flareDuration / Double(sequence.count)))
                if stepIndex < sequence.count {
                    wanted = sequence[stepIndex]
                } else {
                    nodes[i].flareStart = -1
                }
            }
            if wanted != nodes[i].flareShown {
                nodes[i].flareShown = wanted
                let image = wanted >= 0 ? nodes[i].flareFrames[wanted] : nodes[i].baseImage
                nodes[i].layer.contents = image
                nodes[i].shade.mask?.contents = image   // keep the darkening overlay the same shape
                // Flare frames are bigger than the star, so resize the overlay to match.
                let pad = wanted >= 0 ? nodes[i].flarePad : 0
                let size = CGFloat(Double(nodes[i].texels + 2 * pad) * texelPoints)
                nodes[i].shade.frame = CGRect(x: 0, y: 0, width: size, height: size)
                nodes[i].shade.mask?.frame = CGRect(x: 0, y: 0, width: size, height: size)
            }
        }

        // Every 20 seconds pick a new star; it stays boxed for the first 15 seconds of that stretch.
        let cycle = Int(t / highlightEvery)
        if cycle != lastHighlightCycle && !nodes.isEmpty {
            lastHighlightCycle = cycle
            var pick = Int.random(in: 0..<nodes.count)
            if nodes.count > 1 && pick == highlighted { pick = (pick + 1) % nodes.count }   // never the same twice in a row
            highlighted = pick
            boxLayer.contents = boxImages[nodes[pick].texels]
            measureName(nodes[pick].name)
            typedCount = -1
            // Shortest line with room for the name; the longest if none is long enough.
            lineImage = lineImages.first { $0.width >= nameSize.width + lineMargin } ?? lineImages.last
            lineLayer.contents = lineImage
            print("Highlighting \(nodes[pick].name)")
        }
        let showBox = t.truncatingRemainder(dividingBy: highlightEvery) < highlightDuration
        boxLayer.isHidden = !showBox
        lineLayer.isHidden = !showBox || lineImage == nil
        nameLayer.isHidden = !showBox || lineImage == nil

        // Type the name: one more letter every `letterInterval` seconds after the box appears.
        if showBox, let h = highlighted {
            let name = nodes[h].name
            let elapsed = t - Double(cycle) * highlightEvery
            let count = min(name.count, Int(elapsed / letterInterval))
            if count != typedCount {
                typedCount = count
                nameLayer.contents = count > 0 ? renderName(String(name.prefix(count))) : nil
            }
        }
        for (index, node) in nodes.enumerated() {
            let p = node.position
            // Spin around the celestial pole...
            let x = p.x * cosT - p.y * sinT
            let y = p.x * sinT + p.y * cosT
            // ...then tilt the pole towards us. Screen right = x, up = north, out of the screen = -y.
            let up = p.z * cosP + y * sinP
            let towardsViewer = p.z * sinP - y * cosP
            // Perspective: positions spread out as stars come towards the viewer; sprites stay the same size.
            let k = focal / (camDist - towardsViewer)
            let side = Double(node.texels) * texelPoints
            let originX = snap(cx + x * k - side / 2) + node.offset.x
            let originY = snap(cy + up * k - side / 2) + node.offset.y
            // While flaring, the bigger flare frame is centred on the star (e.g. 18x18 around 16x16).
            let pad = node.flareShown >= 0 ? Double(node.flarePad) * texelPoints : 0
            node.layer.frame = CGRect(x: originX - CGFloat(pad), y: originY - CGFloat(pad),
                                      width: CGFloat(side + 2 * pad), height: CGFloat(side + 2 * pad))

            // Centre the box on this star, at the same pixel scale (e.g. a 12x12 box around an 8x8 star).
            if showBox && index == highlighted, let box = boxImages[node.texels] {
                let boxW = Double(box.width) * texelPoints
                let boxH = Double(box.height) * texelPoints
                let boxX = snap(Double(originX) - (boxW - side) / 2)
                let boxY = snap(Double(originY) - (boxH - side) / 2)
                boxLayer.frame = CGRect(x: boxX, y: boxY, width: CGFloat(boxW), height: CGFloat(boxH))

                // Line: bottom-left corner on the box's top-right corner, plus any nudge.
                if let line = lineImage {
                    let lineX = Double(boxX) + boxW + Double(lineOffset.x) * texelPoints
                    let lineY = Double(boxY) + boxH + Double(lineOffset.y) * texelPoints
                    lineLayer.frame = CGRect(x: snap(lineX), y: snap(lineY),
                                             width: CGFloat(Double(line.width) * texelPoints),
                                             height: CGFloat(Double(line.height) * texelPoints))

                    // Name: centred along the line, sitting `nameGap` sprite pixels above it.
                    let nameX = Double(lineLayer.frame.minX) + Double((line.width - nameSize.width) / 2) * texelPoints
                    let nameY = Double(lineLayer.frame.maxY) + Double(nameGap) * texelPoints
                    nameLayer.frame = CGRect(x: snap(nameX), y: snap(nameY),
                                             width: CGFloat(Double(nameSize.width) * texelPoints),
                                             height: CGFloat(Double(nameSize.height) * texelPoints))
                }
            }
            node.layer.zPosition = CGFloat(towardsViewer)   // nearer stars draw on top
            let depth = max(0, min(1, (towardsViewer + radius) / (2 * radius)))
            var brightness = farSideBrightness + (1 - farSideBrightness) * depth
            if t < node.flickerUntil { brightness *= 1 - flickerDarkness }
            node.shade.opacity = Float(1 - brightness)
        }

        // Spaceship: fly between two stars through the 3D scene, easing out of the start and into the end.
        func project(_ p: SIMD3<Double>) -> (x: Double, y: Double, towards: Double) {
            let x = p.x * cosT - p.y * sinT
            let y = p.x * sinT + p.y * cosT
            let up = p.z * cosP + y * sinP
            let towards = p.z * sinP - y * cosP
            let k = focal / (camDist - towards)
            return (cx + x * k, cy + up * k, towards)
        }
        if trip == nil && t >= nextShipTime && nodes.count > 1, let frames = shipKinds.randomElement() {
            let from = Int.random(in: 0..<nodes.count)
            let a = nodes[from].position
            let far = nodes.indices.filter { i in
                let d = nodes[i].position - a
                return (d * d).sum().squareRoot() >= shipMinTrip
            }
            if let to = far.randomElement() {
                let d = nodes[to].position - a
                trip = Trip(from: from, to: to, start: t, duration: (d * d).sum().squareRoot() / shipSpeed, frames: frames)
                shipFrameShown = -1
                print("Spaceship: \(nodes[from].name) -> \(nodes[to].name)")
            } else {
                nextShipTime = t + Double.random(in: shipWait)
            }
        }
        if let current = trip {
            let progress = (t - current.start) / current.duration
            if progress >= 1 {
                trip = nil
                shipLayer.isHidden = true
                nextShipTime = t + Double.random(in: shipWait)
            } else {
                let eased = progress * progress * (3 - 2 * progress)
                let a = nodes[current.from].position, b = nodes[current.to].position
                let here = project(a + (b - a) * eased)
                let ahead = project(a + (b - a) * (eased + 0.01))
                let frame = Int((t - current.start) / shipFrameTime) % current.frames.count
                if frame != shipFrameShown {
                    shipFrameShown = frame
                    shipLayer.contents = current.frames[frame]
                }
                let w = Double(shipFrameWidth) * texelPoints, h = Double(shipFrameHeight) * texelPoints
                shipLayer.position = CGPoint(x: snap(here.x - w / 2) + CGFloat(w / 2),
                                             y: snap(here.y - h / 2) + CGFloat(h / 2))
                shipLayer.transform = ahead.x < here.x ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
                shipLayer.zPosition = CGFloat(here.towards)   // passes in front of and behind stars
                shipLayer.isHidden = false
            }
        }

        CATransaction.commit()
    }
}

#if SCREENSAVER

// MARK: - Screen saver

/// The class macOS loads from Starfield.saver (named in its Info.plist as NSPrincipalClass).
@objc(StarfieldSaverView)
final class StarfieldSaverView: ScreenSaverView {
    private var starfield: StarfieldView?
    private var stars: [Star] = []
    private var artDirs: [URL] = []

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 60.0
        wantsLayer = true

        // The Art and data folders are packed inside the .saver bundle's Resources folder.
        let bundle = Bundle(for: StarfieldSaverView.self)
        let resources = bundle.resourceURL ?? bundle.bundleURL
        artDirs = [resources.appendingPathComponent(artFolder), resources]
        stars = (try? loadStars(searchDirs: [resources.appendingPathComponent(dataFolder), resources])) ?? []

        if !isPreview {
            // Recent macOS versions keep the screen saver process running after it's dismissed, still animating
            // in the background. Quitting when it stops is the usual fix.
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenSaverWillStop),
                                                                name: NSNotification.Name("com.apple.screensaver.willstop"),
                                                                object: nil)
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc private func screenSaverWillStop() {
        exit(0)
    }

    /// Builds the starfield once the view has a real size and screen (it can start out at zero size).
    private func buildIfNeeded() {
        guard starfield == nil, !stars.isEmpty, bounds.width > 1, bounds.height > 1,
              let screen = window?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let view = StarfieldView(frame: bounds, screen: screen, stars: stars,
                                 sprites: SpriteLibrary(searchDirs: artDirs), drivesItself: false)
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        starfield = view
    }

    override func startAnimation() {
        super.startAnimation()
        buildIfNeeded()
    }

    override func animateOneFrame() {
        buildIfNeeded()
        starfield?.step()
    }
}

#else

// MARK: - Full-screen window that quits on any input

final class StarWindow: NSWindow {
    private let armedAt = Date().addingTimeInterval(1.5)   // ignore mouse jitter right after launch
    private var mouseStart: NSPoint?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            NSApp.terminate(nil)
            return
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            let p = NSEvent.mouseLocation
            if Date() < armedAt || mouseStart == nil {
                mouseStart = p
            } else if let s = mouseStart, hypot(p.x - s.x, p.y - s.y) > 8 {
                NSApp.terminate(nil)
                return
            }
        default:
            break
        }
        super.sendEvent(event)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let stars: [Star]
    private let searchDirs: [URL]
    private var window: StarWindow?

    init(stars: [Star], searchDirs: [URL]) {
        self.stars = stars
        self.searchDirs = searchDirs
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { NSApp.terminate(nil); return }

        let window = StarWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.backgroundColor = .black
        window.isOpaque = true
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = StarfieldView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                           screen: screen,
                                           stars: stars,
                                           sprites: SpriteLibrary(searchDirs: searchDirs))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.hide()
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Start

@main
struct StarfieldApp {
    @MainActor static func main() {
        // Find the project folder (the one holding source, Art and data). Candidates, in order:
        // a folder passed on the command line, the folder above where this file was compiled from,
        // the current folder and its parent, and the program's folder and its parent.
        let args = CommandLine.arguments
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let programDir = URL(fileURLWithPath: args[0]).deletingLastPathComponent()
        var projectDirs: [URL] = []
        if args.count > 1 { projectDirs.append(URL(fileURLWithPath: args[1])) }
        projectDirs.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent())
        projectDirs += [cwd, cwd.deletingLastPathComponent(), programDir, programDir.deletingLastPathComponent()]

        let dataDirs = projectDirs.map { $0.appendingPathComponent(dataFolder) } + projectDirs
        let artDirs = projectDirs.map { $0.appendingPathComponent(artFolder) } + projectDirs

        let loadedStars: [Star]
        do {
            loadedStars = try loadStars(searchDirs: dataDirs)
        } catch {
            print("Error: \(error)")
            exit(1)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate(stars: loadedStars, searchDirs: artDirs)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

#endif