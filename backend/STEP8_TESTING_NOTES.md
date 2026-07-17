# STEP 8 - Manual Testing Procedure for Echo v1.2.20

## Build Artifacts Generated
- **dist/Echo-1.2.20-arm64.dmg** (127M) - Apple Silicon (M1/M2/M3)
- **dist/Echo-1.2.20.dmg** (132M) - Intel x64

Both DMGs are ready for installation and testing.

## Testing Checklist

### 1. First-Time Installation (Gatekeeper Bypass)
**Important:** This build is unsigned/unnotarized (code signing deferred deliberately - tracked separately).

When you double-click Echo.app the first time, Gatekeeper will prevent execution with:
```
"Apple cannot check it for malicious software"
```

**This is expected behavior, not a broken build.**

**To bypass (one-time):**
1. In Applications folder, right-click (Control-click) **Echo.app** → **Open**
2. A dialog appears with an "Open" button this time → click it
3. After this, normal double-click works for subsequent launches

**If you instead see "is damaged":** Run in Terminal:
```bash
xattr -cr "/Applications/Echo.app"
```
Then retry step 1 above.

### 2. App Launch Verification
After successful first launch:
- Tiny black pill should appear at screen bottom (80×23px, 15% opacity)
- Hover over it to see expand button
- Click to expand → should show mic selector, model selector, app launcher

### 3. Groq Transcription (Core Feature - Not Affected by Nova Switch)
- Settings → Enter Groq API key (from console.groq.com)
- Click record button on pill
- Speak into microphone
- ✓ Transcription should appear (this has NOT changed from v1.2.19)

### 4. Grammar Correction with Nova Lite (THE KEY TEST FOR v1.2.20)
**Prerequisites:**
- Valid AWS Bedrock API key (bearer token format)
- Amazon Nova model access enabled in AWS Bedrock console (US East N. Virginia region)
- NO additional "use case details" form required (this was Anthropic's gate - Nova has none)

**Testing:**
1. Settings → Grammar Correction toggle ON
2. Provide Bedrock API key (if not already stored)
3. Record a transcription with intentionally poor grammar:
   ```
   "i goed to the store yesterday for buying grocerys"
   ```
4. After transcription:
   - ✓ **Expected result:** Corrected to proper English
   - ✓ **Terminal log should show:** `[bedrock] grammar correction applied`
   - ✗ **If error:** Check log for specific error:
     - `ResourceNotFoundException` / "use case details" → Wrong model or Anthropic in code
     - `AccessDeniedException` → Nova model access not granted in the configured AWS region
     - `ThrottlingException` → AWS quota limit (not a bug, raise in Service Quotas)

### 5. Verify Nova Model in Use
To confirm Nova Lite (not Claude) is being used:
1. Set `ECHO_LOG_LEVEL=debug` in environment (if available)
2. Look for debug output showing `model_id: amazon.nova-lite-v1:0`
3. Test a correction and verify `[bedrock] grammar correction applied` in logs

### 6. SoX Binary Verification (Already Self-Healed)
- No manual action needed - electron.js (~line 911-928) self-heals on launch
- If you see "recording falls back to browser mode" → regression flag (report it)
- Check logs for: `mode:native` (correct) vs `mode:browser-fallback` (regression)

### 7. Keychain Integration
- First launch may prompt for Keychain password (normal)
- API keys should be stored securely after that

## Sign-Off Criteria for v1.2.20

✅ **Automated** (all completed during build):
- [x] Pulled v1.2.20 from Hemanth-dev
- [x] Verified amazon.nova-lite-v1:0 default model
- [x] Verified 0 anthropic.claude references
- [x] Verified client.converse API in place
- [x] Verified HTML copy updated to "Amazon Nova"
- [x] Re-froze with PyInstaller
- [x] All 3 invariant checks passed (jose+keyring, vendor UI, renderer)
- [x] Built both DMGs (arm64 + x64)

✅ **Manual testing required** (you should do this):
- [ ] First launch Gatekeeper bypass works
- [ ] App pill appears and basic UI works
- [ ] Groq transcription still works (regression check)
- [ ] Bedrock grammar correction with Nova Lite works
- [ ] Corrected text actually improves grammar
- [ ] Terminal log shows `[bedrock] grammar correction applied` (not failed)
- [ ] No regression to browser fallback for recording

## Key Changes vs v1.2.19

| Component | v1.2.19 | v1.2.20 | Why |
|-----------|---------|---------|-----|
| Default Model | `anthropic.claude-3-haiku-*` | `amazon.nova-lite-v1:0` | Removes Anthropic's strict "use case details" gate |
| API Call | `invoke_model()` + Messages API | `converse()` API | Provider-agnostic; swapping models is now a config change, not a code change |
| HTML Copy | "Claude Haiku" | "Amazon Nova" | Accurate product naming |
| Gate Removed | Anthropic's "use case details" form | N/A (Nova has no gate) | Nova is Bedrock's own model - no separate approval process |

## Contact & Debug

If you encounter issues:
1. Check app logs (usually in `~/.echo/logs` or `~/Library/Logs/echo`)
2. Verify AWS region is `us-east-1` (Echo default)
3. Verify Nova Lite access is granted in Bedrock console
4. If Anthropic appears in error: Check code for `anthropic.claude` (should be 0)
5. Report with: app version, error message, AWS region, and last 10 lines of logs

---

**Build completed:** 2026-07-09  
**Version:** 1.2.20  
**Ready for:** Testing & deployment
