# Recent Changes - Enhanced Pill Experience

## What's New

### 1. Fixed Waveform Overlap ✅
- **Before**: Waveform overlapped with mic/model selectors
- **After**: Waveform only shows during recording, selectors hidden while recording
- **Result**: Clean, no overlap, proper dynamic layout

### 2. Screen Following ✅
- **Feature**: Pill now follows you to the active screen
- **How it works**: Automatically detects cursor position and moves to that display
- **Benefit**: Multi-monitor setup friendly

### 3. Compact/Expanded States ✅
- **Compact Mode**: 
  - Tiny 60×60px circle
  - 40% opacity (very subtle)
  - Black theme with transparency
  - Click anywhere to expand
  
- **Expanded Mode**:
  - 400px width showing all controls
  - 100% opacity
  - Black themed with white text
  - Shows mic selector and model selector

- **Recording Mode**:
  - 350px width
  - Shows waveform instead of selectors
  - Red tint background
  - Stop button visible

### 4. Auto-Paste (Clipboard) ✅
- **Implementation**: Reliable clipboard-based approach
- **How it works**: Auto-copies transcript, you press Cmd+V to paste
- **Benefit**: Works everywhere, no special permissions needed

## Visual Flow

```
Compact (60×60px, subtle)
    ↓ [Click anywhere]
Expanded (400px, full controls)
    ↓ [Click record button]
Recording (350px, waveform)
    ↓ [Click stop]
Processing → Success → Back to Expanded
```

## New Styling

### Black Theme
- Background: `rgba(0, 0, 0, 0.7)` - Semi-transparent black
- Text: White with various opacity levels
- Borders: White at 15% opacity
- Selectors: Black themed dropdowns

### States
- **Compact**: 0.4 opacity, hover to 0.7
- **Expanded**: 1.0 opacity
- **Recording**: Red-tinted background
- **Success**: Green confirmation
- **Error**: Red error state

## Technical Implementation

### Electron Changes
- Window starts at 60×60px
- IPC messages for expand/compact
- Screen tracking and repositioning
- Always-on-top behavior maintained

### React Component
- New `isExpanded` state
- Conditional rendering based on state
- Dynamic width management
- Smooth transitions (0.3s ease)

### CSS Updates
- New compact/expanded classes
- Black theme colors
- Improved selector styling
- Better hover states

## Usage

1. **Launch**: Tiny circle appears at bottom center
2. **Expand**: Click anywhere on the circle
3. **Select**: Choose microphone and model
4. **Record**: Click record button
5. **Stop**: Click stop when done
6. **Paste**: Press Cmd+V to paste transcript

## Build the App

```bash
./build-app.sh
```

Creates:
- `dist/Whisper Flow.app`
- `dist/Whisper Flow.dmg`

Install by opening DMG and dragging to Applications.