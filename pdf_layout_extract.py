#!/usr/bin/env python3
"""Print PDF page layout as JSON for Ruby-side HTML rendering."""

import argparse
import json
import sys

from layout_extractor import extract_layout


def main():
    parser = argparse.ArgumentParser(
        description="Extract PDF layout JSON (layout, width, height) to stdout."
    )
    parser.add_argument("pdf_path", help="Path to source PDF")
    parser.add_argument(
        "--page",
        type=int,
        default=0,
        help="Zero-based page index (same convention as extract2.py / PyMuPDF)",
    )
    parser.add_argument(
        "--output-dir",
        default="output",
        help="Directory for extracted raster images (must exist or be creatable)",
    )
    args = parser.parse_args()

    try:
        layout, width, height = extract_layout(
            args.pdf_path, args.page, args.output_dir
        )
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)

    payload = {
        "layout": layout,
        "width": float(width),
        "height": float(height),
    }
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
