package dev.ayce.dailydev.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

@Composable
fun DailyDevTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Color(0xFFCE3DF3),
            background = Color(0xFF0E1217),
            surface = Color(0xFF1C1F26),
        ),
        content = content,
    )
}
