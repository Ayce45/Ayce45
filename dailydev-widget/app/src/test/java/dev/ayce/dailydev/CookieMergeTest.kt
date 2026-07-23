package dev.ayce.dailydev

import dev.ayce.dailydev.data.api.DailyDevApi
import org.junit.Assert.assertEquals
import org.junit.Test

class CookieMergeTest {

    @Test
    fun `fusionne les Set-Cookie dans la chaine existante`() {
        val merged = DailyDevApi.mergeCookies(
            "da2=old; da3=refresh; other=x",
            listOf(
                "da2=new; Path=/; Domain=.daily.dev; HttpOnly; Secure; SameSite=Lax",
                "da4=extra; Max-Age=31536000",
            ),
        )
        assertEquals("da2=new; da3=refresh; other=x; da4=extra", merged)
    }

    @Test
    fun `ignore les en-tetes malformes`() {
        val merged = DailyDevApi.mergeCookies("da2=a", listOf("garbage", "=novalue"))
        assertEquals("da2=a", merged)
    }
}
