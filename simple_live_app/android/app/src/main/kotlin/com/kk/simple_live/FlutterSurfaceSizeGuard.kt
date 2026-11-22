package com.kk.simple_live

import android.graphics.SurfaceTexture
import android.util.Log
import android.view.TextureView
import android.view.View
import android.view.ViewTreeObserver
import io.flutter.embedding.android.FlutterImageView
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.renderer.FlutterRenderer

/**
 * 保持整页 TextureView 的缓冲区、Flutter 渲染表面与真实窗口尺寸一致。
 *
 * FlutterTextureView 在 hybrid composition 期间 pause 后会忽略尺寸回调，
 * resume 又只连接 Surface、不补发 surfaceChanged。仅切换 RenderMode.texture
 * 不能覆盖这条路径；旧尺寸可能在返回播放页后继续被新窗口非等比缩放。
 *
 * 不重建 Surface/播放器，也不设置缩放矩阵。原始纹理监听器必须完整转发，
 * 否则会破坏 Flutter 的 Surface 生命周期和首帧通知。
 */
internal class FlutterSurfaceSizeGuard(private val view: FlutterTextureView) {
    private val delegate = requireNotNull(view.surfaceTextureListener)
    private var bufferWidth = 0
    private var bufferHeight = 0
    private var rendererWidth = 0
    private var rendererHeight = 0
    private var renderer: FlutterRenderer? = null
    private var needsSync = true
    private var released = false
    private var observer: ViewTreeObserver? = null

    private val preDrawListener = ViewTreeObserver.OnPreDrawListener {
        synchronize()
        true
    }
    private val attachListener = object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) {
            observeDraws()
            requestSync()
        }

        override fun onViewDetachedFromWindow(v: View) {
            stopObservingDraws()
            needsSync = true
        }
    }
    private val listener = object : TextureView.SurfaceTextureListener {
        override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
            updateBufferSize(surface, width, height)
            delegate.onSurfaceTextureAvailable(surface, width, height)
            requestSync()
        }

        override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
            // 在 Flutter 收到 resize 前就更新默认缓冲区；暂停期间也不能漏掉。
            updateBufferSize(surface, width, height)
            delegate.onSurfaceTextureSizeChanged(surface, width, height)
            requestSync()
        }

        override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {
            delegate.onSurfaceTextureUpdated(surface)
        }

        override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
            bufferWidth = 0
            bufferHeight = 0
            renderer = null
            needsSync = true
            return delegate.onSurfaceTextureDestroyed(surface)
        }
    }

    init {
        view.surfaceTextureListener = listener
        view.addOnAttachStateChangeListener(attachListener)
        if (view.isAttachedToWindow) observeDraws()
    }

    fun requestSync() {
        if (released) return
        needsSync = true
        view.post { if (!released) synchronize() }
    }

    private fun observeDraws() {
        stopObservingDraws()
        observer = view.viewTreeObserver.also { it.addOnPreDrawListener(preDrawListener) }
    }

    private fun stopObservingDraws() {
        observer?.let { if (it.isAlive) it.removeOnPreDrawListener(preDrawListener) }
        observer = null
    }

    private fun updateBufferSize(surface: SurfaceTexture, width: Int, height: Int) {
        if (width <= 0 || height <= 0 || (bufferWidth == width && bufferHeight == height)) return
        surface.setDefaultBufferSize(width, height)
        bufferWidth = width
        bufferHeight = height
    }

    private fun synchronize() {
        if (released || !view.isAttachedToWindow || !view.isAvailable) return
        val width = view.width
        val height = view.height
        if (width <= 0 || height <= 0) return
        val surface = view.surfaceTexture ?: return
        updateBufferSize(surface, width, height)

        // WebView 等原生视图可能暂时把 Flutter 输出切到 ImageReader。
        // 此时不能把 TextureView 的尺寸发给正在使用的另一块渲染表面。
        // 退出 hybrid composition 后，下一次 pre-draw 自动补齐，不依赖再次旋转。
        val flutterView = view.parent as? FlutterView ?: return
        for (index in 0 until flutterView.childCount) {
            val child = flutterView.getChildAt(index)
            if (child is FlutterImageView && child.alpha > 0 && child.visibility == View.VISIBLE) {
                needsSync = true
                return
            }
        }
        val currentRenderer = view.attachedRenderer ?: return
        if (!needsSync && renderer === currentRenderer &&
            rendererWidth == width && rendererHeight == height
        ) return

        currentRenderer.surfaceChanged(width, height)
        renderer = currentRenderer
        rendererWidth = width
        rendererHeight = height
        needsSync = false
        Log.d("FlutterSurfaceSize", "synchronized page surface: ${width}x${height}")
    }

    fun release() {
        released = true
        stopObservingDraws()
        view.removeOnAttachStateChangeListener(attachListener)
        if (view.surfaceTextureListener === listener) view.surfaceTextureListener = delegate
        renderer = null
    }
}
