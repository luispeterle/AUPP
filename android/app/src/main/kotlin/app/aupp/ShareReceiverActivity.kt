package app.aupp

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import java.io.File

/**
 * Fork: receives a PDF or picture shared from another app (a bill by e-mail,
 * a boleto from the bank) so the app reads its Pix / boleto. Copies the file
 * into the cache and hands it to [MainActivity] in the app's own task: shared
 * from inside another app, Android would otherwise open a second copy of the
 * app on top of that one. No screen of its own.
 */
class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uri = streamOf(intent)
        if (uri == null) {
            finish()
            return
        }
        // The read grant lasts while this activity lives: copy before leaving.
        Thread {
            val path = try {
                copyToCache(uri)
            } catch (e: Exception) {
                null
            }
            runOnUiThread {
                if (path != null) {
                    startActivity(
                        Intent(this, MainActivity::class.java)
                            .setAction(MainActivity.ACTION_SHARED_FILE)
                            .putExtra(MainActivity.EXTRA_PATH, path)
                            .addFlags(
                                Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
                            ),
                    )
                }
                finish()
            }
        }.start()
    }

    private fun streamOf(intent: Intent?): Uri? {
        if (intent?.action != Intent.ACTION_SEND) return null
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
        return uri ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
    }

    /** One file at a time: the last one shared replaces the one before. */
    private fun copyToCache(uri: Uri): String {
        val dir = File(cacheDir, "shared").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val pdf = contentResolver.getType(uri) == "application/pdf"
        val file = File(dir, if (pdf) "compartilhado.pdf" else "compartilhado.img")
        contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "Unreadable shared file" }
            file.outputStream().use { output -> input.copyTo(output) }
        }
        return file.absolutePath
    }
}
