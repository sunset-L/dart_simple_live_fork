package com.kk.simple_live.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FloatingWindowPlacementTest {
    private val portrait = FloatingWindowArea(6, 6, 388, 770)
    private val landscape = FloatingWindowArea(6, 6, 788, 370)

    @Test
    fun rotationPreservesPositionFractions() {
        val original = FloatingWindowPlacement(43, 471, 240, 150)
        val rotated = repositionFloatingWindow(original, portrait, landscape, false)
        assertEquals(FloatingWindowPlacement(143, 171, 240, 150), rotated)
        assertEquals(original, repositionFloatingWindow(rotated, landscape, portrait, false))
    }

    @Test
    fun landscapeBottomRightRemainsVisibleInPortrait() {
        val original = FloatingWindowPlacement(554, 226, 240, 150)
        val rotated = repositionFloatingWindow(original, landscape, portrait, false)
        assertEquals(FloatingWindowPlacement(154, 626, 240, 150), rotated)
    }

    @Test
    fun tallWindowShrinksWithoutChangingAspectRatio() {
        val original = FloatingWindowPlacement(154, 246, 240, 480)
        val rotated = repositionFloatingWindow(original, portrait, landscape, false)
        assertEquals(185, rotated.width)
        assertEquals(370, rotated.height)
        assertTrue(rotated.x >= landscape.left)
        assertEquals(landscape.top, rotated.y)
        assertTrue(rotated.x + rotated.width <= landscape.left + landscape.width)
    }

    @Test
    fun fullWidthWindowFitsNewOrientation() {
        val original = FloatingWindowPlacement(6, 6, 788, 443)
        val rotated = repositionFloatingWindow(original, landscape, portrait, true)
        assertEquals(388, rotated.width)
        assertEquals(portrait.left, rotated.x)
        assertTrue(rotated.height <= portrait.height)
    }

    @Test
    fun offscreenCoordinatesAreClampedBeforeRotation() {
        val original = FloatingWindowPlacement(-100, 1000, 240, 150)
        val rotated = repositionFloatingWindow(original, portrait, landscape, false)
        assertEquals(landscape.left, rotated.x)
        assertEquals(226, rotated.y)
    }
}
