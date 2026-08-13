import os
import io
import shutil
from PIL import Image

def process_image_in_place(filepath, is_profile=False, quality=82):
    try:
        # Load image
        with open(filepath, 'rb') as f:
            data = f.read()

        img = Image.open(io.BytesIO(data))
        orig_size = len(data)
        
        # Determine target size
        max_width = 512 if is_profile else 1280
        
        # Check if resize is needed
        width, height = img.size
        if width > max_width:
            new_height = int(height * (max_width / width))
            try:
                img = img.resize((max_width, new_height), Image.Resampling.LANCZOS)
            except AttributeError:
                img = img.resize((max_width, new_height), Image.ANTIALIAS)

        # Output bytes buffer
        out_buf = io.BytesIO()

        # Try to save as WebP
        try:
            img.save(out_buf, format="WEBP", quality=quality)
            processed_data = out_buf.getvalue()
        except Exception as e:
            print(f"Failed WEBP save for {filepath}: {e}. Falling back to JPEG/PNG.")
            out_buf = io.BytesIO()
            if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
                img.save(out_buf, format="PNG", optimize=True)
            else:
                img = img.convert("RGB")
                img.save(out_buf, format="JPEG", quality=quality)
            processed_data = out_buf.getvalue()

        # Save backup if not already present
        bak_path = filepath + ".bak"
        if not os.path.exists(bak_path):
            with open(bak_path, 'wb') as f:
                f.write(data)

        # Overwrite original
        with open(filepath, 'wb') as f:
            f.write(processed_data)

        new_size = len(processed_data)
        print(f"Processed {filepath}: {orig_size / 1024:.1f}KB -> {new_size / 1024:.1f}KB (Saved {(orig_size - new_size) / 1024:.1f}KB)")
        return orig_size, new_size
    except Exception as e:
        print(f"Error processing {filepath}: {e}")
        return 0, 0

def main():
    # Base uploads directory inside container
    uploads_dir = "/app/ziggo_admin_panel/static/uploads"
    if not os.path.exists(uploads_dir):
        # Fallback to local sibling path if run outside container
        current_dir = os.path.dirname(os.path.abspath(__file__))
        uploads_dir = os.path.abspath(os.path.join(current_dir, "..", "ziggo_admin_panel", "static", "uploads"))
    
    print(f"Scanning directory: {uploads_dir}")
    
    allowed_exts = {".jpg", ".jpeg", ".png", ".webp", ".avif"}
    ignored_dirs = {"driver_docs", "vendor_docs"}
    
    total_orig = 0
    total_new = 0
    file_count = 0
    
    for root, dirs, files in os.walk(uploads_dir):
        # Modify dirs in-place to ignore certain directories
        dirs[:] = [d for d in dirs if d not in ignored_dirs]
        
        for file in files:
            ext = os.path.splitext(file)[1].lower()
            if ext in allowed_exts:
                filepath = os.path.join(root, file)
                
                # Skip already backed up files or backup files themselves
                if filepath.endswith('.bak'):
                    continue
                
                # Determine type
                is_profile = "customers" in filepath or "drivers" in filepath
                
                orig_s, new_s = process_image_in_place(filepath, is_profile=is_profile)
                if orig_s > 0:
                    total_orig += orig_s
                    total_new += new_s
                    file_count += 1

    print("\n--- Backfill Completed ---")
    print(f"Total processed files: {file_count}")
    if total_orig > 0:
        savings = total_orig - total_new
        pct = (savings / total_orig) * 100
        print(f"Original Volume Size: {total_orig / 1024 / 1024:.2f} MB")
        print(f"New Volume Size:      {total_new / 1024 / 1024:.2f} MB")
        print(f"Space Saved:          {savings / 1024 / 1024:.2f} MB ({pct:.1f}% reduction)")

if __name__ == "__main__":
    main()
