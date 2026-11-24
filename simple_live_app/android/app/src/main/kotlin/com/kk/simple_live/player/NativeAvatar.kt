package com.kk.simple_live.player

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import android.widget.ImageView
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/** 只加载当前主播头像；缓存有界，离房后不把结果写回旧页面。 */
object NativeAvatar {
    private val cache = object : LruCache<String, Bitmap>(2 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }
    private var placeholder: Bitmap? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    fun clear(view: ImageView) { view.tag = null; view.setImageDrawable(null) }
    fun load(view: ImageView, source: String) {
        val url = if (source.startsWith("//")) "https:$source" else source
        if (view.tag == url) return
        view.tag = url
        if (placeholder == null) placeholder = runCatching {
            view.context.assets.open("flutter_assets/assets/images/logo.png").use { BitmapFactory.decodeStream(it) }
        }.getOrNull()
        view.setImageBitmap(placeholder)
        if (!url.startsWith("https://") && !url.startsWith("http://")) return
        cache.get(url)?.let { view.setImageBitmap(it); return }
        val target = java.lang.ref.WeakReference(view)
        io.execute {
            val bitmap = runCatching {
                val connection = URL(url).openConnection() as HttpURLConnection
                try {
                    connection.connectTimeout = 4000; connection.readTimeout = 4000
                    connection.inputStream.use { stream ->
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(4096)
                        while (output.size() <= 1024 * 1024) {
                            val count = stream.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                        }
                        val bytes = output.toByteArray()
                        if (bytes.size > 1024 * 1024) null else {
                            val info = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, info)
                            if (info.outWidth <= 0 || info.outHeight <= 0) null else {
                                val options = BitmapFactory.Options().apply { inSampleSize = maxOf(info.outWidth, info.outHeight).div(128).coerceAtLeast(1) }
                                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                            }
                        }
                    }
                } finally { connection.disconnect() }
            }.getOrNull()
            if (bitmap != null) { cache.put(url, bitmap); main.post { target.get()?.takeIf { it.tag == url }?.setImageBitmap(bitmap) } }
        }
    }
}
