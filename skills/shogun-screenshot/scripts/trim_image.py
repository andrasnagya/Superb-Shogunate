#!/usr/bin/env python3
"""Image cropping script — for the shogun-screenshot skill"""
import argparse
import sys

def main():
    parser = argparse.ArgumentParser(description="Crop an image")
    parser.add_argument("--input", required=True, help="Path to input image")
    parser.add_argument("--output", required=True, help="Path to output image")
    parser.add_argument("--crop", required=True,
                        help='Crop coordinates "x1,y1,x2,y2" (origin (0,0) at top-left, pixel values)')
    parser.add_argument("--resize", default=None,
                        help='Resize "width,height" (omit for crop only)')
    args = parser.parse_args()

    try:
        from PIL import Image
    except ImportError:
        print("ERROR: Pillow is not installed. Install it with the following command:", file=sys.stderr)
        print("  pip install Pillow", file=sys.stderr)
        sys.exit(1)

    try:
        coords = tuple(int(v.strip()) for v in args.crop.split(","))
        if len(coords) != 4:
            raise ValueError
        x1, y1, x2, y2 = coords
    except ValueError:
        print('ERROR: --crop must be in "x1,y1,x2,y2" format (e.g., "100,50,800,600")', file=sys.stderr)
        sys.exit(1)

    try:
        img = Image.open(args.input)
    except FileNotFoundError:
        print(f"ERROR: Input file not found: {args.input}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: Cannot open image: {e}", file=sys.stderr)
        sys.exit(1)

    w, h = img.size
    x1 = max(0, min(x1, w))
    y1 = max(0, min(y1, h))
    x2 = max(x1, min(x2, w))
    y2 = max(y1, min(y2, h))

    cropped = img.crop((x1, y1, x2, y2))

    if args.resize:
        try:
            rw, rh = (int(v.strip()) for v in args.resize.split(","))
            cropped = cropped.resize((rw, rh), Image.LANCZOS)
        except ValueError:
            print('ERROR: --resize must be in "width,height" format', file=sys.stderr)
            sys.exit(1)

    cropped.save(args.output)
    print(f"OK: {args.output} ({cropped.size[0]}x{cropped.size[1]})")

if __name__ == "__main__":
    main()
