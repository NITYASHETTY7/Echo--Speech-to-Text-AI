# Transcription Pipeline Analysis

## Complete Execution Path

```
PillController.stopRecording()
  ↓
AudioRecorder.stop()
  ↓ Returns: File?
TranscriptionRepository.transcribe(file, model)
  ↓ Interface: domain/repository/Repositories.kt
TranscriptionRepositoryImpl.transcribe(file, model)
  ↓ Implementation: data/repository/TranscriptionRepositoryImpl.kt
Creates MultipartBody.Part from file
  ↓
EchoApi.transcribe(part, model)
  ↓ Retrofit interface: data/remote/Api.kt
HTTP POST to: http://192.168.0.124:8080/api/transcribe
  ↓ via OkHttp with AuthInterceptor
Backend processes audio
  ↓
Returns: TranscriptionResponse
  ↓
TranscriptionRepositoryImpl parses response
  ↓
Saves to Room database
  ↓
Returns: Result<Transcription>
  ↓
PillController logs result
```

---

## Classes Involved (in order)

### 1. PillController
**Location:** `app/src/main/java/com/echo/dictation/service/overlay/PillController.kt`

**Role:** Orchestrates recording and transcription

**Code:**
```kotlin
private fun stopRecording() {
    state.value = PillState.Idle
    
    scope.launch(Dispatchers.IO) {
        try {
            val recordedFile = audioRecorder.stop()
            if (recordedFile != null && recordedFile.exists() && recordedFile.length() > 0) {
                Log.d(TAG, "Recording stopped: ${recordedFile.absolutePath}, size: ${recordedFile.length()} bytes")
                
                // Transcribe the audio file
                val model = preferences.model
                val result = transcriptionRepository.transcribe(recordedFile, model)
                
                result.fold(
                    onSuccess = { transcription ->
                        Log.d(TAG, "Transcription successful: ${transcription.text}")
                    },
                    onFailure = { error ->
                        Log.e(TAG, "Transcription failed", error)
                    }
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error during recording stop/transcription", e)
        }
    }
}
```

**Current Logging:**
- ✅ File path: `recordedFile.absolutePath`
- ✅ File size: `recordedFile.length()`
- ✅ Success/failure result
- ❌ Model name not logged
- ❌ Transcription text only logged on success

---

### 2. AudioRecorder
**Location:** `app/src/main/java/com/echo/dictation/core/audio/AudioRecorder.kt`

**Role:** Stops MediaRecorder and returns finalized file

**Code:**
```kotlin
@Synchronized
fun stop(): File? {
    val activeRecorder = recorder ?: return null
    val output = file
    var savedFile: File? = null
    
    try {
        activeRecorder.stop()
        activeRecorder.release()
        savedFile = output?.takeIf { it.isFile && it.length() > 0L }
        if (savedFile == null) {
            output?.delete()
            _audioFilePath.value = null
        }
    } catch (e: RuntimeException) {
        // ...
    }
    return savedFile
}
```

**Current Logging:** NONE

---

### 3. TranscriptionRepositoryImpl
**Location:** `app/src/main/java/com/echo/dictation/data/repository/TranscriptionRepositoryImpl.kt`

**Role:** Uploads audio file, receives transcription, saves to database

**Code:**
```kotlin
override suspend fun transcribe(file: File, model: String): Result<Transcription> = runCatching {
    require(file.exists() && file.length() > 0) { "Audio file is empty" }
    
    val part = MultipartBody.Part.createFormData(
        "audio", 
        file.name, 
        file.asRequestBody("audio/mp4".toMediaType())
    )
    
    val response = api.transcribe(
        part, 
        model.toRequestBody("text/plain".toMediaType())
    )
    
    if (!response.success) error(response.error ?: "Transcription failed")
    
    val text = response.text?.trim()?.takeIf { it.isNotEmpty() }
        ?: error(response.error ?: "Transcription returned no text")
    
    val item = Transcription(
        UUID.randomUUID().toString(), 
        text, 
        System.currentTimeMillis(), 
        model, 
        file.absolutePath, 
        auth.currentUser.value?.id ?: "local"
    )
    
    dao.insert(item.entity())
    item
}
```

**Current Logging:** NONE

**Issues:**
- No logging of multipart request creation
- No logging of API call
- No logging of response
- No logging of parsed text

---

### 4. EchoApi (Retrofit Interface)
**Location:** `app/src/main/java/com/echo/dictation/data/remote/Api.kt`

**Endpoint Definition:**
```kotlin
interface EchoApi {
    @Multipart 
    @POST("api/transcribe") 
    suspend fun transcribe(
        @Part audio: MultipartBody.Part, 
        @Part("model") model: RequestBody
    ): TranscriptionResponse
}
```

**Response Data Class:**
```kotlin
data class TranscriptionResponse(
    val success: Boolean, 
    val text: String? = null, 
    val timestamp: String? = null, 
    val error: String? = null
)
```

---

### 5. OkHttp Configuration
**Location:** `app/src/main/java/com/echo/dictation/di/AppModule.kt`

```kotlin
@Provides @Singleton 
fun client(auth: AuthInterceptor): OkHttpClient = 
    OkHttpClient.Builder()
        .addInterceptor(auth)
        .addInterceptor(HttpLoggingInterceptor().apply { 
            level = if (BuildConfig.DEBUG) 
                HttpLoggingInterceptor.Level.BASIC 
            else 
                HttpLoggingInterceptor.Level.NONE 
        })
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)
        .build()
```

**Base URL:**
```kotlin
buildConfigField("String", "API_BASE_URL", "\"http://192.168.0.124:8080/\"")
```

**Full Endpoint:**
```
POST http://192.168.0.124:8080/api/transcribe
```

**Logging Level:** `BASIC` (in debug builds)
- Logs: Request method, URL, response code, response time
- Does NOT log: Request body, response body

---

### 6. AuthInterceptor
**Location:** `app/src/main/java/com/echo/dictation/data/remote/AuthInterceptor.kt`

```kotlin
override fun intercept(chain: Interceptor.Chain): Response {
    val token = tokenStore.token
    val request = if (token.isNullOrBlank()) 
        chain.request() 
    else 
        chain.request().newBuilder()
            .addHeader("Authorization", "Bearer $token")
            .build()
    return chain.proceed(request)
}
```

---

## Analysis: Is Data Mocked or Real?

### ✅ CONFIRMED: Using Real Backend

1. **No Mock Repository Found**
   - Only `TranscriptionRepositoryImpl` is bound in Hilt
   - No fake/mock/demo implementations exist

2. **Real Retrofit API Call**
   ```kotlin
   @POST("api/transcribe")
   suspend fun transcribe(@Part audio: MultipartBody.Part, ...): TranscriptionResponse
   ```

3. **Real Multipart Upload**
   ```kotlin
   MultipartBody.Part.createFormData("audio", file.name, file.asRequestBody("audio/mp4".toMediaType()))
   ```

4. **Real HTTP Request to Backend**
   - Base URL: `http://192.168.0.124:8080/`
   - Endpoint: `POST /api/transcribe`
   - Full URL: `http://192.168.0.124:8080/api/transcribe`

5. **No Hardcoded Responses**
   - No dummy/demo/sample data found
   - No cached responses
   - Response comes directly from `api.transcribe()`

---

## Why Transcription Appears Mocked/Cached

### Likely Root Causes:

#### 1. **Backend Issue - Not Processing Audio**
The backend may be:
- Returning success without actually processing audio
- Using a mock/demo endpoint during development
- Failing to upload/parse multipart data
- Returning cached/hardcoded responses

#### 2. **Network Issue**
- Backend at `192.168.0.124:8080` may not be reachable
- Retrofit may be hitting a fallback/error handler
- HTTP errors being swallowed

#### 3. **Multipart Upload Issue**
- File might not be included in request
- Wrong content type (`audio/mp4` vs actual format)
- File corruption during upload
- Backend not receiving audio data

#### 4. **Logging Level Too Low**
Current `HttpLoggingInterceptor.Level.BASIC` only shows:
```
--> POST /api/transcribe
<-- 200 OK (1234ms)
```

Does NOT show:
- Request body (multipart data)
- Response body (transcription text)

---

## Missing Diagnostics

### Currently NOT Logged:

1. **In PillController:**
   - Model name being used
   - Full error messages

2. **In TranscriptionRepositoryImpl:**
   - File path before upload
   - File size before upload
   - Multipart part creation
   - API request URL
   - HTTP response code
   - Response success flag
   - Response error message
   - Response text content
   - Parsed transcription text

3. **In OkHttp:**
   - Request body (multipart data)
   - Response body (transcription JSON)

---

## Verification Needed

To determine if data is real or mocked:

### Check Backend Logs
Is the backend receiving:
- POST requests to `/api/transcribe`?
- Multipart file data?
- Audio file content?

### Check Network Traffic
Use tools like:
- Logcat with detailed HTTP logging
- Charles Proxy / Wireshark
- Backend request logs

### Add Comprehensive Logging

**In TranscriptionRepositoryImpl:**
```kotlin
Log.d(TAG, "=== TRANSCRIPTION REQUEST ===")
Log.d(TAG, "File: ${file.absolutePath}")
Log.d(TAG, "Size: ${file.length()} bytes")
Log.d(TAG, "Model: $model")
Log.d(TAG, "Creating multipart request...")

val part = MultipartBody.Part.createFormData(...)
Log.d(TAG, "Calling API: POST /api/transcribe")

val response = api.transcribe(part, model.toRequestBody(...))

Log.d(TAG, "=== TRANSCRIPTION RESPONSE ===")
Log.d(TAG, "Success: ${response.success}")
Log.d(TAG, "Text: ${response.text}")
Log.d(TAG, "Error: ${response.error}")
Log.d(TAG, "Timestamp: ${response.timestamp}")
```

**In OkHttp:**
Change logging level to `BODY`:
```kotlin
level = HttpLoggingInterceptor.Level.BODY
```

This will show complete request and response including multipart data.

---

## Conclusion

### The App IS Using Real Backend Transcription

**Evidence:**
- Real Retrofit API interface
- Real multipart file upload
- Real HTTP request to `http://192.168.0.124:8080/api/transcribe`
- No mock repositories or hardcoded responses
- Response parsed from backend JSON

### But Symptoms Suggest Backend Issues

**The problem is NOT in the Android app code.**

The issue is likely:
1. **Backend returning incorrect/cached responses**
2. **Backend not actually processing audio files**
3. **Network connectivity issue preventing real requests**
4. **Insufficient logging hiding the real problem**

### Next Steps Required

1. **Add detailed logging** to TranscriptionRepositoryImpl
2. **Change OkHttp logging to BODY level** to see actual responses
3. **Check backend logs** to verify audio is received
4. **Verify network connectivity** to `192.168.0.124:8080`
5. **Test with curl/Postman** to verify backend works independently
