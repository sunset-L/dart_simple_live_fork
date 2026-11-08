package com.kk.simple_live.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.sqrt

class FloatingPinchGestureTest {
    private val initial = PinchBounds(100f, 100f, 240f, 135f)
    private fun pair(x1: Float, y1: Float, x2: Float, y2: Float) =
        listOf(PinchPoint(3, x1, y1), PinchPoint(7, x2, y2))
    private val horizontal = pair(160f, 150f, 280f, 150f)
    private fun gesture(points: List<PinchPoint> = horizontal, bounds: PinchBounds = initial,
                        maxWidth: Float = 600f) =
        FloatingPinchGesture(bounds, points, 120f, maxWidth, 24f, 2f)
    private fun near(expected: Float, actual: Float) = assertEquals(expected, actual, 0.002f)

    @Test fun secondFingerDownDoesNotChangeBounds() {
        assertEquals(initial, gesture().update(horizontal))
    }

    @Test fun onlyOneSmallSlopAndFirstMovementIsNotDiscarded() {
        val g = gesture()
        assertEquals(initial, g.update(pair(160f, 150f, 281f, 150f)))
        near(248f, g.update(pair(160f, 150f, 284f, 150f)).width)
    }

    @Test fun symmetricPinchKeepsFocusAndAspect() {
        val b = gesture().update(pair(130f, 150f, 310f, 150f))
        near(360f, b.width)
        near(202.5f, b.height)
        near(40f, b.x)
        near(75f, b.y)
    }

    @Test fun stationaryFingerKeepsItsContentPoint() {
        val b = gesture().update(pair(160f, 150f, 340f, 150f))
        near(160f, b.x + (160f - initial.x) * b.width / initial.width)
        near(150f, b.y + (150f - initial.y) * b.height / initial.height)
    }

    @Test fun twoFingerTranslationIsOneToOneNotMultipliedByZoomGain() {
        val b = gesture().update(pair(177f, 159f, 297f, 159f))
        near(240f, b.width)
        near(117f, b.x)
        near(109f, b.y)
    }

    @Test fun verticalPinchUsesSameScaleAsHorizontal() {
        val b = gesture(pair(220f, 120f, 220f, 240f))
            .update(pair(220f, 90f, 220f, 270f))
        near(360f, b.width)
    }

    @Test fun diagonalPinchIsContinuousWhenDirectionChanges() {
        val g = gesture()
        g.update(pair(140f, 150f, 300f, 150f))
        val b = g.update(pair(140f, 90f, 300f, 210f))
        near(400f, b.width) // 两指距离从 120 增至 200，不锁住先选中的横轴。
    }

    @Test fun rotatingFingersWithoutChangingDistanceDoesNotResize() {
        val d = 60f / sqrt(2f)
        val b = gesture().update(pair(220f - d, 150f - d, 220f + d, 150f + d))
        near(240f, b.width)
    }

    @Test fun repeatedExpansionAndContractionDoNotDrift() {
        val g = gesture()
        repeat(100) {
            g.update(pair(100f, 150f, 340f, 150f))
            g.update(pair(190f, 150f, 250f, 150f))
            assertEquals(initial, g.update(horizontal))
        }
    }

    @Test fun closeFingersHaveLimitedGainAndNoInitialJump() {
        val points = pair(220f, 150f, 221f, 150f)
        val g = gesture(points)
        assertEquals(initial, g.update(points))
        near(280f, g.update(pair(218f, 150f, 223f, 150f)).width)
    }

    @Test fun zeroSpanStaysFinite() {
        val g = gesture(pair(220f, 150f, 220f, 150f))
        val b = g.update(pair(216f, 150f, 224f, 150f))
        near(320f, b.width)
        assertTrue(b.x.isFinite() && b.y.isFinite())
    }

    @Test fun overshootIsResistedAndReversesImmediately() {
        val g = gesture(maxWidth = 300f)
        val b = g.update(pair(100f, 150f, 340f, 150f))
        assertTrue(b.width > 300f && b.width < 600f)
        val reversed = g.update(pair(105f, 150f, 335f, 150f))
        assertTrue(reversed.width < b.width)
        assertEquals(initial, g.update(horizontal))
    }

    @Test fun undershootIsResistedWithoutHardDeadZone() {
        val g = gesture()
        val b = g.update(pair(210f, 150f, 230f, 150f))
        assertTrue(b.width > 102f && b.width < 120f)
        assertTrue(g.update(pair(207f, 150f, 233f, 150f)).width > b.width)
    }

    @Test fun pointerIndexReorderingDoesNotChangeGeometry() {
        val g = gesture()
        val points = pair(140f, 150f, 300f, 150f)
        val b = g.update(points)
        assertEquals(b, g.update(points.reversed()))
    }

    @Test fun thirdFingerIsIgnoredAndLiftingItDoesNotRebase() {
        val g = gesture()
        val points = pair(140f, 150f, 300f, 150f)
        val b = g.update(points)
        assertEquals(b, g.update(points + PinchPoint(9, 500f, 800f)))
        assertEquals(b, g.update(points))
    }

    @Test fun replacingActiveFingerDoesNotJumpAndCanContinuePinching() {
        val g = gesture()
        val b = g.update(pair(140f, 150f, 300f, 150f))
        val replacement = listOf(PinchPoint(7, 300f, 150f), PinchPoint(9, 200f, 150f))
        assertEquals(b, g.update(replacement))
        assertEquals(b, g.update(replacement))
        val next = g.update(listOf(PinchPoint(7, 310f, 150f), PinchPoint(9, 190f, 150f)))
        near(b.width * 1.2f, next.width)
    }

    @Test fun replacingFingerInResistanceZoneDoesNotApplyResistanceTwice() {
        val g = gesture(maxWidth = 300f)
        val b = g.update(pair(100f, 150f, 340f, 150f))
        val replacement = listOf(PinchPoint(7, 340f, 150f), PinchPoint(9, 200f, 150f))
        assertEquals(b, g.update(replacement))
        val next = g.update(replacement.map { it.copy(x = it.x + 10f) })
        near(b.width, next.width)
        near(b.x + 10f, next.x)
    }

    @Test fun tinyAvailableAreaWinsOverMinimumWidth() {
        val g = gesture(bounds = PinchBounds(0f, 0f, 50f, 200f), maxWidth = 50f)
        val b = g.update(pair(140f, 150f, 300f, 150f))
        assertTrue(b.width > 50f && b.width < 100f)
        near(4f, b.height / b.width)
    }

    @Test fun noMovementAfterOneFingerRemains() {
        val g = gesture()
        val b = g.update(pair(140f, 150f, 300f, 150f))
        assertEquals(b, g.update(listOf(PinchPoint(7, 400f, 400f))))
    }
}
