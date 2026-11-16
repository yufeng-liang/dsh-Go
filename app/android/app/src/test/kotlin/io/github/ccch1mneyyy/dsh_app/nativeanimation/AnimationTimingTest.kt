package io.github.ccch1mneyyy.dsh_app.nativeanimation

import org.junit.Assert.*
import org.junit.Test

class AnimationTimingTest {
    @Test fun sourceDurationsDoNotAccumulateRenderingTime() {
        val sequence = SpriteSequence(listOf(0, 2, 5), listOf(50, 100, 50), true)
        assertEquals(0, sequence.frame(49))
        assertEquals(1, sequence.frame(50))
        assertEquals(1, sequence.frame(149))
        assertEquals(2, sequence.frame(150))
        assertEquals(0, sequence.frame(200))
        // A delayed draw skips to the source clock, rather than adding its latency to each frame.
        assertEquals(1, sequence.frame(10_076))
        assertEquals(74L, sequence.remaining(10_076))
    }

    @Test fun unchangedCellsDoNotRequireMoreSurfaceBuffers() {
        val sequence = SpriteSequence(listOf(0, 0, 1), listOf(50, 50, 50), true)
        assertEquals(100L, sequence.nextVisualDelay(0))
        assertEquals(40L, sequence.nextVisualDelay(60))
        assertEquals(25L, sequence.nextVisualDelay(125))
        assertNull(SpriteSequence(listOf(3, 3), listOf(50, 50), true).nextVisualDelay(10))
    }

    @Test fun oneShotHoldsLastCellAndEndsExactlyAtSourceDuration() {
        val sequence = SpriteSequence(listOf(0, 1, 1), listOf(50, 50, 50), false)
        assertFalse(sequence.ended(149))
        assertTrue(sequence.ended(150))
        assertEquals(2, sequence.frame(1000))
        assertEquals(90L, sequence.nextVisualDelay(60))
        assertNull(sequence.nextVisualDelay(150))
    }

    @Test fun hopIncludesBothEndpointsAndItsFullHeight() {
        val hop = SpriteMotion(1, "hop", 400, MotionPoint(-20f, 8f), MotionPoint(0f, 0f), 18f)
        assertEquals(MotionPoint(-20f, 8f), hop.point(0))
        val middle = hop.point(200)
        assertEquals(-10f, middle.x, .001f)
        assertEquals(-14f, middle.y, .001f)
        assertEquals(MotionPoint(0f, 0f), hop.point(400))
        assertEquals(MotionPoint(0f, 0f), hop.point(1000))
    }

    @Test fun waitingWhaleSlowsButDoesNotStop() {
        assertEquals(2, whaleForm(0))
        assertEquals(.3, whaleRate(0), 0.0)
        val slowed = approachWhaleRate(1.0, whaleRate(0), .35)
        assertTrue(slowed > .3 && slowed < 1)
    }

    @Test fun continuousFramesStayOnSixtyHertzDeadlines() {
        assertEquals(17L, continuousDelay(0))
        assertEquals(17L, continuousDelay(17))
        assertEquals(16L, continuousDelay(34))
        assertEquals(17L, continuousDelay(1000))
    }
}
