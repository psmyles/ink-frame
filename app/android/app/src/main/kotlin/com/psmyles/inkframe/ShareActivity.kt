package com.psmyles.inkframe

import android.app.Activity
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.MimeTypeMap
import java.io.File
import java.util.UUID

/**
 * Photos shared from another app (Share → Ink Frame). Android starts this in the sharing
 * app's task; it hands the photos to MainActivity in the app's own task (CLEAR_TOP, as
 * OAuthCallbackActivity does), passing on its permission to read them.
 */
class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uris = sharedUris(intent)
        if (uris.isNotEmpty()) {
            val clip = ClipData.newRawUri(null, uris.first())
            uris.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
            try {
                startActivity(Intent(this, MainActivity::class.java).apply {
                    action = SharedInbox.ACTION
                    clipData = clip
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                })
            } catch (e: SecurityException) {
                // The sharing app didn't let us read them, so there's nothing to pass on.
                Log.w("InkFrame", "share: no permission to read the shared photos", e)
            }
        }
        finish()
    }

    @Suppress("DEPRECATION")
    private fun sharedUris(intent: Intent?): List<Uri> = when (intent?.action) {
        Intent.ACTION_SEND -> listOfNotNull(
            if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else intent.getParcelableExtra(Intent.EXTRA_STREAM))
        Intent.ACTION_SEND_MULTIPLE ->
            (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)) ?: emptyList()
        else -> emptyList()
    }
}

/**
 * Where shared photos wait for the Dart side (lib/data/shared_inbox.dart): one folder per
 * share, named so they sort oldest first, each photo named `<nnn>-<original name>`.
 */
object SharedInbox {
    const val ACTION = "com.psmyles.inkframe.SHARED"

    fun dir(context: Context) = File(context.cacheDir, "share-inbox")

    /** The photos in [intent] (from ShareActivity), or none. */
    fun urisIn(intent: Intent?): List<Uri> {
        if (intent?.action != ACTION || intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return emptyList()
        val clip = intent.clipData ?: return emptyList()
        return (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
    }

    /** Copies one share into the inbox: into a folder of its own first, then moved in whole. */
    fun copy(context: Context, uris: List<Uri>) {
        val share = "%013d-%s".format(System.currentTimeMillis(), UUID.randomUUID().toString().take(8))
        val incoming = File(context.cacheDir, "share-incoming/$share").apply { mkdirs() }
        uris.forEachIndexed { i, uri ->
            try {
                val file = File(incoming, "%03d-%s".format(i, fileName(context, uri, i)))
                context.contentResolver.openInputStream(uri)?.use { input -> file.outputStream().use { input.copyTo(it) } }
            } catch (e: Exception) {
                Log.w("InkFrame", "share: couldn't read $uri", e)
            }
        }
        val inbox = dir(context).apply { mkdirs() }
        if (!incoming.renameTo(File(inbox, share))) incoming.deleteRecursively()
    }

    private fun fileName(context: Context, uri: Uri, i: Int): String {
        val shown = try {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        } catch (e: Exception) {
            null
        }
        val name = (shown ?: "photo-${i + 1}").replace(Regex("[/\\\\:]"), "_")
        if (name.contains('.')) return name
        val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(context.contentResolver.getType(uri))
        return if (ext == null) name else "$name.$ext"
    }
}
