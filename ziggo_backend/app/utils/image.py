import io
import logging
from PIL import Image

logger = logging.getLogger(__name__)

def process_image_upload(data: bytes, is_profile: bool = False, quality: int = 82) -> bytes:
    """
    Resizes and compresses image data:
    - Banners/Others are resized to max width 1280.
    - Profiles are resized to max width 512.
    - Converts to WebP format (or falls back to JPEG if WebP is not available).
    """
    try:
        img = Image.open(io.BytesIO(data))
        
        # Determine target size
        max_width = 512 if is_profile else 1280
        
        # Check if resize is needed
        width, height = img.size
        if width > max_width:
            new_height = int(height * (max_width / width))
            try:
                img = img.resize((max_width, new_height), Image.Resampling.LANCZOS)
            except AttributeError:
                # Fallback for older Pillow versions
                img = img.resize((max_width, new_height), Image.ANTIALIAS)

        # Output bytes buffer
        out_buf = io.BytesIO()

        # Try to save as WebP
        try:
            img.save(out_buf, format="WEBP", quality=quality)
            return out_buf.getvalue()
        except Exception as e:
            logger.warning(f"Failed to save as WEBP: {e}. Falling back to JPEG/PNG.")
            out_buf = io.BytesIO()
            # If WebP is unavailable, fallback to JPEG (for non-transparent) or PNG (for transparent)
            if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
                img.save(out_buf, format="PNG", optimize=True)
            else:
                img = img.convert("RGB")
                img.save(out_buf, format="JPEG", quality=quality)
            return out_buf.getvalue()
    except Exception as e:
        logger.error(f"Error processing image: {e}")
        # Fail safe: return original data untouched
        return data
