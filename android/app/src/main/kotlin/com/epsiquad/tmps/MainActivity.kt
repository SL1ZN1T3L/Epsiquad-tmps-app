package com.epsiquad.tmps

import android.content.ClipData
import android.content.ContentUris
import android.content.Intent
import android.provider.OpenableColumns
import android.view.WindowManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.widget.Toast
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    // PdfRenderer не потокобезопасен и держит открытой одну страницу за раз,
    // поэтому все вызовы идут через один поток.
    private val pdfWorker = Executors.newSingleThreadExecutor()
    private var pdfDescriptor: ParcelFileDescriptor? = null
    private var pdfRenderer: PdfRenderer? = null

    private val filesWorker = Executors.newSingleThreadExecutor()

    // Файлы из «Поделиться»: копируем в кэш и отдаём в Dart
    private val shareWorker = Executors.newSingleThreadExecutor()
    private var shareChannel: MethodChannel? = null
    private var shareDartReady = false
    private var pendingShare: List<Map<String, Any>> = emptyList()

    private companion object {
        // Значения из NotificationReceiver плагина background_downloader
        const val ACTION_TAP = "com.bbflight.background_downloader.tap"
        const val KEY_TASK = "com.bbflight.background_downloader.task"
        const val KEY_NOTIFICATION_TYPE = "com.bbflight.background_downloader.notificationType"
        const val NOTIFICATION_COMPLETE = 1 // порядковый номер NotificationType.complete
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Приложение было закрыто, и его поднял тап по уведомлению
        if (savedInstanceState == null) handleNotificationTap(intent)
        applyRecentsPrivacy(readHideRecents())
        if (savedInstanceState == null) handleShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleNotificationTap(intent)
        handleShare(intent)
    }

    // ---- Скрытие окна в списке недавних ----

    /** Читает настройку из SharedPreferences Flutter (ключ с префиксом «flutter.»). */
    private fun readHideRecents(): Boolean {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        return prefs.getBoolean("flutter.tmps_hide_recents", true)
    }

    /**
     * Android 13+: убираем только снимок в списке недавних, скриншоты остаются.
     * Ниже: единственный способ - FLAG_SECURE, он запрещает и скриншоты.
     */
    private fun applyRecentsPrivacy(hide: Boolean) {
        if (Build.VERSION.SDK_INT >= 33) {
            setRecentsScreenshotEnabled(!hide)
        } else if (hide) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    // ---- Приём файлов из «Поделиться» ----

    private fun handleShare(intent: Intent?) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) return
        val uris = sharedUris(intent)
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (uris.isEmpty() && text.isNullOrEmpty()) return

        shareWorker.execute {
            val items = ArrayList<Map<String, Any>>()
            try {
                val root = File(cacheDir, "shared")
                cleanOldShares(root)
                val dir = File(root, System.currentTimeMillis().toString())
                dir.mkdirs()
                for (uri in uris) {
                    try {
                        copyShared(uri, dir)?.let { items.add(it) }
                    } catch (e: Exception) {
                        // пропускаем файл, который не удалось прочитать
                    }
                }
                if (uris.isEmpty() && !text.isNullOrEmpty()) {
                    val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
                    val file = File(dir, "text-$stamp.txt")
                    file.writeText(text, Charsets.UTF_8)
                    items.add(mapOf("name" to file.name, "size" to file.length(), "path" to file.absolutePath))
                }
            } catch (e: Exception) {
                // оставим то, что успели скопировать
            }
            runOnUiThread {
                if (items.isEmpty()) {
                    Toast.makeText(this, "Не удалось прочитать присланные файлы", Toast.LENGTH_LONG).show()
                } else if (shareDartReady) {
                    shareChannel?.invokeMethod("shared", items)
                } else {
                    pendingShare = pendingShare + items
                }
            }
        }
    }

    private fun sharedUris(intent: Intent): List<Uri> {
        val result = LinkedHashSet<Uri>()
        val clip = intent.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) {
                clip.getItemAt(i).uri?.let { result.add(it) }
            }
        }
        if (result.isEmpty()) {
            if (intent.action == Intent.ACTION_SEND) {
                streamExtra(intent)?.let { result.add(it) }
            } else {
                streamListExtra(intent)?.let { result.addAll(it) }
            }
        }
        return result.toList()
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun streamListExtra(intent: Intent): List<Uri>? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        }

    private fun displayName(uri: Uri): String {
        var name: String? = null
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) name = c.getString(0)
            }
        } catch (e: Exception) {
            // имя возьмём из пути
        }
        val raw = name ?: uri.lastPathSegment ?: "file"
        val clean = raw.substringAfterLast('/').replace("\\", "_").trim()
        return if (clean.isEmpty()) "file" else clean
    }

    private fun copyShared(uri: Uri, dir: File): Map<String, Any>? {
        val target = File(dir, displayName(uri))
        val input = contentResolver.openInputStream(uri) ?: return null
        input.use { source -> target.outputStream().use { out -> source.copyTo(out) } }
        return mapOf("name" to target.name, "size" to target.length(), "path" to target.absolutePath)
    }

    /** Удаляем копии старше трёх суток, чтобы кэш не рос. */
    private fun cleanOldShares(root: File) {
        val limit = System.currentTimeMillis() - 3L * 24 * 60 * 60 * 1000
        root.listFiles()?.forEach { dir ->
            if (dir.lastModified() < limit) dir.deleteRecursively()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.epsiquad.tmps/pdf")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("args", "path is required", null)
                        } else {
                            runPdf(result) { openPdf(path) }
                        }
                    }
                    "render" -> {
                        val index = call.argument<Int>("index") ?: 0
                        val width = call.argument<Int>("width") ?: 1080
                        runPdf(result) { renderPdfPage(index, width) }
                    }
                    "close" -> runPdf(result) {
                        closePdf()
                        null
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.epsiquad.tmps/files")
            .setMethodCallHandler { call, result ->
                if (call.method != "openDownload") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val name = call.argument<String>("name")
                if (name == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                filesWorker.execute {
                    val found = try {
                        findDownload(name, false)
                    } catch (e: Exception) {
                        null
                    }
                    runOnUiThread {
                        if (found == null) {
                            result.success(false)
                        } else {
                            val opened = try {
                                startViewer(found.first, found.second)
                                true
                            } catch (e: Exception) {
                                false
                            }
                            result.success(opened)
                        }
                    }
                }
            }

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "com.epsiquad.tmps/system")
            .setMethodCallHandler { call, result ->
                if (call.method == "setHideRecents") {
                    applyRecentsPrivacy(call.argument<Boolean>("hide") ?: true)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        val share = MethodChannel(messenger, "com.epsiquad.tmps/share")
        shareChannel = share
        share.setMethodCallHandler { call, result ->
            if (call.method == "takeShared") {
                shareDartReady = true
                val taken = pendingShare
                pendingShare = emptyList()
                result.success(taken)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(messenger, "com.epsiquad.tmps/reminders")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val items = JSONArray()
                        (call.argument<List<*>>("items") ?: emptyList<Any>()).forEach { raw ->
                            val map = raw as? Map<*, *> ?: return@forEach
                            items.put(
                                JSONObject()
                                    .put("code", map["code"]?.toString() ?: "")
                                    .put("title", map["title"]?.toString() ?: "")
                                    .put("expiresAt", (map["expiresAt"] as? Number)?.toLong() ?: 0L)
                            )
                        }
                        val lead = (call.argument<Number>("leadMs"))?.toLong() ?: 0L
                        ExpiryReminders.schedule(applicationContext, items, lead)
                        result.success(null)
                    }
                    "cancelAll" -> {
                        ExpiryReminders.cancelAll(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Тап по уведомлению «Сохранено в Загрузки»: находим файл в «Загрузках»
     * и предлагаем открыть его. Делаем это здесь, а не через Dart-колбэк, чтобы
     * не зависеть от того, успел ли запуститься Flutter. Для Android ниже 10
     * остаётся запасной путь через Dart.
     */
    private fun handleNotificationTap(intent: Intent?) {
        if (intent == null || intent.action != ACTION_TAP) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        if (intent.getIntExtra(KEY_NOTIFICATION_TYPE, -1) != NOTIFICATION_COMPLETE) return
        val taskJson = intent.getStringExtra(KEY_TASK) ?: return
        val filename = try {
            JSONObject(taskJson).optString("filename")
        } catch (e: Exception) {
            ""
        }
        if (filename.isEmpty()) return

        filesWorker.execute {
            // Файл переносится в «Загрузки» сразу после окончания загрузки,
            // поэтому при очень быстром тапе подождём его появления.
            var found: Pair<Uri, String?>? = null
            for (attempt in 0 until 10) {
                found = try {
                    findDownload(filename, true)
                } catch (e: Exception) {
                    null
                }
                if (found != null) break
                Thread.sleep(300)
            }
            runOnUiThread {
                val target = found
                if (target == null) {
                    Toast.makeText(this, "Файл не найден в «Загрузках»", Toast.LENGTH_LONG).show()
                } else {
                    try {
                        startViewer(target.first, target.second)
                    } catch (e: Exception) {
                        Toast.makeText(this, "Не удалось открыть файл", Toast.LENGTH_LONG).show()
                    }
                }
            }
        }
    }

    /**
     * Ищет файл приложения в «Загрузках». При [loose] подходит и имя, которое
     * система изменила из-за повторов («name (1).ext»), берётся самый свежий.
     */
    private fun findDownload(name: String, loose: Boolean): Pair<Uri, String?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        val pattern = Regex("^" + Regex.escape(base) + "( \\(\\d+\\))?" + Regex.escape(ext) + "$")
        val likeBase = base.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")

        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE
        )
        val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ? ESCAPE '\\'"
        val sort = "${MediaStore.MediaColumns.DATE_ADDED} DESC"
        contentResolver.query(collection, projection, selection, arrayOf("$likeBase%"), sort)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
            while (cursor.moveToNext()) {
                val displayName = cursor.getString(nameCol) ?: continue
                if (displayName == name || (loose && pattern.matches(displayName))) {
                    val uri = ContentUris.withAppendedId(collection, cursor.getLong(idCol))
                    return Pair(uri, cursor.getString(mimeCol))
                }
            }
        }
        return null
    }

    /**
     * Обычный ACTION_VIEW: если для типа файла назначено приложение по умолчанию,
     * файл откроется сразу, иначе система сама покажет свой стандартный выбор.
     */
    private fun startViewer(uri: Uri, mime: String?) {
        val view = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, if (mime.isNullOrEmpty()) "*/*" else mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            clipData = ClipData.newRawUri("", uri)
        }
        startActivity(view)
    }

    private fun runPdf(result: MethodChannel.Result, action: () -> Any?) {
        pdfWorker.execute {
            try {
                val value = action()
                runOnUiThread { result.success(value) }
            } catch (e: SecurityException) {
                // PdfRenderer кидает SecurityException для PDF с паролем
                runOnUiThread { result.error("password", "PDF is password protected", null) }
            } catch (e: Exception) {
                runOnUiThread { result.error("pdf", e.message, null) }
            }
        }
    }

    private fun openPdf(path: String): Int {
        closePdf()
        val descriptor = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
        try {
            val renderer = PdfRenderer(descriptor)
            pdfDescriptor = descriptor
            pdfRenderer = renderer
            return renderer.pageCount
        } catch (e: Exception) {
            descriptor.close()
            throw e
        }
    }

    private fun renderPdfPage(index: Int, requestedWidth: Int): ByteArray {
        val renderer = pdfRenderer ?: throw IllegalStateException("PDF is not opened")
        val page = renderer.openPage(index)
        try {
            val width = requestedWidth.coerceIn(200, 3000)
            val height = (width.toLong() * page.height / page.width).toInt().coerceAtLeast(1)
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(Color.WHITE)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
            bitmap.recycle()
            return out.toByteArray()
        } finally {
            page.close()
        }
    }

    private fun closePdf() {
        try {
            pdfRenderer?.close()
        } catch (e: Exception) {
            // уже закрыт
        }
        try {
            pdfDescriptor?.close()
        } catch (e: Exception) {
            // уже закрыт
        }
        pdfRenderer = null
        pdfDescriptor = null
    }

    override fun onDestroy() {
        pdfWorker.execute { closePdf() }
        pdfWorker.shutdown()
        filesWorker.shutdown()
        shareWorker.shutdown()
        super.onDestroy()
    }
}
