#!/usr/bin/env python3
"""Sensitive information masking script — redacts confidential data in screenshots"""
import argparse
import sys


def main():
    parser = argparse.ArgumentParser(
        description="Redact sensitive information in screenshots with filled rectangles",
        epilog='Example: mask_sensitive.py --input shot.png --output masked.png --regions "100,50,400,80" "500,200,800,230"',
    )
    parser.add_argument("--input", required=True, help="Path to input image")
    parser.add_argument("--output", required=True, help="Path to output image")
    parser.add_argument(
        "--regions",
        nargs="+",
        required=True,
        help='Mask region "x1,y1,x2,y2" (multiple allowed. Origin (0,0) at top-left, pixel values)',
    )
    parser.add_argument(
        "--color",
        default="0,0,0",
        help='Fill color "R,G,B" (default: 0,0,0 = black)',
    )
    parser.add_argument(
        "--preview",
        action="store_true",
        help="Display mask regions with red outlines (no fill. For position verification)",
    )
    args = parser.parse_args()

    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print(
            "ERROR: Pillow is not installed. Install it with the following command:",
            file=sys.stderr,
        )
        print("  pip install Pillow", file=sys.stderr)
        sys.exit(1)

    # Parse color
    try:
        fill_color = tuple(int(v.strip()) for v in args.color.split(","))
        if len(fill_color) != 3:
            raise ValueError
    except ValueError:
        print(
            'ERROR: --color must be in "R,G,B" format (e.g., "0,0,0")',
            file=sys.stderr,
        )
        sys.exit(1)

    # Load image
    try:
        img = Image.open(args.input)
    except FileNotFoundError:
        print(f"ERROR: Input file not found: {args.input}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: Cannot open image: {e}", file=sys.stderr)
        sys.exit(1)

    w, h = img.size
    draw = ImageDraw.Draw(img)
    masked_count = 0

    for i, region in enumerate(args.regions, 1):
        try:
            coords = tuple(int(v.strip()) for v in region.split(","))
            if len(coords) != 4:
                raise ValueError
            x1, y1, x2, y2 = coords
        except ValueError:
            print(
                f'ERROR: Region {i} "{region}" must be in "x1,y1,x2,y2" format',
                file=sys.stderr,
            )
            sys.exit(1)

        # Clamp coordinates
        x1 = max(0, min(x1, w))
        y1 = max(0, min(y1, h))
        x2 = max(x1, min(x2, w))
        y2 = max(y1, min(y2, h))

        if args.preview:
            # Preview mode: display with red outlines
            draw.rectangle([x1, y1, x2, y2], outline=(255, 0, 0), width=3)
        else:
            # Mask mode: fill
            draw.rectangle([x1, y1, x2, y2], fill=fill_color)
        masked_count += 1

    img.save(args.output)
    mode = "preview" if args.preview else "masked"
    print(f"OK: {args.output} ({w}x{h}, {masked_count} regions {mode})")


if __name__ == "__main__":
    main()
