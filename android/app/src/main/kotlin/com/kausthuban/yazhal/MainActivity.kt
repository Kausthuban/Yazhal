package com.kausthuban.yazhal

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import android.media.MediaMetadataRetriever
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Storage Access Framework: no broad storage permission or guessed raw paths. */
class MainActivity : AudioServiceActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var picker: MethodChannel.Result? = null
    private val requestCode = 5201

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "yazhal/music_storage").setMethodCallHandler { call, result ->
            if (call.method == "pickTree") {
                if (picker != null) { result.error("busy", "A folder picker is already open", null); return@setMethodCallHandler }
                picker = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                try { startActivityForResult(intent, requestCode) }
                catch (e: Exception) { picker = null; result.error("picker", e.message, null) }
            } else {
                worker.execute {
                    try {
                        val value: Any? = when (call.method) {
                            "scanTree" -> scanTree(Uri.parse(call.argument<String>("tree")!!))
                            "readText" -> {
                                val uri = Uri.parse(call.argument<String>("uri")!!)
                                contentResolver.openInputStream(uri)!!.use { input ->
                                    val buffer = java.io.ByteArrayOutputStream()
                                    val chunk = ByteArray(8192)
                                    while (buffer.size() <= 4 * 1024 * 1024) {
                                        val count = input.read(chunk)
                                        if (count < 0) break
                                        buffer.write(chunk, 0, count)
                                    }
                                    val bytes = buffer.toByteArray()
                                    require(bytes.size <= 4 * 1024 * 1024) { "Playlist exceeds 4 MiB" }
                                    // Reject malformed UTF-8 rather than corrupting paths silently.
                                    Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString()
                                }
                            }
                            "preparePlaybackUri" -> {
                                val uri = Uri.parse(call.argument<String>("uri")!!)
                                contentResolver.openAssetFileDescriptor(uri, "r").use { descriptor ->
                                    requireNotNull(descriptor) { "File is unavailable; select the folder again" }
                                }
                                uri.toString()
                            }
                            "preparePlayback" -> preparePlayback(Uri.parse(call.argument<String>("uri")!!))
                            "publishDownload" -> publishDownload(Uri.parse(call.argument<String>("tree")!!),
                                File(call.argument<String>("path")!!), call.argument<String>("name")!!, call.argument<String>("mime")!!)
                            else -> { runOnUiThread { result.notImplemented() }; return@execute }
                        }
                        runOnUiThread { result.success(value) }
                    } catch (e: Exception) { runOnUiThread { result.error("storage", e.message ?: "Folder access failed; select the folder again", null) } }
                }
            }
        }
    }

    @Deprecated("Activity result API used for FlutterActivity compatibility")
    override fun onActivityResult(request: Int, code: Int, data: Intent?) {
        if (request != requestCode) { super.onActivityResult(request, code, data); return }
        val pending = picker ?: return
        picker = null
        val uri = data?.data
        if (code != RESULT_OK || uri == null) { pending.success(null); return }
        try {
            val flags = data!!.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            contentResolver.takePersistableUriPermission(uri, flags)
            pending.success(uri.toString())
        } catch (e: Exception) { pending.error("permission", e.message, null) }
    }

    private fun scanTree(tree: Uri): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        val seen = mutableSetOf<String>()
        fun visit(id: String, prefix: String, depth: Int) {
            require(depth < 64 && seen.size < 50000) { "Folder tree is too large" }
            if (!seen.add(id)) return
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, id)
            contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    val childId = cursor.getString(0)
                    val name = cursor.getString(1) ?: continue
                    val mime = cursor.getString(2)
                    val relative = if (prefix.isEmpty()) name else "$prefix/$name"
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) { visit(childId, relative, depth + 1); continue }
                    val ext = name.substringAfterLast('.', "").lowercase()
                    if (ext !in setOf("mp3", "m4a", "aac", "flac", "ogg", "opus", "wav", "webm", "3gpp", "m3u", "m3u8")) continue
                    val uri = DocumentsContract.buildDocumentUriUsingTree(tree, childId)
                    val entry = mutableMapOf<String, Any?>("uri" to uri.toString(), "relativePath" to relative, "name" to name)
                    if (ext != "m3u" && ext != "m3u8") {
                        val metadata = MediaMetadataRetriever()
                        try {
                            metadata.setDataSource(this@MainActivity, uri)
                            metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)?.takeIf { it.isNotBlank() }?.let { entry["title"] = it }
                            entry["artist"] = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
                            entry["album"] = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
                            mapOf(
                                "albumArtist" to MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST,
                                "genre" to MediaMetadataRetriever.METADATA_KEY_GENRE,
                                "year" to MediaMetadataRetriever.METADATA_KEY_YEAR,
                                "trackNumber" to MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER,
                                "discNumber" to MediaMetadataRetriever.METADATA_KEY_DISC_NUMBER,
                                "composer" to MediaMetadataRetriever.METADATA_KEY_COMPOSER,
                                "writer" to MediaMetadataRetriever.METADATA_KEY_WRITER,
                                "mimeType" to MediaMetadataRetriever.METADATA_KEY_MIMETYPE,
                                "bitrate" to MediaMetadataRetriever.METADATA_KEY_BITRATE
                            ).forEach { (key, tag) ->
                                metadata.extractMetadata(tag)?.takeIf { it.isNotBlank() }?.let { entry[key] = it }
                            }
                            metadata.embeddedPicture?.takeIf { it.size <= 6 * 1024 * 1024 }?.let { bytes ->
                                val artDir = File(filesDir, "embedded_art").apply { mkdirs() }
                                val key = java.security.MessageDigest.getInstance("SHA-256").digest(uri.toString().toByteArray()).joinToString("") { "%02x".format(it) }
                                val art = File(artDir, "$key.jpg")
                                val partial = File(artDir, "$key.partial")
                                partial.writeBytes(bytes)
                                if (partial.renameTo(art)) entry["artworkPath"] = art.absolutePath
                            }
                            entry["duration"] = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.div(1000)
                        } catch (_: Exception) { /* Decoder can report an unsupported file at playback; use filename metadata. */ }
                        finally { metadata.release() }
                    }
                    result.add(entry)
                    require(result.size <= 20000) { "Folder exceeds 20,000 supported files" }
                }
            } ?: error("Folder is unavailable; select it again")
        }
        visit(DocumentsContract.getTreeDocumentId(tree), "", 0)
        return result
    }

    private fun preparePlayback(uri: Uri): String {
        val hash = MessageDigest.getInstance("SHA-256").digest(uri.toString().toByteArray()).joinToString("") { "%02x".format(it) }
        var name = "audio"
        var size: Long? = null
        var modified: Long? = null
        contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_LAST_MODIFIED), null, null, null)?.use { c ->
            check(c.moveToFirst()) { "File is missing; select its folder again" }
            name = c.getString(0) ?: name
            if (!c.isNull(1)) size = c.getLong(1)
            if (!c.isNull(2)) modified = c.getLong(2)
        } ?: error("File is missing or permission was revoked")
        val dir = File(cacheDir, "local_music").apply { mkdirs() }
        val extension = name.substringAfterLast('.', "audio").replace(Regex("[^A-Za-z0-9]"), "")
        val target = File(dir, "$hash-${size ?: 0}-${modified ?: 0}.$extension")
        // Opening every time checks permission even if a cache entry exists.
        contentResolver.openInputStream(uri)!!.use { input ->
            if (!target.exists() || size == null || modified == null || modified == 0L || size == 0L || target.length() != size) {
                val partial = File(dir, "${target.name}.partial")
                try { partial.outputStream().use { input.copyTo(it) }; check(partial.renameTo(target)) { "Could not finalize playback cache" } }
                finally { partial.delete() }
            }
        }
        // Bounded cache; never delete the currently requested file.
        var total = dir.listFiles()?.sumOf { it.length() } ?: 0L
        dir.listFiles()?.filter { it != target }?.sortedBy { it.lastModified() }?.forEach {
            if (total > 512L * 1024 * 1024) { val length = it.length(); if (it.delete()) total -= length }
        }
        target.setLastModified(System.currentTimeMillis())
        return target.path
    }

    private fun publishDownload(tree: Uri, source: File, name: String, mime: String): String {
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        // createDocument creates a new document; it never overwrites an existing original.
        val document = DocumentsContract.createDocument(contentResolver, parent, mime, name)
            ?: error("Destination is not writable; select another folder")
        try {
            contentResolver.openOutputStream(document, "w")!!.use { output -> source.inputStream().use { it.copyTo(output) } }
            return document.toString()
        } catch (e: Exception) {
            try { DocumentsContract.deleteDocument(contentResolver, document) } catch (_: Exception) {}
            throw e
        }
    }
}
