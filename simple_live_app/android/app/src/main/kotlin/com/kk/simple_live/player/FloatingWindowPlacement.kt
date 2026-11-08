package com.kk.simple_live.player

import kotlin.math.min
import kotlin.math.roundToInt

internal data class FloatingWindowArea(
    val left: Int,
    val top: Int,
    val width: Int,
    val height: Int,
)

internal data class FloatingWindowPlacement(
    val x: Int,
    val y: Int,
    val width: Int,
    val height: Int,
)

internal fun repositionFloatingWindow(
    previous: FloatingWindowPlacement,
    previousArea: FloatingWindowArea,
    area: FloatingWindowArea,
    fullWidth: Boolean,
): FloatingWindowPlacement {
    val horizontalRange = previousArea.width - previous.width
    val verticalRange = previousArea.height - previous.height
    val horizontalFraction = if (horizontalRange > 0) {
        ((previous.x - previousArea.left).toDouble() / horizontalRange).coerceIn(0.0, 1.0)
    } else {
        0.5
    }
    val verticalFraction = if (verticalRange > 0) {
        ((previous.y - previousArea.top).toDouble() / verticalRange).coerceIn(0.0, 1.0)
    } else {
        0.5
    }
    val desiredWidth = if (fullWidth) area.width else previous.width
    val desiredHeight = desiredWidth.toDouble() * previous.height / previous.width
    val fit = min(1.0, min(area.width.toDouble() / desiredWidth, area.height / desiredHeight))
    val width = (desiredWidth * fit).roundToInt().coerceIn(1, area.width)
    val height = (desiredHeight * fit).roundToInt().coerceIn(1, area.height)
    return FloatingWindowPlacement(
        x = area.left + ((area.width - width) * horizontalFraction).roundToInt(),
        y = area.top + ((area.height - height) * verticalFraction).roundToInt(),
        width = width,
        height = height,
    )
}
