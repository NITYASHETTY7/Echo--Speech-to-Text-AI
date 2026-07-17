# Mac Beginner Guide: How to Test Echo v1.2.20

Welcome to Mac! Don't worry, this guide will show you **exactly** where everything is and how to find it. Let's go step by step.

---

## Part 1: The Mac Basics You Need to Know

### What is Finder?
**Finder** is like File Explorer on Windows. It shows files and folders on your Mac.

**How to open Finder:**
1. Look at the bottom of your screen → You'll see a dock (taskbar) with app icons
2. Find the **smiling face icon** (Finder) - it's usually on the far left
3. Click it
4. A window opens showing your files

See this? → The dock at the bottom of screen:
```
[Finder icon] [other apps...]
```

### What is Applications folder?
**Applications** is a special folder where all your Mac apps live.

**How to find Applications:**
1. Open Finder (smiling face icon at bottom)
2. In the top menu bar, click: **Finder** → **Applications**
   OR
   Press: **Cmd + Shift + A** (keyboard shortcut)
3. A window opens showing Applications folder with all installed apps

### What is Desktop?
**Desktop** is the main screen you see when you start your Mac.

**Where Desktop files appear:**
- Right side of your screen (all those icons you see)
- Also accessible in Finder → Desktop (in left sidebar)

---

## Part 2: Getting the Echo App File

### Step 1: Open Finder and Navigate to the Echo File

1. **Click the Finder icon** at the bottom left of your screen (smiling face)
   - A Finder window opens
   
2. **Go to Desktop folder:**
   - Look at the left sidebar → Find "Desktop"
   - Click "Desktop"
   - Now you see your desktop files in the window

3. **Find the Project folder:**
   - You'll see a folder called: `Project's by Narendra`
   - Double-click it (opens it)
   
4. **Find the echo folder:**
   - You'll see a folder called: `echo`
   - Double-click it (opens it)
   
5. **Find the dist folder:**
   - You'll see a folder called: `dist`
   - Double-click it (opens it)
   
6. **Find the DMG file:**
   - You'll now see files including:
     - `Echo-1.2.20-arm64.dmg` ← **Use this one for Apple Silicon M-series Macs**
     - `Echo-1.2.20.dmg` ← Use this if you have Intel Mac (older)
   
   (If you're not sure which you have, scroll down to "How to check if your Mac is Apple Silicon or Intel" section)

---

## Part 3: Mount (Open) the DMG File

### What does "mount" mean?
**Mount** = "open and make the contents accessible". When you mount a DMG, it's like inserting a DVD into a DVD player.

### How to Mount the DMG:

1. **Double-click the DMG file:**
   - Right-click `Echo-1.2.20-arm64.dmg`
   - Select: **Open**
   - Wait 5-10 seconds...

2. **A new window appears** showing:
   ```
   Echo.app (the application)
   Applications (a folder)
   Background image
   ```

3. **You've now "mounted" the DMG!** ✅
   - Think of it like inserting a DVD
   - You can now see what's inside

---

## Part 4: Copy Echo.app to Applications Folder

### Why copy?
You need to copy the app from the DMG to Applications folder so it can run on your Mac permanently.

### How to Copy:

1. **You should still see the DMG window** with Echo.app visible

2. **Click and hold Echo.app:**
   - With your mouse/trackpad, hold down the button on: `Echo.app`
   - Keep holding...

3. **Drag to Applications:**
   - While holding, move your mouse to the `Applications` folder (visible in the same window)
   - Still holding...
   - Release the mouse button
   - Echo.app is now copied!

4. **Wait for copy to complete:**
   - You'll see a progress indicator
   - Wait until it says 100%
   - Takes about 30 seconds

5. **Close the DMG window:**
   - Click the red X button at the top-left of the window
   - The DMG is still mounted, but the window closes

---

## Part 5: First Launch (The Tricky Part - Read This!)

### ⚠️ IMPORTANT: Gatekeeper Protection

When you try to launch Echo.app, your Mac will say:
```
"Apple cannot check it for malicious software"
```

**This is NORMAL. Not a bug. Expected.**

The app is unsigned (we didn't pay Apple for code signing yet). This warning is safe to bypass.

### How to Bypass (One-Time Only):

1. **Open Applications folder:**
   - Open Finder → Click "Applications" in left sidebar
   - You'll see your apps

2. **Find Echo.app:**
   - Scroll down until you find `Echo` (or `Echo.app`)
   - It should have a rocket/diamond-like icon

3. **Right-click on Echo.app:**
   - Place your finger on the trackpad
   - Use **two fingers** and click (this is right-click on Mac)
   - OR use **Ctrl + click** with one finger
   - A menu appears

4. **Click "Open" from the menu:**
   - You'll see options including "Open"
   - Click "Open"
   - Now a dialog appears with an "Open" button (this time it's NOT greyed out)
   - Click "Open" ✅

5. **App launches!**
   - Echo starts
   - A tiny black pill appears at the bottom of your screen
   - First launch complete! 🎉

**After this first time:**
- You can just double-click Echo.app normally
- No more Gatekeeper warning
- It launches immediately

---

## Part 6: Using Echo - First Time Setup

### When Echo launches:

1. **Look at the bottom of your screen:**
   - You'll see a tiny black rectangle (the "pill")
   - It's very small on purpose
   - If you don't see it, check all edges of the screen

2. **Hover your mouse over it:**
   - Move your mouse to the pill
   - It will expand slightly
   - You'll see small buttons appear

3. **Click the expand button:**
   - Click the button with three lines (or → arrow)
   - The pill grows to show more options

4. **Click the Settings gear icon:**
   - Look for a gear/cog icon
   - Click it
   - Settings dialog opens

### Adding Your API Keys:

You need **two keys** for testing:

#### Key #1: Groq API Key (for transcription)
1. Open your web browser
2. Go to: `https://console.groq.com`
3. Sign up if needed (free)
4. Look for "API Keys" section
5. Create a new key or copy existing one
6. Copy the key (long text string)
7. Back in Echo Settings → paste it in "Groq API Key" field
8. Click Save

#### Key #2: Bedrock API Key (for grammar correction)
1. Open your web browser
2. Go to: `https://aws.amazon.com`
3. Sign in to your AWS account (create one if needed)
4. Search for "Bedrock" in the search bar
5. Go to Bedrock service
6. Look for "API Keys" section
7. Create a new key or use existing one
8. Copy the key
9. Back in Echo Settings → paste it in "Bedrock API Key" field
10. Click Save

---

## Part 7: Testing Transcription (Make Sure It Works)

### Before testing grammar correction, test basic transcription:

1. **Click the record button:**
   - On the Echo pill, find the microphone/record button
   - Click it
   - Recording starts

2. **Speak into your Mac:**
   - Say: "Hello, this is a test"
   - Speak clearly
   - Wait a moment

3. **Click stop:**
   - Click the red stop button
   - Recording stops

4. **Wait for transcription:**
   - Wait 3-5 seconds
   - Text should appear on screen
   - It should say: "Hello, this is a test"

5. **Check if it worked:**
   - ✅ Text appeared? → Basic features work! Continue to next step.
   - ❌ Nothing appeared? → Check if Groq key is valid (you might have copied it wrong)

---

## Part 8: Testing Grammar Correction (The Key Test!)

### First, check AWS settings:

1. **Open web browser**
2. **Go to: `https://aws.amazon.com`**
3. **Sign in**
4. **Search for: "Bedrock"** (search bar at top)
5. **Click: "Bedrock"** service
6. **In left sidebar, click: "Model access"**
7. **Look for: "Amazon Nova"**
   - Verify the status says: **"Access granted"** ✅
   - If it says "Access requested", wait 24 hours or request it
8. **Make sure you're in region: "us-east-1"** (check top-right corner)
   - You'll see a region dropdown
   - Click it
   - Select: "N. Virginia" (which is us-east-1)

### Now test in Echo:

1. **In Echo Settings, toggle Grammar Correction ON:**
   - Find the toggle switch for "Grammar Correction"
   - Click to turn it ON
   - You should see it turn blue/green (indicating ON)

2. **Click record:**
   - On the pill, click the record button
   - Recording starts

3. **Speak with bad grammar (on purpose!):**
   - Say this exactly: "i goed to the store yesterday for buying grocerys and that was very good"
   - Intentionally use wrong grammar
   - Speak clearly

4. **Click stop:**
   - Click the red stop button
   - Recording ends

5. **Wait 5-10 seconds:**
   - Your Mac is now:
     - Transcribing your voice to text (Groq)
     - Correcting the grammar (Nova Lite)
   - You'll see two steps happen

6. **Expected result:**
   - Original: "i goed to the store yesterday for buying grocerys and that was very good"
   - Corrected: "I went to the store yesterday to buy groceries and that was very good"
   - If you see corrected text → **SUCCESS!** 🎉

7. **If it doesn't work:**
   - Check if you have poor internet (grammar correction needs network)
   - Check if Bedrock key is correct
   - Make sure Grammar Correction is toggled ON
   - Make sure Nova access is "granted" in AWS

---

## Part 9: Checking Logs (If Something Goes Wrong)

### What are logs?
**Logs** = messages that show what the app is doing behind the scenes. If something fails, logs tell you why.

### How to see logs while app runs:

1. **Close Echo app:**
   - Click the red X button on Echo window
   - Or press: **Cmd + Q**

2. **Open Terminal:**
   - Open Finder
   - Click "Applications" in left sidebar
   - Find folder called "Utilities"
   - Double-click "Utilities"
   - Find "Terminal" app
   - Double-click it
   - A black window opens (Terminal)

3. **In Terminal, type this command and press Enter:**
   ```
   /Applications/Echo.app/Contents/MacOS/Echo
   ```
   - Echo app launches
   - BUT now you can see all the logs in the Terminal window!

4. **Look for these messages:**
   - ✅ `[bedrock] grammar correction applied` → SUCCESS!
   - ❌ `[bedrock] grammar correction failed` → Something wrong with key
   - ❌ `ResourceNotFoundException` → Nova model not enabled
   - ❌ `AccessDeniedException` → Bedrock key doesn't have Nova access

5. **To stop:**
   - Press: **Ctrl + C** (hold Ctrl, press C)
   - App closes and Terminal shows `$` prompt

---

## Part 10: Unmount the DMG (Cleanup)

### When you're done testing:

1. **Open Finder**
2. **Look at left sidebar:**
   - Find "Echo" under "Devices" section
   - Click the eject icon next to it (↑ arrow)
   - DMG unmounts

OR

1. **On your desktop:**
   - Look for "Echo" disk icon
   - Drag it to the Trash
   - DMG unmounts

---

## Appendix: Mac Keyboard Shortcuts You'll Need

| Task | Shortcut |
|------|----------|
| Copy | **Cmd + C** |
| Paste | **Cmd + V** |
| Quit app | **Cmd + Q** |
| Find Files | **Cmd + F** |
| Right-click | **Ctrl + click** or **two-finger tap on trackpad** |
| Open Applications | **Cmd + Shift + A** |
| Open Desktop | **Cmd + Shift + D** |
| Take Screenshot | **Cmd + Shift + 3** |
| Search Spotlight | **Cmd + Space** then type |

---

## Appendix: How to Check If Your Mac is Apple Silicon or Intel

### Why you need to know:
- **Apple Silicon** (M1, M2, M3, etc.) → Use `Echo-1.2.20-arm64.dmg`
- **Intel** (older Macs) → Use `Echo-1.2.20.dmg`

### How to check:

1. **Click the Apple menu** at top-left of screen
   - You'll see: 
   ```
    [Apple icon] 
   ```
   - Click it

2. **Select: "About This Mac"**
   - A window appears

3. **Look for "Chip" or "Processor":**
   - If it says: "Apple M1" or "M2" or "M3" → You have **Apple Silicon** ✅
   - If it says: "Intel Core i5" or "i7" or similar → You have **Intel** ✅

---

## Appendix: Basic Mac Trackpad Gestures

If you're using a Mac trackpad (not an external mouse):

| Action | How To Do It |
|--------|------------|
| Left-click | Tap once with one finger |
| Right-click | Tap with two fingers, OR hold Ctrl and tap |
| Drag | Tap and hold, then slide finger |
| Scroll | Two fingers scroll up/down |
| Back | Two fingers left swipe |
| Forward | Two fingers right swipe |

---

## Appendix: If Gatekeeper Still Blocks You

If you still see "is damaged" error after right-click > Open:

1. **Open Terminal** (see Part 9 above)
2. **Type this and press Enter:**
   ```
   xattr -cr "/Applications/Echo.app"
   ```
3. **Close Terminal**
4. **Try right-click > Open again**
5. **Should work now!**

---

## Quick Checklist (Print This!)

```
SETUP CHECKLIST:
[ ] Open Finder (smiling face icon at bottom)
[ ] Navigate to: Desktop → Project's by Narendra → echo → dist
[ ] Double-click: Echo-1.2.20-arm64.dmg
[ ] Wait 5-10 seconds for it to mount
[ ] Drag Echo.app to Applications folder
[ ] Wait 30 seconds for copy
[ ] Close the DMG window
[ ] Open Applications folder
[ ] Right-click Echo.app → Open (Gatekeeper bypass)
[ ] Wait for app to launch
[ ] Tiny black pill appears at bottom of screen
[ ] Settings → Add Groq API key
[ ] Settings → Add Bedrock API key
[ ] Test transcription (record, speak, check text)
[ ] Test grammar correction (poor grammar → corrected)
[ ] Check logs show "[bedrock] grammar correction applied"
[ ] Done! 🎉
```

---

## Troubleshooting: Common Issues

### Problem: "I can't find Finder"
**Solution:** Look at the bottom of your screen. You'll see a taskbar (dock) with app icons. The smiling face icon on the far left is Finder.

### Problem: "The DMG won't mount"
**Solution:** Double-click the DMG file again. If it still doesn't work, try: Right-click → Open.

### Problem: "I can't find Applications folder"
**Solution:** Open Finder → Press **Cmd + Shift + A**. Applications folder opens.

### Problem: "Echo won't launch"
**Solution:** Make sure you right-click Echo.app (from Applications folder) → Open. Don't try double-clicking the first time.

### Problem: "I don't see the text after recording"
**Solution:** 
1. Check if Groq key was added correctly (copy it again)
2. Check your internet is working
3. Wait 5 seconds after clicking stop
4. Try again

### Problem: "Grammar correction didn't work"
**Solution:**
1. Make sure Grammar Correction toggle is ON
2. Check AWS shows Nova access is "granted"
3. Make sure you're in region us-east-1
4. Check Terminal logs (see Part 9)
5. Try again

---

## Still Stuck?

If you're still having trouble:

1. **Check the detailed docs:**
   - `BUILD_REPORT_v1.2.20.md` - Technical details
   - `STEP8_TESTING_NOTES.md` - Advanced testing guide

2. **Common places files are saved on Mac:**
   - `/Applications/` - Your apps
   - `~/Desktop/` - Your desktop files
   - `~/Library/Logs/echo/` - Echo app logs
   - `~/Downloads/` - Downloaded files

3. **Need help with Mac basics?**
   - Apple has great tutorials: `support.apple.com`
   - Search "how to [something] on Mac" in Google

---

**You've got this! Don't worry if Mac feels different - you'll get used to it.** 

Good luck testing Echo! 🚀
