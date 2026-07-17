package com.echo.dictation.presentation.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

@Composable fun LoginScreen(onSuccess: () -> Unit, vm: AuthViewModel = hiltViewModel()) {
    var email by remember { mutableStateOf("") }; var otp by remember { mutableStateOf("") }; var sent by remember { mutableStateOf(false) }; var busy by remember { mutableStateOf(false) }; var error by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) { Text("Echo"); OutlinedTextField(email, { email = it }, Modifier.fillMaxWidth(), label = { Text("Email") }); if (sent) OutlinedTextField(otp, { if (it.length <= 6) otp = it }, Modifier.fillMaxWidth(), label = { Text("OTP") }); if (error.isNotEmpty()) Text(error); Button({ busy = true; if (sent) vm.verifyOtp(email, otp, { busy = false; onSuccess() }, { busy = false; error = it }) else vm.sendOtp(email, { busy = false; sent = true }, { busy = false; error = it }) }, enabled = !busy && email.isNotBlank(), modifier = Modifier.fillMaxWidth()) { if (busy) CircularProgressIndicator() else Text(if (sent) "Verify" else "Send OTP") } }
}
