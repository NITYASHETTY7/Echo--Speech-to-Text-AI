package com.echo.dictation.data.remote.firebase

import android.util.Log
import com.echo.dictation.data.remote.datasource.UserRemoteDataSource
import com.echo.dictation.domain.model.User
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import kotlinx.coroutines.tasks.await
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class FirestoreUserService @Inject constructor() : UserRemoteDataSource {

    private val firestore: FirebaseFirestore? get() = runCatching { FirebaseFirestore.getInstance() }.getOrNull()

    override suspend fun createOrUpdateUser(user: User): Result<Unit> = runCatching {
        val db = firestore ?: throw IllegalStateException("Firestore is not initialized.")
        val docRef = db.collection(COLLECTION_USERS).document(user.uid)

        val docSnapshot = docRef.get().await()
        val data = mutableMapOf<String, Any?>(
            "uid" to user.uid,
            "displayName" to user.displayName,
            "email" to user.email,
            "photoUrl" to user.photoUrl,
            "lastLogin" to user.lastLogin,
        )

        if (!docSnapshot.exists()) {
            data["createdAt"] = user.createdAt
            docRef.set(data).await()
            Log.d(TAG, "Created new user document for ${user.uid}")
        } else {
            docRef.set(data, SetOptions.merge()).await()
            Log.d(TAG, "Updated existing user document for ${user.uid}")
        }
        Unit
    }.onFailure { Log.e(TAG, "createOrUpdateUser failed", it) }

    override suspend fun getUser(uid: String): Result<User?> = runCatching {
        val db = firestore ?: return@runCatching null
        val docSnapshot = db.collection(COLLECTION_USERS).document(uid).get().await()
        if (!docSnapshot.exists()) return@runCatching null

        User(
            uid = docSnapshot.getString("uid") ?: uid,
            displayName = docSnapshot.getString("displayName"),
            email = docSnapshot.getString("email"),
            photoUrl = docSnapshot.getString("photoUrl"),
            createdAt = docSnapshot.getLong("createdAt") ?: System.currentTimeMillis(),
            lastLogin = docSnapshot.getLong("lastLogin") ?: System.currentTimeMillis(),
        )
    }.onFailure { Log.e(TAG, "getUser failed", it) }

    companion object {
        private const val TAG = "FirestoreUserService"
        private const val COLLECTION_USERS = "users"
    }
}
