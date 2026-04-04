# XLFQL — XLIFF QuickLook Preview Extension

A macOS QuickLook extension that previews XLIFF 1.2 files (`.xlf`, `.xliff`) directly in Finder by pressing the space bar.

Displays translation units (trans-units) in a grid format with Source, Target, and Note columns.

![QuickLook Preview](screenshots/app.png)

## Features

- Grid preview of XLIFF 1.2 files
- Source / Target / Note columns
- Section headers for multiple `<file>` elements
- Segment-level display via `<seg-source>` + `<mrk>` tags
- Inline tag rendering (`<g>`, `<x>`, `<bpt>`, `<ept>`, `<ph>`, etc.)
- Text wrapping with dynamic row heights
- In-cell text selection

## Installation

1. Download `XLFQLApp.app` from [Releases](../../releases)
2. Copy `XLFQLApp.app` to `/Applications`
3. Launch `XLFQLApp.app` once (this registers the extension with macOS)
4. Select a `.xlf` file in Finder and press Space to preview

> **Note:** This app is unsigned. On first launch, macOS Gatekeeper may block it. Run the following command before launching:
> ```bash
> xattr -cr /Applications/XLFQLApp.app
> ```

## Uninstallation

1. Move `/Applications/XLFQLApp.app` to Trash
2. Run `qlmanage -r` in Terminal to reset the QuickLook cache

## Building from Source

### Requirements

- macOS 13+
- Xcode 15+

### Run

1. Open `XLFQLApp.xcodeproj` in Xcode
2. Select the `XLFQLApp` scheme
3. Product → Run (⌘R)

### Export for Distribution

1. Product → Archive
2. Distribute App → Custom → Copy App
3. Distribute the exported `XLFQLApp.app`
