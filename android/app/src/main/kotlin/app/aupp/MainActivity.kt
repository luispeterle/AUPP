package app.aupp

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingKeepUris: List<String> = emptyList()
    private var widgetChannel: MethodChannel? = null
    private var pendingWidgetAction: String? = null
    private var sharedFileChannel: MethodChannel? = null
    private var pendingSharedFile: String? = null
    private var lockChannel: MethodChannel? = null
    private var askedNotifications = false

    /**
     * Fork: the disguise calculator covers the app again when the screen
     * goes off (the phone was locked) or from "Bloquear agora" on the
     * unlocked notification.
     */
    private val lockReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            UnlockedNotification.cancel(context)
            lockChannel?.invokeMethod("lock", null)
        }
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Fork: with the disguise calculator on (Dart pref "disguiseEnabled"),
        // no snapshot of the app in the recent apps list (the screen behind
        // the calculator would show there).
        val disguise = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .getBoolean("flutter.disguiseEnabled", false)
        if (disguise && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(false)
        }
        ContextCompat.registerReceiver(
            this,
            lockReceiver,
            IntentFilter(Intent.ACTION_SCREEN_OFF).apply {
                addAction(UnlockedNotification.ACTION_LOCK)
            },
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
            .also { widgetChannel = it }
            .setMethodCallHandler { call, result ->
                if (call.method == "getInitialAction") {
                    result.success(pendingWidgetAction)
                    pendingWidgetAction = null
                } else {
                    result.notImplemented()
                }
            }
        handleWidgetIntent(intent)
        // Fork: a PDF / picture shared with the app (ShareReceiverActivity),
        // to read its Pix / boleto.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARED_FILE_CHANNEL)
            .also { sharedFileChannel = it }
            .setMethodCallHandler { call, result ->
                if (call.method == "getInitialFile") {
                    result.success(pendingSharedFile)
                    pendingSharedFile = null
                } else {
                    result.notImplemented()
                }
            }
        handleSharedFileIntent(intent)
        // Fork: real restart (new process), used after "Importar minha config"
        // so the import runs at startup before any screen or sync.
        lockChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCK_CHANNEL)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "unlocked") {
                    // Fork: the disguise calculator was unlocked; "until"
                    // is when it locks again (null while the app is open).
                    askNotifications()
                    UnlockedNotification.show(this, call.argument<Number>("until")?.toLong())
                    result.success(null)
                } else if (call.method == "locked") {
                    UnlockedNotification.cancel(this)
                    result.success(null)
                } else if (call.method == "moveToBack") {
                    // Fork: back on the disguise calculator leaves the app
                    // without finishing it.
                    moveTaskToBack(true)
                    result.success(null)
                } else if (call.method == "syncRunning") {
                    // Fork: keep the process alive while a sync runs.
                    try {
                        SyncForegroundService.update(
                            applicationContext,
                            call.argument<String>("text"),
                            call.argument<Int>("done"),
                            call.argument<Int>("total"),
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        // Android may refuse (app not in the foreground).
                        result.success(false)
                    }
                } else if (call.method == "syncDone") {
                    SyncForegroundService.stop(applicationContext)
                    result.success(null)
                } else if (call.method == "restart") {
                    result.success(null)
                    val launch = packageManager.getLaunchIntentForPackage(packageName)
                    val component = launch?.component
                    mainHandler.postDelayed({
                        if (component != null) {
                            startActivity(Intent.makeRestartActivityTask(component))
                        }
                        Runtime.getRuntime().exit(0)
                    }, 200)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickBackupDirectory" -> pickBackupDirectory(
                        result,
                        call.argument<List<String>>("keepUris"),
                        call.argument<String>("initialFolder"),
                    )
                    "probeWrite" -> runIo(result) {
                        probeWrite(call.argument<String>("uri"))
                    }

                    "writeFile" -> runIo(result) {
                        writeFile(
                            call.argument<String>("uri"),
                            call.argument<String>("fileName"),
                            call.argument<String>("sourcePath"),
                        )
                    }

                    "readFile" -> runIo(result) {
                        readFile(
                            call.argument<String>("uri"),
                            call.argument<String>("fileName"),
                            call.argument<String>("targetPath"),
                        )
                    }

                    "deleteFile" -> runIo(result) {
                        deleteFile(
                            call.argument<String>("uri"),
                            call.argument<String>("fileName"),
                        )
                    }

                    "listFiles" -> runIo(result) {
                        listFiles(call.argument<String>("uri"))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleWidgetIntent(intent)
        handleSharedFileIntent(intent)
    }

    /** Same as [handleWidgetIntent], for a file from ShareReceiverActivity. */
    private fun handleSharedFileIntent(intent: Intent?) {
        if (intent?.action != ACTION_SHARED_FILE) return
        val path = intent.getStringExtra(EXTRA_PATH) ?: return
        // Handled once: a later recreation does not open it again.
        intent.action = null
        // Kept until Flutter takes it: pushed now if the app is past the
        // lock, otherwise read with getInitialFile once it is.
        pendingSharedFile = path
        sharedFileChannel?.invokeMethod(
            "openSharedFile",
            path,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (pendingSharedFile == path) pendingSharedFile = null
                }

                override fun error(code: String, message: String?, details: Any?) {}

                override fun notImplemented() {}
            },
        )
    }

    /**
     * Forwards home screen widget quick-add taps to Flutter. While the
     * engine runs, the action is pushed immediately; otherwise (cold start)
     * it is stashed for [getInitialAction].
     */
    private fun handleWidgetIntent(intent: Intent?) {
        val action = when (intent?.action) {
            "app.aupp.ADD_EXPENSE" -> "add_expense"
            "app.aupp.ADD_INCOME" -> "add_income"
            else -> return
        }
        try {
            widgetChannel?.invokeMethod("openAddFlow", action)
                ?: run { pendingWidgetAction = action }
        } catch (e: Exception) {
            pendingWidgetAction = action
        }
    }

    /**
     * Runs a blocking storage operation off the main thread and delivers the
     * result back on the platform thread.
     */
    private fun runIo(result: MethodChannel.Result, block: () -> Any?) {
        ioExecutor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("backup_directory_error", e.message, null)
                }
            }
        }
    }

    /**
     * Opens the system Storage Access Framework picker (ACTION_OPEN_DOCUMENT_TREE)
     * so the user can choose the folder backups are stored in. The result is
     * delivered to [onActivityResult].
     */
    private fun pickBackupDirectory(
        result: MethodChannel.Result,
        keepUris: List<String>?,
        initialFolder: String?,
    ) {
        if (pendingResult != null) {
            result.error("picker_active", "A directory picker is already active", null)
            return
        }
        pendingResult = result
        pendingKeepUris = keepUris ?: emptyList()
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            if (initialFolder != null) {
                putExtra(
                    DocumentsContract.EXTRA_INITIAL_URI,
                    DocumentsContract.buildDocumentUri(
                        "com.android.externalstorage.documents",
                        "primary:$initialFolder",
                    ),
                )
            }
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_PICK_BACKUP_DIRECTORY)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_BACKUP_DIRECTORY) {
            return
        }
        val result = pendingResult ?: return
        pendingResult = null
        val treeUri = data?.data
        if (resultCode != Activity.RESULT_OK || treeUri == null) {
            // The user dismissed the picker.
            result.success(null)
            return
        }
        persistDirectoryGrant(treeUri)
        result.success(
            mapOf(
                "path" to resolveTreePath(treeUri),
                "uri" to treeUri.toString(),
            )
        )
    }

    /** Once per run: the unlocked notification needs the permission. */
    private fun askNotifications() {
        if (askedNotifications || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        askedNotifications = true
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7001)
        }
    }

    override fun onDestroy() {
        // The app starts locked again: the notification would be wrong.
        unregisterReceiver(lockReceiver)
        UnlockedNotification.cancel(this)
        pendingResult?.error("picker_cancelled", "The picker was dismissed", null)
        pendingResult = null
        ioExecutor.shutdown()
        super.onDestroy()
    }

    /**
     * Keeps the granted access to the picked folder across reboots and drops
     * the grants of previously picked folders, so the app never runs into the
     * system limit of persisted URI permissions.
     */
    private fun persistDirectoryGrant(treeUri: Uri) {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        try {
            contentResolver.takePersistableUriPermission(treeUri, flags)
        } catch (e: SecurityException) {
            // Some providers do not offer persistable grants.
        }
        for (permission in contentResolver.persistedUriPermissions) {
            val uri = permission.uri
            if (uri != treeUri &&
                uri.toString() !in pendingKeepUris &&
                uri.path?.startsWith("/tree/") == true
            ) {
                try {
                    contentResolver.releasePersistableUriPermission(uri, flags)
                } catch (e: SecurityException) {
                    // The grant is already gone; nothing to release.
                }
            }
        }
    }

    private fun parseTreeUri(uriString: String?): Uri {
        if (uriString.isNullOrEmpty()) {
            throw IllegalArgumentException("Missing backup folder uri")
        }
        return Uri.parse(uriString)
    }

    private fun rootDocumentUri(treeUri: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(
            treeUri, DocumentsContract.getTreeDocumentId(treeUri)
        )

    private fun childrenUri(treeUri: Uri): Uri =
        DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri, DocumentsContract.getTreeDocumentId(treeUri)
        )

    private data class ChildDocument(val documentId: String, val name: String)

    private fun queryChildren(treeUri: Uri): List<ChildDocument> {
        val children = mutableListOf<ChildDocument>()
        contentResolver.query(
            childrenUri(treeUri),
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            ),
            null, null, null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                children.add(ChildDocument(cursor.getString(0), cursor.getString(1)))
            }
        }
        return children
    }

    private fun findChild(treeUri: Uri, fileName: String): ChildDocument? =
        queryChildren(treeUri).firstOrNull { it.name == fileName }

    /**
     * Verifies through the Storage Access Framework that the app can create
     * and delete documents in the picked folder. Raw file-path probes are not
     * usable here: scoped storage blocks direct writes outside app-specific
     * directories even when a persistable URI grant exists.
     */
    private fun probeWrite(uriString: String?): Boolean {
        val treeUri = parseTreeUri(uriString)
        val probeUri = DocumentsContract.createDocument(
            contentResolver, rootDocumentUri(treeUri),
            "application/octet-stream", PROBE_FILE_NAME
        ) ?: return false
        return try {
            DocumentsContract.deleteDocument(contentResolver, probeUri)
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Copies the staged backup file [sourcePath] into the picked folder as
     * [fileName]. An existing document with the same name is overwritten in
     * place, so fixed-name backups do not accumulate " (1)" copies.
     */
    private fun writeFile(uriString: String?, fileName: String?, sourcePath: String?): Boolean {
        val treeUri = parseTreeUri(uriString)
        if (fileName.isNullOrEmpty() || sourcePath.isNullOrEmpty()) {
            throw IllegalArgumentException("Missing file name or source path")
        }
        val existing = findChild(treeUri, fileName)
        val targetUri = if (existing != null) {
            DocumentsContract.buildDocumentUriUsingTree(treeUri, existing.documentId)
        } else {
            val mime = if (fileName.endsWith(".json", ignoreCase = true)) {
                "application/json"
            } else {
                "application/octet-stream"
            }
            DocumentsContract.createDocument(
                contentResolver, rootDocumentUri(treeUri), mime, fileName
            )
                ?: throw IllegalStateException("Could not create $fileName in the backup folder")
        }
        FileInputStream(File(sourcePath)).use { input ->
            contentResolver.openOutputStream(targetUri, "wt").use { output ->
                if (output == null) {
                    throw IllegalStateException("The backup folder is not writable")
                }
                input.copyTo(output)
            }
        }
        return true
    }

    /**
     * Copies the document [fileName] of the picked folder to [targetPath].
     * Returns false when there is no such document.
     */
    private fun readFile(uriString: String?, fileName: String?, targetPath: String?): Boolean {
        val treeUri = parseTreeUri(uriString)
        if (fileName.isNullOrEmpty() || targetPath.isNullOrEmpty()) {
            throw IllegalArgumentException("Missing file name or target path")
        }
        val existing = findChild(treeUri, fileName) ?: return false
        val source = DocumentsContract.buildDocumentUriUsingTree(treeUri, existing.documentId)
        contentResolver.openInputStream(source).use { input ->
            if (input == null) {
                throw IllegalStateException("The sync folder is not readable")
            }
            File(targetPath).outputStream().use { output -> input.copyTo(output) }
        }
        return true
    }

    private fun deleteFile(uriString: String?, fileName: String?): Boolean {
        val treeUri = parseTreeUri(uriString)
        if (fileName.isNullOrEmpty()) {
            return false
        }
        val existing = findChild(treeUri, fileName) ?: return false
        return DocumentsContract.deleteDocument(
            contentResolver,
            DocumentsContract.buildDocumentUriUsingTree(treeUri, existing.documentId)
        )
    }

    /**
     * Lists the documents in the picked folder with their display names and
     * last-modified timestamps, used for retention cleanup and for detecting
     * the latest backup.
     */
    private fun listFiles(uriString: String?): List<Map<String, Any?>> {
        val treeUri = parseTreeUri(uriString)
        val files = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            childrenUri(treeUri),
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            ),
            null, null, null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                files.add(
                    mapOf(
                        "name" to cursor.getString(1),
                        "lastModifiedMs" to if (cursor.isNull(2)) null else cursor.getLong(2),
                    )
                )
            }
        }
        return files
    }

    /**
     * Maps a SAF tree URI to the raw filesystem path it points to, e.g.
     * content://com.android.externalstorage.documents/tree/primary:Backups
     * becomes /storage/emulated/0/Backups. Returns null when the provider is
     * not backed by the local filesystem (e.g. a cloud provider). The path is
     * used for display only; all writes go through the content resolver.
     */
    private fun resolveTreePath(treeUri: Uri): String? {
        val docId = try {
            DocumentsContract.getTreeDocumentId(treeUri)
        } catch (e: IllegalArgumentException) {
            return null
        }
        val separator = docId.indexOf(':')
        return if (separator < 0) {
            // Whole-volume pick, e.g. the storage root.
            volumeRoot(docId)
        } else {
            val volumeRoot = volumeRoot(docId.substring(0, separator))
            val relativePath = docId.substring(separator + 1)
            if (relativePath.isEmpty()) volumeRoot else "$volumeRoot/$relativePath"
        }
    }

    private fun volumeRoot(volumeId: String): String {
        @Suppress("DEPRECATION")
        val externalStorage = Environment.getExternalStorageDirectory().absolutePath
        return if (volumeId.equals("primary", ignoreCase = true)) {
            externalStorage
        } else {
            "/storage/$volumeId"
        }
    }

    companion object {
        private const val CHANNEL = "aupp/backup_directory"
        private const val WIDGET_CHANNEL = "aupp/widget_action"
        private const val APP_CHANNEL = "aupp/app"
        private const val LOCK_CHANNEL = "aupp/lock"
        private const val SHARED_FILE_CHANNEL = "aupp/shared_file"
        const val ACTION_SHARED_FILE = "app.aupp.SHARED_FILE"
        const val EXTRA_PATH = "path"
        private const val REQUEST_PICK_BACKUP_DIRECTORY = 7941
        private const val PROBE_FILE_NAME = ".aupp_probe"
    }
}
