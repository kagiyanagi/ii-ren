#!/usr/bin/env python3
import sys
import json

def main():
    original_stdout = sys.stdout
    sys.stdout = sys.stderr

    if len(sys.argv) < 2:
        original_stdout.write(json.dumps({"error": "No image path provided."}) + "\n")
        sys.exit(1)
        
    img_path = sys.argv[1]
    
    try:
        from mokuro.manga_page_ocr import MangaPageOcr
        import argostranslate.translate
        import argostranslate.package
    except ImportError:
        original_stdout.write(json.dumps({"error": "Dependencies missing. Please install: pip install mokuro argostranslate"}) + "\n")
        sys.exit(0)
        
    try:
        # Initialize Mokuro (handles comic-text-detector + manga-ocr)
        ocr = MangaPageOcr()
        
        # Ensure ja->en translation model is installed
        installed_packages = argostranslate.package.get_installed_packages()
        ja_en_installed = next(filter(lambda x: x.from_code == 'ja' and x.to_code == 'en', installed_packages), None)
        
        if not ja_en_installed:
            argostranslate.package.update_package_index()
            available_packages = argostranslate.package.get_available_packages()
            package_to_install = next(
                filter(lambda x: x.from_code == 'ja' and x.to_code == 'en', available_packages)
            )
            argostranslate.package.install_from_path(package_to_install.download())

        # Run Mokuro detection and OCR
        res = ocr(img_path)
        
        output = []
        for block in res.get('blocks', []):
            box = block['box'] # [xmin, ymin, xmax, ymax]
            x1, y1, x2, y2 = map(float, box)
            
            # Combine lines in the block without spaces (since Japanese doesn't use spaces)
            text = "".join(block.get('lines', []))
            
            if text.strip():
                translated = argostranslate.translate.translate(text, "ja", "en")
                output.append({
                    "text": text,
                    "translated": translated,
                    "boundingBox": {
                        "vertices": [
                            {"x": x1, "y": y1},
                            {"x": x2, "y": y1},
                            {"x": x2, "y": y2},
                            {"x": x1, "y": y2}
                        ]
                    }
                })
                
        original_stdout.write(json.dumps({"success": True, "data": output}) + "\n")
    except Exception as e:
        original_stdout.write(json.dumps({"error": str(e)}) + "\n")

if __name__ == "__main__":
    main()
