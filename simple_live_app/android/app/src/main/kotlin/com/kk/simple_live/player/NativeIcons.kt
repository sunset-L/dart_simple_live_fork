package com.kk.simple_live.player

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.widget.ImageButton
import androidx.core.graphics.PathParser

/** 本地矢量图标，不依赖字体、网络图片或 Unicode 字符。 */
object NativeIcons {
    fun button(context: Context, icon: String, label: String, action: () -> Unit): ImageButton =
        ImageButton(context).apply {
            contentDescription = label
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) tooltipText = label
            scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
            val inset = (11 * resources.displayMetrics.density).toInt()
            setPadding(inset, inset, inset, inset)
            background = RippleDrawable(ColorStateList.valueOf(0x44FFFFFF), null,
                GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.WHITE) })
            setImageDrawable(drawable(icon))
            setOnClickListener { action() }
        }

    fun drawable(icon: String, color: Int = Color.WHITE): Drawable = object : Drawable() {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color; style = Paint.Style.STROKE; strokeWidth = 1.8f
            strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
        }
        override fun draw(canvas: Canvas) {
            val paths = when (icon) {
                "back" -> "M15 5 L8 12 L15 19"
                "play" -> "M8 5 L19 12 L8 19 Z"
                "pause" -> "M8 5 L8 19 M16 5 L16 19"
                "refresh" -> "M20 7 L20 2 M20 7 L15 7 M20 7 C17 1 7 2 4 8 C0 17 12 24 19 17"
                "danmaku" -> "M4 4 L20 4 L20 17 L13 17 L7 21 L7 17 L4 17 Z M7 8 L17 8 M7 12 L13 12"
                "danmakuOff" -> "M4 4 L20 4 L20 17 L13 17 L7 21 L7 17 L4 17 Z M3 2 L22 22"
                "fullscreen" -> "M9 4 L4 4 L4 9 M15 4 L20 4 L20 9 M4 15 L4 20 L9 20 M20 15 L20 20 L15 20"
                "collapse" -> "M4 9 L9 9 L9 4 M20 9 L15 9 L15 4 M4 15 L9 15 L9 20 M20 15 L15 15 L15 20"
                "lock" -> "M7 10 L7 7 C7 0 17 0 17 7 L17 10 M5 10 L19 10 L19 21 L5 21 Z M12 14 L12 17"
                "unlock" -> "M7 10 L7 7 C7 0 17 0 17 7 M5 10 L19 10 L19 21 L5 21 Z M12 14 L12 17"
                "more" -> "M5 11 L5 13 M12 11 L12 13 M19 11 L19 13"
                "settings" -> "M4 7 L20 7 M4 17 L20 17 M8 4 L8 10 M16 14 L16 20"
                "rooms" -> "M4 5 L9 5 L9 10 L4 10 Z M15 5 L20 5 L20 10 L15 10 Z M4 16 L9 16 L9 21 L4 21 Z M15 16 L20 16 L20 21 L15 21 Z"
                "floating" -> "M3 4 L21 4 L21 20 L3 20 Z M12 12 L19 12 L19 18 L12 18 Z"
                "follow" -> "M12 20 C-5 9 5 -1 12 7 C19 -1 29 9 12 20 Z"
                "share" -> "M8 8 L12 4 L16 8 M12 4 L12 15 M5 12 L5 21 L19 21 L19 12"
                "info" -> "M12 3 C0 3 0 21 12 21 C24 21 24 3 12 3 Z M12 10 L12 17 M12 7 L12 7.2"
                "quality" -> "M3 5 L21 5 L21 19 L3 19 Z M6 9 L6 15 M10 9 L10 15 M6 12 L10 12 M14 9 L14 15 L17 15 C21 15 21 9 17 9 Z"
                "line" -> "M4 5 L20 5 L20 19 L4 19 Z M8 9 L16 9 L13 6 M16 15 L8 15 L11 18"
                "close" -> "M5 5 L19 19 M19 5 L5 19"
                else -> "M4 5 L20 5 L20 19 L4 19 Z M7 9 L17 9 M7 13 L14 13"
            }
            canvas.save()
            canvas.translate(bounds.left.toFloat(), bounds.top.toFloat())
            canvas.scale(bounds.width() / 24f, bounds.height() / 24f)
            PathParser.createPathFromPathData(paths)?.let { canvas.drawPath(it, paint) }
            canvas.restore()
        }
        override fun getIntrinsicWidth() = 24
        override fun getIntrinsicHeight() = 24
        override fun setAlpha(alpha: Int) { paint.alpha = alpha; invalidateSelf() }
        override fun setColorFilter(filter: android.graphics.ColorFilter?) { paint.colorFilter = filter }
        @Deprecated("Deprecated in Android") override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
    }

    fun background(color: Int, radius: Float = 0f) = GradientDrawable().apply {
        setColor(color); cornerRadius = radius
    }
}
