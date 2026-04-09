---
name: shogun-screenshot
description: |
  Captures and processes screenshots. Retrieves the latest image from local screenshots,
  captures web pages with Playwright, trims/resizes images, and masks sensitive info with black overlay.
  Trigger: "screenshot", "screen capture", "latest screenshot", "image processing", "trim", "mask",
  "took a screenshot", "capture screen".
  Do NOT use for: image generation (use shogun-imagegen).
argument-hint: "[url-or-target e.g. https://example.com, latest]"
allowed-tools: Bash, Read
---

# /shogun-screenshot - Screenshot Capture & Processing Skill

## North Star

The north star of this skill is **content differentiation through enhanced visual quality in articles and reports**.
By inserting high-quality images (masked, properly trimmed) into articles and reports,
we achieve differentiation from competitors who rely on text alone.

## Input

`$ARGUMENTS` = Target specification (URL or mode keyword)

- URL (`https://...`) → Mode 2: Web capture
- `latest` (optional) → Mode 1: Local screenshot retrieval
- No arguments → Selects the optimal mode based on user intent

## Overview

Captures and processes screenshots. There are 4 modes:

1. **Local retrieval**: Retrieves the latest image from the user's screenshot folder
2. **Web capture**: Captures a page via Playwright MCP with a specified URL
3. **Trimming**: Crops and resizes a portion of an existing image
4. **Masking**: Black-out overlay for sensitive information (API keys, personal data, etc.)

## When to Use

- When asked "show me the latest screenshot" or "take a screenshot"
- When inserting images into articles or reports
- When a UI screen capture is needed
- When image trimming/cropping is needed
- When masking confidential information in screenshots

## Configuration

Screenshot folder paths are managed in `config/settings.yaml` (priority-ordered array):

```yaml
screenshot:
  paths:
    - "/path/to/your/Screenshots/"      # OS screenshot save location
    - "queue/screenshots/"               # Received from mobile apps etc.
  capture_dir: "images/"                 # Web capture save location
  trim_dir: "images/trimmed/"            # Save location for trimmed images
```

Searches the `paths` array from top to bottom, using the first directory that exists and contains image files.
Returns an error if none of the paths exist.

## Instructions

### Mode 1: Local Screenshot Retrieval (multi-path fallback)

**Steps**:
1. Read the `screenshot.paths` array from config/settings.yaml
2. **Search each path in priority order**:
   a. Verify directory exists with `ls <path>` (if not found, move to next)
   b. For existing paths, get latest images with `ls -lt <path>/*.png <path>/*.jpg 2>/dev/null | head -5`
3. Display the most recent image file using the Read tool
4. If multiple paths contain images, **compare the latest from all paths and display the newest**

**Helper script** (auto-searches all paths):
```bash
bash skills/shogun-screenshot/scripts/capture_local.sh -n 3
```

**When manually specifying a path**:
```bash
# Use the paths configured in config/settings.yaml screenshot.paths
ls -lt "/path/to/Screenshots/"*.png 2>/dev/null | head -3
```

**Note**: The directory itself may not exist (unmounted drive, etc.).
Suppress errors for non-existent paths with `2>/dev/null`.

### Mode 2: Web Capture (Playwright MCP)

1. Navigate to URL with Playwright MCP's `playwright_navigate`
2. Capture with `playwright_screenshot`
   - fullPage: true (entire page)
   - selector: specified (element only)
   - savePng: true, downloadsDir: save location
3. Return the path of the saved PNG

### Mode 3: Trimming

1. Receive the path of the target image
2. Execute trimming with Python (PIL/Pillow)
3. Save the trimmed image

```bash
python3 skills/shogun-screenshot/scripts/trim_image.py \
  --input /path/to/image.png \
  --output /path/to/trimmed.png \
  --crop "x1,y1,x2,y2"
```

Option: `--resize "width,height"` to also resize simultaneously.

### Mode 4: Sensitive Information Masking

Masks API keys, topic names, personal data, etc. in screenshots with black rectangles.

```bash
# Single region
python3 skills/shogun-screenshot/scripts/mask_sensitive.py \
  --input /path/to/image.png \
  --output /path/to/masked.png \
  --regions "100,50,400,80"

# Multiple regions
python3 skills/shogun-screenshot/scripts/mask_sensitive.py \
  --input /path/to/image.png \
  --output /path/to/masked.png \
  --regions "100,50,400,80" "500,200,800,230"

# Position check (red border preview, no fill)
python3 skills/shogun-screenshot/scripts/mask_sensitive.py \
  --input /path/to/image.png \
  --output /path/to/preview.png \
  --regions "100,50,400,80" --preview
```

Options:
- `--color "R,G,B"` — Fill color (default: black `0,0,0`)
- `--preview` — Red border display only (no fill; for coordinate verification)

**Steps**:
1. Use the Read tool to inspect the image and identify regions to mask
2. Verify coordinates are correct with `--preview`
3. If preview looks good, remove `--preview` and execute

## Guidelines

- Take care not to include API keys or credentials in images. Always mask with Mode 4 before publishing
- If Playwright MCP is unavailable, operate in local mode only
- For processing large numbers of screenshots at once, use the batch processing script
- Trimming/masking coordinates are pixel values with origin at top-left (0,0)
- Default save location: the project's images/ directory
