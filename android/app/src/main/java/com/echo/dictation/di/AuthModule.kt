package com.echo.dictation.di

import com.echo.dictation.data.export.ExportServiceImpl
import com.echo.dictation.data.remote.datasource.AuthRemoteDataSource
import com.echo.dictation.data.remote.datasource.UserRemoteDataSource
import com.echo.dictation.data.remote.firebase.FirebaseAuthService
import com.echo.dictation.data.remote.firebase.FirestoreUserService
import com.echo.dictation.data.repository.AuthRepositoryImpl
import com.echo.dictation.data.repository.UserRepositoryImpl
import com.echo.dictation.data.session.SessionManagerImpl
import com.echo.dictation.data.sync.SyncManagerImpl
import com.echo.dictation.domain.export.ExportService
import com.echo.dictation.domain.repository.AuthRepository
import com.echo.dictation.domain.repository.UserRepository
import com.echo.dictation.domain.session.SessionManager
import com.echo.dictation.domain.sync.SyncManager
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class AuthModule {

    @Binds
    @Singleton
    abstract fun bindAuthRemoteDataSource(impl: FirebaseAuthService): AuthRemoteDataSource

    @Binds
    @Singleton
    abstract fun bindUserRemoteDataSource(impl: FirestoreUserService): UserRemoteDataSource

    @Binds
    @Singleton
    abstract fun bindSessionManager(impl: SessionManagerImpl): SessionManager

    @Binds
    @Singleton
    abstract fun bindAuthRepository(impl: AuthRepositoryImpl): AuthRepository

    @Binds
    @Singleton
    abstract fun bindUserRepository(impl: UserRepositoryImpl): UserRepository

    @Binds
    @Singleton
    abstract fun bindSyncManager(impl: SyncManagerImpl): SyncManager

    @Binds
    @Singleton
    abstract fun bindExportService(impl: ExportServiceImpl): ExportService
}
