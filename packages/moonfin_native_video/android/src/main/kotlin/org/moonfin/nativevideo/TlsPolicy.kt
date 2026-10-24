package org.moonfin.nativevideo

import android.content.Context
import android.util.Base64
import org.json.JSONObject
import java.net.InetSocketAddress
import java.net.Socket
import java.security.KeyFactory
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Principal
import java.security.cert.CertificateException
import java.security.PrivateKey
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.KeyManager
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSession
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManager
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509ExtendedTrustManager
import javax.net.ssl.X509ExtendedKeyManager
import javax.net.ssl.X509TrustManager

/**
 * Owns the process-wide HttpsURLConnection defaults, which media3, the
 * transmuxer, artwork and the download plugin all connect through.
 *
 * Two settings feed it: the pinned server certificates (Foxfin 2.9.2, Trust
 * on First Use: a certificate the system rejects is accepted only when its
 * SHA-256 matches the pin for exactly that host:port), which media3 otherwise
 * can't see because it skips the Dart client, and the client certificates,
 * each presented only to the host it was imported for. The system defaults
 * come back once both are empty.
 */
object TlsPolicy {
    data class ClientCertificate(val host: String, val chainPem: String, val keyPem: String)

    private class Identity(val key: PrivateKey, val chain: Array<X509Certificate>)

    private var pins: Map<String, String> = emptyMap()
    private var certificates: List<ClientCertificate> = emptyList()
    private var identities: Map<String, Identity> = emptyMap()
    private var systemSocketFactory: SSLSocketFactory? = null
    private var systemHostnameVerifier: HostnameVerifier? = null

    private const val PIN_PREFS = "fox_cert_pins"
    private const val PIN_KEY = "pins"

    /** [map] is `host:port` -> SHA-256 fingerprint (`AA:BB:...`). */
    @Synchronized
    fun setPins(map: Map<String, String>): Boolean {
        val normalized = map.entries.associate { (k, v) -> k.lowercase() to normalize(v) }
        if (normalized == pins) return false
        pins = normalized
        install()
        return true
    }

    /** Mirrors the pins for [MtlsInitProvider]; fingerprints aren't secret. */
    fun savePins(context: Context, map: Map<String, String>) {
        context.getSharedPreferences(PIN_PREFS, Context.MODE_PRIVATE).edit()
            .putString(PIN_KEY, JSONObject(map).toString()).apply()
    }

    fun loadPins(context: Context): Map<String, String> = try {
        val raw = context.getSharedPreferences(PIN_PREFS, Context.MODE_PRIVATE)
            .getString(PIN_KEY, null) ?: "{}"
        val json = JSONObject(raw)
        json.keys().asSequence().associateWith { json.getString(it) }
    } catch (_: Exception) {
        emptyMap()
    }

    private fun normalize(fp: String): String =
        fp.filter { it.isLetterOrDigit() }.uppercase().chunked(2).joinToString(":")

    internal fun fingerprint(cert: X509Certificate): String =
        MessageDigest.getInstance("SHA-256").digest(cert.encoded)
            .joinToString(":") { "%02X".format(it) }

    private fun isPinned(host: String?, port: Int, cert: X509Certificate?): Boolean {
        if (host == null || cert == null) return false
        val pin = pins["${host.lowercase()}:$port"] ?: return false
        return pin == fingerprint(cert)
    }

    /** Returns false when [list] is what's already in place. */
    @Synchronized
    fun setClientCertificates(list: List<ClientCertificate>): Boolean {
        if (list == certificates) return false
        certificates = list
        identities = list.mapNotNull { c -> parse(c)?.let { c.host.lowercase() to it } }.toMap()
        install()
        return true
    }

    private fun install() {
        if (systemSocketFactory == null) {
            systemSocketFactory = HttpsURLConnection.getDefaultSSLSocketFactory()
            systemHostnameVerifier = HttpsURLConnection.getDefaultHostnameVerifier()
        }
        if (pins.isEmpty() && identities.isEmpty()) {
            systemSocketFactory?.let { HttpsURLConnection.setDefaultSSLSocketFactory(it) }
            systemHostnameVerifier?.let { HttpsURLConnection.setDefaultHostnameVerifier(it) }
            return
        }
        val keyManagers = if (identities.isEmpty()) null else arrayOf<KeyManager>(HostKeyManager(identities))
        val trustManagers = if (pins.isNotEmpty()) arrayOf<TrustManager>(PinningTrustManager(systemTrustManager())) else null
        val context = SSLContext.getInstance("TLS").apply { init(keyManagers, trustManagers, null) }
        HttpsURLConnection.setDefaultSSLSocketFactory(context.socketFactory)
        val system = systemHostnameVerifier
        if (pins.isNotEmpty() && system != null) {
            // A pinned (e.g. self-signed, IP-addressed) certificate often
            // doesn't name the host; the exact pin stands in for that check.
            HttpsURLConnection.setDefaultHostnameVerifier { host, session ->
                system.verify(host, session) || sessionIsPinned(host, session)
            }
        } else {
            system?.let { HttpsURLConnection.setDefaultHostnameVerifier(it) }
        }
    }

    private fun parse(certificate: ClientCertificate): Identity? = try {
        val chain = CertificateFactory.getInstance("X.509")
            .generateCertificates(certificate.chainPem.byteInputStream())
            .map { it as X509Certificate }
            .toTypedArray()
        val keyDer = Base64.decode(
            certificate.keyPem.lines().filterNot { it.startsWith("-----") }.joinToString(""),
            Base64.DEFAULT,
        )
        val key = KeyFactory.getInstance(chain.first().publicKey.algorithm)
            .generatePrivate(PKCS8EncodedKeySpec(keyDer))
        Identity(key, chain)
    } catch (_: Exception) {
        null
    }

    private class HostKeyManager(
        private val identities: Map<String, Identity>,
    ) : X509ExtendedKeyManager() {
        override fun chooseClientAlias(
            keyType: Array<out String>?,
            issuers: Array<out Principal>?,
            socket: Socket?,
        ): String? = alias(
            (socket as? SSLSocket)?.handshakeSession?.peerHost
                ?: (socket?.remoteSocketAddress as? InetSocketAddress)?.hostString,
        )

        override fun chooseEngineClientAlias(
            keyType: Array<out String>?,
            issuers: Array<out Principal>?,
            engine: SSLEngine?,
        ): String? = alias(engine?.peerHost)

        private fun alias(host: String?): String? =
            host?.lowercase()?.takeIf { it in identities }

        override fun getCertificateChain(alias: String?): Array<X509Certificate>? =
            identities[alias]?.chain

        override fun getPrivateKey(alias: String?): PrivateKey? = identities[alias]?.key

        override fun getClientAliases(keyType: String?, issuers: Array<out Principal>?): Array<String> =
            identities.keys.toTypedArray()

        override fun getServerAliases(keyType: String?, issuers: Array<out Principal>?): Array<String>? = null

        override fun chooseServerAlias(keyType: String?, issuers: Array<out Principal>?, socket: Socket?): String? = null
    }

    private fun sessionIsPinned(host: String?, session: SSLSession?): Boolean = try {
        val leaf = session?.peerCertificates?.firstOrNull() as? X509Certificate
        isPinned(host, session?.peerPort ?: -1, leaf)
    } catch (_: Exception) {
        false
    }

    private fun systemTrustManager(): X509TrustManager {
        val factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        factory.init(null as KeyStore?)
        return factory.trustManagers.filterIsInstance<X509TrustManager>().first()
    }

    /**
     * System validation first; only when that fails, the exact pinned
     * certificate for the connection's host:port is accepted. Everything else
     * is refused, including a changed certificate on a pinned host.
     */
    private class PinningTrustManager(
        private val system: X509TrustManager,
    ) : X509ExtendedTrustManager() {
        private fun check(
            chain: Array<out X509Certificate>?,
            authType: String?,
            host: String?,
            port: Int,
        ) {
            try {
                system.checkServerTrusted(chain, authType)
            } catch (e: CertificateException) {
                if (!isPinned(host, port, chain?.firstOrNull())) throw e
            }
        }

        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: Socket?) {
            val ssl = socket as? SSLSocket
            val host = ssl?.handshakeSession?.peerHost
                ?: (socket?.remoteSocketAddress as? InetSocketAddress)?.hostString
            check(chain, authType, host, socket?.port ?: -1)
        }

        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) =
            check(chain, authType, engine?.peerHost, engine?.peerPort ?: -1)

        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) =
            // No connection context: only the system decision applies.
            system.checkServerTrusted(chain, authType)

        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: Socket?) =
            system.checkClientTrusted(chain, authType)

        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) =
            system.checkClientTrusted(chain, authType)

        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) =
            system.checkClientTrusted(chain, authType)

        override fun getAcceptedIssuers(): Array<X509Certificate> = system.acceptedIssuers
    }
}
