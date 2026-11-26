package com.kk.simple_live.player

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.*
import android.graphics.drawable.*
import android.widget.ImageButton

/** 直接使用旧 Flutter UI 的 Remix/Material 字形，避免手画图标造成形状及实心状态差异。
 * 原字体作为独立 Android 资源保留，不受 Flutter 图标裁剪影响。 */
object NativeIcons {
    private lateinit var remix: Typeface
    private lateinit var material: Typeface
    private lateinit var resources: android.content.res.Resources
    fun initialize(context: Context) {
        if (::remix.isInitialized) return
        resources = context.resources
        remix = Typeface.createFromAsset(context.assets, "player_icons/Remix.ttf")
        material = Typeface.createFromAsset(context.assets, "player_icons/MaterialIcons.otf")
    }
    fun button(context: Context, icon: String, label: String, action: () -> Unit): ImageButton =
        ImageButton(context).apply {
            initialize(context)
            contentDescription = label
            if (android.os.Build.VERSION.SDK_INT >= 26) tooltipText = label
            scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
            val inset = (12 * resources.displayMetrics.density).toInt()
            setPadding(inset, inset, inset, inset)
            background = RippleDrawable(ColorStateList.valueOf(0x229E9E9E), null,
                GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.WHITE) })
            setImageDrawable(drawable(icon))
            setOnClickListener { action() }
        }
    fun drawable(icon: String, color: Int = Color.WHITE): Drawable {
        val vector = when (icon) {
            "danmaku" -> com.kk.simple_live.R.drawable.player_danmaku_on
            "danmakuOff" -> com.kk.simple_live.R.drawable.player_danmaku_off
            "danmakuSettings" -> com.kk.simple_live.R.drawable.player_danmaku_settings
            else -> null
        }
        if (vector != null) return resources.getDrawable(vector, null).mutate().apply { setTint(color) }
        return object : Drawable() {
        private val glyph = when (icon) {
                "radioChecked" -> Pair(material, 0xe503)
                "radioUnchecked" -> Pair(material, 0xe504)
                "back" -> Pair(material, 0xe092)
                "arrowDown" -> Pair(material, 0xe097)
                "play" -> Pair(material, 0xe4cb)
                "pause" -> Pair(material, 0xe47c)
                "refresh" -> Pair(remix, 0xf064)
                "danmaku" -> Pair(material, 0xe619)
                "danmakuOff" -> Pair(material, 0xe61a)
                "fullscreen" -> Pair(remix, 0xed9c)
                "collapse" -> Pair(remix, 0xed99)
                "lock" -> Pair(material, 0xe3ae)
                "unlock" -> Pair(material, 0xe3b0)
                "more" -> Pair(material, 0xe402)
                "settings" -> Pair(material, 0xe683)
                "rooms" -> Pair(remix, 0xf00d)
                "floating" -> Pair(material, 0xe4c1)
                "follow" -> Pair(remix, 0xee0f)
                "followFilled" -> Pair(remix, 0xee0e)
                "followTab" -> Pair(remix, 0xee0b)
                "history" -> Pair(remix, 0xee17)
                "share" -> Pair(remix, 0xf0fe)
                "info" -> Pair(remix, 0xee59)
                "infoFilled" -> Pair(remix, 0xee58)
                "quality" -> Pair(material, 0xf0e1)
                "line" -> Pair(material, 0xf411)
                "close" -> Pair(remix, 0xeb99)
                "fire" -> Pair(remix, 0xed32)
                "chevron" -> Pair(material, 0xe15f)
                "timer" -> Pair(material, 0xf44a)
                "volume" -> Pair(material, 0xe6c5)
                "brightness" -> Pair(material, 0xe10a)
                "copy" -> Pair(material, 0xe190)
                "link" -> Pair(material, 0xe380)
                "openApp" -> Pair(material, 0xe45c)
                "aspect" -> Pair(material, 0xee94)
                else -> Pair(material, 0xe5d3)
        }
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; typeface = glyph.first; textAlign = Paint.Align.CENTER }
        override fun draw(canvas: Canvas) {
            paint.textSize = minOf(bounds.width(), bounds.height()).toFloat()
            val metrics = paint.fontMetrics
            canvas.drawText(String(Character.toChars(glyph.second)), bounds.exactCenterX(),
                bounds.exactCenterY() - (metrics.ascent + metrics.descent) / 2, paint)
        }
        override fun getIntrinsicWidth() = 24
        override fun getIntrinsicHeight() = 24
        override fun setAlpha(alpha: Int) { paint.alpha = alpha; invalidateSelf() }
        override fun setColorFilter(filter: ColorFilter?) { paint.colorFilter = filter; invalidateSelf() }
        @Deprecated("Deprecated in Android") override fun getOpacity() = PixelFormat.TRANSLUCENT
    }
    }
    fun background(color: Int, radius: Float = 0f) = GradientDrawable().apply { setColor(color); cornerRadius = radius }
}
