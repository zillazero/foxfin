// Foxfin: MethodChannel bridge to the FOX SSO client (site.pk187.sso).
// GPL-2.0-or-later, see NOTICE.
package org.moonfin.androidtv

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import site.pk187.sso.FavItem
import site.pk187.sso.Favorites
import site.pk187.sso.FoxApiException
import site.pk187.sso.FoxAuthClient
import site.pk187.sso.FoxSessionExpired
import site.pk187.sso.FoxSso
import site.pk187.sso.FoxSsoClient
import site.pk187.sso.FoxSyncClient
import site.pk187.sso.Links
import site.pk187.sso.ProgressItem
import site.pk187.sso.ProgressList
import site.pk187.sso.ProgressResult
import site.pk187.sso.SsoResult
import site.pk187.sso.SyncConflict
import site.pk187.sso.SyncSettings

class FoxSsoChannel(context: Context) : MethodChannel.MethodCallHandler {
    companion object { const val CHANNEL = "fox_sso" }

    private val app = context.applicationContext
    private val auth by lazy { FoxAuthClient(app) }
    private val sync by lazy { FoxSyncClient(auth) }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            val out: Result<Any?> = runCatching { handle(call) }
            withContext(Dispatchers.Main) {
                out.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { e ->
                        when (e) {
                            is FoxSessionExpired -> result.error("session_expired", e.message, null)
                            is SyncConflict -> result.error("conflict", e.message, e.server?.toString())
                            is FoxApiException -> result.error(
                                if (e.isRateLimited) "rate_limited" else e.code, e.message, e.status,
                            )
                            else -> result.error("error", e.message ?: e.toString(), null)
                        }
                    },
                )
            }
        }
    }

    // Foxfin 2.8.5: "Im FOX-Player öffnen". Startet FOX-Player (foxplayer://live),
    // sonst die FOX-Store-Seite des Pakets, sonst den Browser.
    private fun openFoxPlayer(): String {
        val pm = app.packageManager
        val flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
        val player = "site.pk187.foxplayer"
        runCatching {
            val i = android.content.Intent(android.content.Intent.ACTION_VIEW,
                android.net.Uri.parse("foxplayer://live")).setPackage(player).addFlags(flags)
            if (i.resolveActivity(pm) != null) { app.startActivity(i); return "player" }
        }
        runCatching {
            pm.getLaunchIntentForPackage(player)?.let { app.startActivity(it.addFlags(flags)); return "player" }
        }
        val page = android.net.Uri.parse("https://apps.pk187.site/app/foxplayer")
        runCatching {
            val i = android.content.Intent(android.content.Intent.ACTION_VIEW, page)
                .setPackage(FoxSso.STORE_PACKAGE).addFlags(flags)
            if (i.resolveActivity(pm) != null) { app.startActivity(i); return "store" }
        }
        return runCatching {
            app.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, page).addFlags(flags)); "web"
        }.getOrDefault("none")
    }

    private suspend fun handle(call: MethodCall): Any? = when (call.method) {
        "openFoxPlayer" -> withContext(Dispatchers.Main) { openFoxPlayer() }
        "status" -> mapOf(
            "storeAvailable" to FoxSsoClient.isStoreAvailable(app),
            "storeLoggedIn" to runCatching { FoxSsoClient.isStoreLoggedIn(app) }.getOrDefault(false),
            "loggedIn" to auth.isLoggedIn,
            "serverId" to FoxSso.JELLYFIN_SERVER_ID,
        )
        "signInViaStore" -> when (val r = auth.signInViaStore()) {
            is SsoResult.Success -> "ok"
            SsoResult.StoreNotLoggedIn -> "store_not_logged_in"
            SsoResult.StoreUnavailable -> "store_unavailable"
            is SsoResult.Error -> "error:${r.code}:${r.message}"
            else -> "error"
        }
        "signInPassword" -> {
            auth.signIn(call.argument<String>("username").orEmpty(), call.argument<String>("password").orEmpty())
            "ok"
        }
        "signOut" -> { auth.signOut(all = call.argument<Boolean>("all") == true); null }
        "getSettings" -> json.encodeToString(SyncSettings.serializer(), sync.getSettings())
        "putSettings" -> json.encodeToString(
            SyncSettings.serializer(),
            sync.putSettings(
                theme = call.argument("theme"),
                baseUpdatedAt = call.argument("baseUpdatedAt"),
            ),
        )
        "getFavorites" -> json.encodeToString(Favorites.serializer(), sync.getFavorites())
        "addFavorites" -> json.encodeToString(
            Favorites.serializer(), sync.addFavorites(call.argument<List<String>>("ids") ?: emptyList()),
        )
        "removeFavorites" -> json.encodeToString(
            Favorites.serializer(), sync.removeFavorites(call.argument<List<String>>("ids") ?: emptyList()),
        )
        "getProgress" -> json.encodeToString(ProgressList.serializer(), sync.getProgress(call.argument("since")))
        "putProgress" -> {
            val raw = call.argument<String>("items") ?: "[]"
            val items = json.decodeFromString(ListSerializer(ProgressItem.serializer()), raw)
            json.encodeToString(ProgressResult.serializer(), sync.putProgress(items))
        }
        "getLinks" -> json.encodeToString(Links.serializer(), sync.getLinks())
        "putLink" -> sync.putLink(
            service = call.argument<String>("service") ?: "",
            connected = call.argument<Boolean>("connected") == true,
            accountName = call.argument("accountName"),
        ).toString()
        else -> throw UnsupportedOperationException(call.method)
    }
}
