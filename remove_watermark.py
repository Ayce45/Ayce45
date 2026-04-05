"""
Watermark removal tool for tiled/repeating watermark patterns.

Uses tile extraction from dark regions + adaptive subtraction + denoising.
Inspired by https://github.com/zuruoke/watermark-removal but uses classical
CV techniques (no deep learning required).

Usage:
    python remove_watermark.py --input image.jpg --output result.jpg
"""
import argparse
import cv2
import numpy as np


def extract_watermark_tile(img, tile_w=36, tile_h=54):
    """Extract watermark pattern by taking the median of the darkest tiles."""
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    h, w = img.shape[:2]

    tiles = []
    for y in range(0, h - tile_h, tile_h):
        for x in range(0, w - tile_w, tile_w):
            brightness = np.mean(gray[y:y+tile_h, x:x+tile_w])
            tile = img[y:y+tile_h, x:x+tile_w].astype(np.float64)
            tiles.append((brightness, tile))

    tiles.sort(key=lambda x: x[0])
    n = max(15, len(tiles) // 3)
    wm = np.median([t[1] for t in tiles[:n]], axis=0)
    return wm


def build_watermark_layer(h, w, wm_tile):
    """Tile the watermark pattern across the full image."""
    th, tw = wm_tile.shape[:2]
    layer = np.zeros((h, w, 3), dtype=np.float64)
    for y in range(0, h, th):
        for x in range(0, w, tw):
            y2, x2 = min(h, y + th), min(w, x + tw)
            layer[y:y2, x:x2] = wm_tile[:y2-y, :x2-x]
    return layer


def remove_watermark(img, wm_tile):
    """Remove watermark with adaptive alpha based on local brightness."""
    h, w = img.shape[:2]
    img_f = img.astype(np.float64)
    layer = build_watermark_layer(h, w, wm_tile)

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(np.float64)
    brightness = cv2.GaussianBlur(gray, (61, 61), 0)

    # Stronger subtraction on dark areas, lighter on bright areas
    alpha = np.clip(2.0 - brightness / 60.0, 0.3, 2.2)
    alpha = cv2.GaussianBlur(alpha, (31, 31), 0)[:, :, np.newaxis]

    result = img_f - alpha * layer
    return np.clip(result, 0, 255).astype(np.uint8)


def cleanup(img):
    """Apply gentle denoising and contrast restoration."""
    clean = cv2.fastNlMeansDenoisingColored(img, None, 3, 3, 7, 21)

    lab = cv2.cvtColor(clean, cv2.COLOR_BGR2LAB)
    clahe = cv2.createCLAHE(clipLimit=1.3, tileGridSize=(8, 8))
    lab[:, :, 0] = clahe.apply(lab[:, :, 0])
    return cv2.cvtColor(lab, cv2.COLOR_LAB2BGR)


def main():
    parser = argparse.ArgumentParser(description="Remove tiled watermarks from images")
    parser.add_argument("--input", default="input_image.jpg", help="Input image path")
    parser.add_argument("--output", default="result_final.jpg", help="Output image path")
    parser.add_argument("--tile-w", type=int, default=36, help="Watermark tile width")
    parser.add_argument("--tile-h", type=int, default=54, help="Watermark tile height")
    args = parser.parse_args()

    img = cv2.imread(args.input)
    if img is None:
        print(f"Error: Could not load {args.input}")
        return

    print(f"Image: {img.shape[1]}x{img.shape[0]}")
    print("Extracting watermark pattern...")
    wm = extract_watermark_tile(img, args.tile_w, args.tile_h)

    print("Removing watermark...")
    result = remove_watermark(img, wm)

    print("Cleaning up...")
    final = cleanup(result)

    cv2.imwrite(args.output, final, [cv2.IMWRITE_JPEG_QUALITY, 95])
    print(f"Saved: {args.output}")


if __name__ == "__main__":
    main()
