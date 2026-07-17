# Assets Directory

## Icon Requirements

For the macOS app, you need an icon file at `assets/icon.png`.

### Icon Specifications:
- Format: PNG
- Size: 512x512 pixels or larger (1024x1024 recommended)
- Background: Transparent or solid
- Design: Simple microphone icon or waveform visual

### Quick Icon Creation:

You can use any of these methods:

1. **Online Tools:**
   - Use [Canva](https://www.canva.com) or [Figma](https://www.figma.com)
   - Create a 1024x1024 design with a microphone icon
   - Export as PNG

2. **macOS Built-in:**
   - Open Preview
   - File > New from Clipboard (after copying an image)
   - Tools > Adjust Size (set to 512x512 or 1024x1024)
   - Export as PNG

3. **Icon Generator:**
   - Use [Icon Kitchen](https://icon.kitchen/)
   - Upload or create an icon
   - Download PNG version

### Default Icon:

If you don't provide a custom icon, electron-builder will use a default icon.

To add your icon:
1. Create or download a 512x512 PNG image
2. Save it as `assets/icon.png`
3. Rebuild the app with `./build-app.sh`