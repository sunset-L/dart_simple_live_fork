package com.kk.simple_live.player

import android.content.Context
import android.util.AttributeSet
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView

/** TextureView 与普通 View 同步合成，横竖屏只改变布局，不销毁视频输出。 */
class NativeVideoView(context: Context, attrs: AttributeSet? = null) : PlayerView(context, attrs) {
    private var forcedAspect = 0f
    private var contentAspect = 0f

    init {
        useController = false
        isClickable = false
        isFocusable = false
        setShowBuffering(SHOW_BUFFERING_NEVER)
        setKeepContentOnPlayerReset(true)
    }

    override fun onContentAspectRatioChanged(frame: AspectRatioFrameLayout?, ratio: Float) {
        // 换线/换画质时 Media3 会先发 UNKNOWN 尺寸（比例 0）。
        // 旧纹理仍在显示，不能把容器比例清零，否则旧画面会先被拉满再恢复。
        // 只接受新源有效比例；不是永久锁死旧源比例。
        if (ratio.isFinite() && ratio in 0.2f..4f) contentAspect = ratio
        super.onContentAspectRatioChanged(frame, if (forcedAspect > 0f) forcedAspect else contentAspect)
    }

    fun setScaleMode(mode: Int) {
        forcedAspect = when (mode) {
            3 -> 16f / 9f
            4 -> 4f / 3f
            else -> 0f
        }
        resizeMode = when (mode) {
            1 -> AspectRatioFrameLayout.RESIZE_MODE_FILL
            2 -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
        }
        // UI 同步不读取瞬时 player.videoSize，统一复用最近有效比例。
        // 从固定比例切回自适应时，也立即恢复真实视频比例。
        val frame = findViewById<AspectRatioFrameLayout>(androidx.media3.ui.R.id.exo_content_frame)
        super.onContentAspectRatioChanged(frame, if (forcedAspect > 0f) forcedAspect else contentAspect)
    }
}
