package app.rehearse

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Hosts Flutter (through audio_service's shared engine, so playback survives
 * the activity) and hands audio shared from other apps to Dart.
 *
 * Shared files arrive as content:// URIs that only live as long as the sending
 * app allows, so each one is copied into the app's cache straight away. Dart
 * then imports it into the library and deletes the copy.
 */
class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null
    private val pending = mutableListOf<Map<String, String>>()
    private val worker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePending" -> {
                    val items = synchronized(pending) {
                        pending.toList().also { pending.clear() }
                    }
                    result.success(items)
                }
                "requestNotificationPermission" -> {
                    requestNotificationPermission()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        channel = methodChannel
        handleIntent(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val uris = extractUris(intent)
        if (uris.isEmpty()) return
        // Consume it so recreating the activity doesn't import the file twice.
        intent.action = null
        intent.data = null

        worker.execute {
            for (uri in uris) {
                copyToCache(uri)?.let { item ->
                    synchronized(pending) { pending.add(item) }
                }
            }
            // Dart pulls the queue with `takePending`; this is only a nudge.
            runOnUiThread { channel?.invokeMethod("incomingChanged", null) }
        }
    }

    @Suppress("DEPRECATION")
    private fun extractUris(intent: Intent): List<Uri> {
        return when (intent.action) {
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            Intent.ACTION_SEND -> {
                val uri: Uri? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
                listOfNotNull(uri)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val uris: ArrayList<Uri>? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                }
                uris?.toList() ?: emptyList()
            }
            else -> emptyList()
        }
    }

    private fun copyToCache(uri: Uri): Map<String, String>? {
        return try {
            val name = displayName(uri) ?: "audio"
            val dir = File(cacheDir, "incoming").apply { mkdirs() }
            val safe = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
            val out = File(dir, "${System.nanoTime()}_$safe")
            val input = contentResolver.openInputStream(uri) ?: return null
            input.use { source -> out.outputStream().use { sink -> source.copyTo(sink) } }
            mapOf("path" to out.absolutePath, "name" to name)
        } catch (e: Exception) {
            null
        }
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme == "content") {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) return cursor.getString(0)
                }
        }
        return uri.lastPathSegment
    }

    companion object {
        private const val CHANNEL = "app.rehearse/platform"
    }
}
